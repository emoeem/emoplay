import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:emoplay/pages/player/controller/player_subtitles_controller.dart';

// Live half of the M3 字幕管理 tests: the sub-add command surface (select/auto
// flags), the sid-based selection state and the sub-delay stepper are verified
// against a real (idle) libmpv core exactly like the equalizer/chapters live
// cases — media_kit's native assets resolve the bundled libmpv under
// flutter_test, so the observed strings come from the linked mpv, not from a
// parser fixture.
//
// Fixture: an mp4 built by the system ffmpeg (testsrc + sine) plus two
// external .srt files — the 1.x fixture pairing (tests/fixtures/media/hevc.mp4
// + subs-en.srt/subs-zh.srt) rebuilt on the fly. External subs keep the
// fixture container free of subtitle tracks, so every track observed by the
// controller arrives through the controller's own sub-add surface.
//
// Behavior pinned against the bundled fork ("mpv v0.41.0-11-gf011d73d5-dirty",
// probed 2026-11-11):
//   * the fork pre-inits sid=no (stock mpv uses 'auto');
//   * `sub-add <path> select` activates the track (sid = track id), while
//     `sub-add <path> auto` only appends it — sid keeps pointing at the
//     previously selected track;
//   * Player.state.track.subtitle is stale after raw sub-add commands (the
//     fork only refreshes it inside setSubtitleTrack), which is why the
//     controller observes mpv's `sid` property;
//   * sub-delay round-trips through %.6f serialization ("0.500000").
//
// Harness constraints shared with chapters_live_test.dart: the fork needs an
// audio track in the fixture (vid=no pre-init kills video-only files) and a
// writable demuxer-cache-dir; ao=null avoids the audio device.
void main() {
  final ffmpegOnPath =
      Process.runSync('which', <String>['ffmpeg']).exitCode == 0;

  /// Builds the media fixture and two external subtitle files; returns
  /// (media, srt-en, srt-zh) paths.
  Future<(String, String, String)> buildFixtures(Directory dir) async {
    final srtEn = File('${dir.path}/subs-en.srt');
    await srtEn.writeAsString(
      '1\n00:00:00,000 --> 00:00:02,000\nhello\n\n'
      '2\n00:00:02,000 --> 00:00:04,000\nworld\n',
    );
    final srtZh = File('${dir.path}/subs-zh.srt');
    await srtZh.writeAsString(
      '1\n00:00:00,000 --> 00:00:02,000\n你好\n\n'
      '2\n00:00:02,000 --> 00:00:04,000\n世界\n',
    );
    final result = await Process.run(
      'ffmpeg',
      <String>[
        '-y',
        '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=duration=6:size=160x120:rate=10',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=6',
        '-map', '0:v', '-map', '1:a',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '32k',
        '${dir.path}/plain.mp4',
      ],
    );
    expect(result.exitCode, 0, reason: 'ffmpeg failed: ${result.stderr}');
    return ('${dir.path}/plain.mp4', srtEn.path, srtZh.path);
  }

  Future<T> waitForValue<T>(
    FutureOr<T> Function() get,
    bool Function(T) done, {
    required String what,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var value = await get();
    while (!done(value)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $what (last value: $value)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      value = await get();
    }
    return value;
  }

  test('live libmpv: sub-add select/auto, track switching and sub-delay '
      'stepping', () async {
    expect(ffmpegOnPath, isTrue,
        reason: 'system ffmpeg required to build the subtitle fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-subs-live-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final (fixture, srtEn, srtZh) = await buildFixtures(dir);

    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(osc: false),
    );
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;
    final cacheDir = Directory('${dir.path}/mpv-cache')
      ..createSync(recursive: true);
    await native.setProperty('ao', 'null');
    await native.setProperty('demuxer-cache-dir', cacheDir.path);

    final subtitles = PlayerSubtitlesController();
    addTearDown(subtitles.detach);

    // App order (PlayerController.init): open first, attach afterwards —
    // the attach-time state snapshot covers events already dispatched.
    await player.open(Media(fixture), play: false);
    await subtitles.attach(player);

    // The fork pre-inits sid=no: no tracks, no explicit selection.
    await waitForValue(
      () async => (await native.getProperty('sid',
              waitForInitialization: false))
          .trim(),
      (v) => v == 'no',
      what: 'initial sid=no',
    );
    expect(subtitles.tracks, isEmpty);
    expect(subtitles.currentSubId, 'no');
    expect(subtitles.currentTrack, isNull);
    // The stepper reads the engine's initial sub-delay (mpv default 0).
    expect(subtitles.subDelay, 0);

    // --- sub-add with the select flag: loads AND activates the track ---
    await subtitles.loadExternal(srtEn, select: true);
    await waitForValue(
      () => subtitles.tracks.length,
      (n) => n == 1,
      what: 'external track in track-list',
    );
    final enTrack = subtitles.tracks.single;
    expect(enTrack.title, 'subs-en.srt',
        reason: 'sub-add receives the file name (with extension, mpv-native '
            'external-track naming) as the explicit title');
    expect(enTrack.language, isNull,
        reason: 'the command surface passes only path/flag/title');
    await waitForValue(
      () => subtitles.currentSubId,
      (id) => id == enTrack.id,
      what: 'sid follows sub-add select',
    );
    expect(subtitles.currentTrack?.id, enTrack.id);

    // --- sub-add with the auto flag: appends without selecting ---
    await subtitles.loadExternal(srtZh, select: false);
    await waitForValue(
      () => subtitles.tracks.length,
      (n) => n == 2,
      what: 'second external track appended',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(subtitles.currentSubId, enTrack.id,
        reason: 'auto must not move the selection (mpv sid readback)');
    final zhTrack =
        subtitles.tracks.singleWhere((t) => t.title == 'subs-zh.srt');

    // --- switching through the panel surface: setSubtitleTrack -> sid ---
    await subtitles.select(zhTrack);
    await waitForValue(
      () => subtitles.currentSubId,
      (id) => id == zhTrack.id,
      what: 'sid after explicit track switch',
    );

    // --- 关闭字幕: sid=no and the current track clears ---
    await subtitles.selectNone();
    await waitForValue(
      () => subtitles.currentSubId,
      (id) => id == 'no',
      what: 'sid after disable',
    );
    expect(subtitles.currentTrack, isNull);

    // Re-selecting after a disable is tracked the same way.
    await subtitles.select(enTrack);
    await waitForValue(
      () => subtitles.currentSubId,
      (id) => id == enTrack.id,
      what: 'sid after re-select',
    );

    // --- sub-delay stepping: ±0.5 lands in the engine ---
    Future<double> readDelay() async =>
        double.tryParse((await native.getProperty('sub-delay',
                    waitForInitialization: false))
                .trim()) ??
            double.nan;
    expect(await subtitles.adjustSubDelay(0), isFalse,
        reason: 'a zero direction is a no-op');

    expect(await subtitles.adjustSubDelay(1), isTrue);
    expect(subtitles.subDelay, 0.5);
    await waitForValue(readDelay, (v) => v == 0.5,
        what: 'sub-delay property after +0.5');

    expect(await subtitles.adjustSubDelay(1), isTrue);
    expect(subtitles.subDelay, 1.0);
    await waitForValue(readDelay, (v) => v == 1.0,
        what: 'sub-delay property after +1.0');

    // Two steps back from +1.0 land on 0.0, then -0.5.
    expect(await subtitles.adjustSubDelay(-1), isTrue);
    expect(await subtitles.adjustSubDelay(-1), isTrue);
    expect(subtitles.subDelay, 0.0);
    await waitForValue(readDelay, (v) => v == 0.0,
        what: 'sub-delay property back at 0');
    expect(await subtitles.adjustSubDelay(-1), isTrue);
    expect(subtitles.subDelay, -0.5);
    await waitForValue(readDelay, (v) => v == -0.5,
        what: 'sub-delay property at -0.5');

    // --- detach clears the observed state ---
    await subtitles.detach();
    expect(subtitles.tracks, isEmpty);
    expect(subtitles.currentSubId, 'no');
    expect(subtitles.subDelay, 0);
    expect(() => native.unobserveProperty('sid'), throwsArgumentError,
        reason: 'detach must have removed the mpv observation');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live libmpv: without a player the stepper and loader are no-ops',
      () async {
    MediaKit.ensureInitialized();
    final subtitles = PlayerSubtitlesController();
    addTearDown(subtitles.detach);

    // Detached controller: no platform, so every surface is inert.
    expect(await subtitles.adjustSubDelay(1), isFalse);
    expect(subtitles.subDelay, 0);
    await subtitles.loadExternal('/nonexistent.srt', select: true);
    expect(subtitles.tracks, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
