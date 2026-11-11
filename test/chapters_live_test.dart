import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:emoplay/pages/player/controller/player_chapters_controller.dart';

// Live half of the M3-T2 chapter tests: the chapter table observation and
// the jump/next/previous rules are verified against a real (idle-then-seek)
// libmpv core exactly like the equalizer live cases — media_kit's native
// assets resolve the bundled libmpv under flutter_test, so the observed
// strings come from the linked mpv, not from a parser fixture.
//
// Fixture: a 9s mp4 built by the system ffmpeg with three chapters written
// through the ffmpeg metadata mechanism (FFMETADATA1 [CHAPTER] sections —
// the section header must be uppercase [CHAPTER], lowercase is silently
// ignored and the titles leak into global metadata).
//
// Harness constraints probed 2026-11-11 against the bundled fork
// ("mpv v0.41.0-11-gf011d73d5-dirty", see mpv_player_properties.dart header):
//   * the fork pre-inits vid=no, so a video-only fixture dies with
//     "No video or audio streams selected" — the fixture carries an audio
//     track and the test pins ao=null (no real audio device needed);
//   * the fork's default demuxer-cache-dir is unwritable under flutter_test
//     ("Failed to create file cache"), so the test redirects it to a temp
//     directory, mirroring what PlayerPlaybackController does in the app.
void main() {
  final ffmpegOnPath = Process.runSync('which', <String>['ffmpeg'])
          .exitCode ==
      0;

  /// Builds the 3-chapter fixture; returns its path.
  Future<String> buildChaptersFixture(Directory dir) async {
    final metadata = File('${dir.path}/chapters.txt');
    await metadata.writeAsString(
      ';FFMETADATA1\n'
      'title=EmoPlay Chapters Fixture\n'
      '[CHAPTER]\n'
      'TIMEBASE=1/1000\n'
      'START=0\n'
      'END=3000\n'
      'title=第一章 开场\n'
      '[CHAPTER]\n'
      'TIMEBASE=1/1000\n'
      'START=3000\n'
      'END=6000\n'
      'title=Second, Chapter & %50%\n'
      '[CHAPTER]\n'
      'TIMEBASE=1/1000\n'
      'START=6000\n'
      'END=9000\n'
      'title=Chapter [3]\n',
    );
    final result = await Process.run(
      'ffmpeg',
      <String>[
        '-y',
        '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=duration=9:size=160x120:rate=10',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=9',
        '-i', metadata.path,
        '-map', '0:v',
        '-map', '1:a',
        '-map_metadata', '2',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '32k',
        '${dir.path}/chapters3.mp4',
      ],
    );
    expect(result.exitCode, 0, reason: 'ffmpeg failed: ${result.stderr}');
    return '${dir.path}/chapters3.mp4';
  }

  Future<T> waitForValue<T>(
    T Function() get,
    bool Function(T) done, {
    required String what,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var value = get();
    while (!done(value)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $what (last value: $value)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      value = get();
    }
    return value;
  }

  test('live libmpv: chapter observation, jump and next/previous', () async {
    expect(ffmpegOnPath, isTrue,
        reason: 'system ffmpeg required to build the chapter fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-chapters-live-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final fixture = await buildChaptersFixture(dir);

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

    final seeks = <Duration>[];
    final chapters = PlayerChaptersController(
      seek: (target) async {
        seeks.add(target);
        await player.seek(target);
      },
      position: () => player.state.position,
    );
    addTearDown(chapters.detach);

    // App order (PlayerController.init): open first, attach afterwards —
    // mpv still fires the initial observation event with the loaded table.
    await player.open(Media(fixture), play: false);
    await chapters.attach(player);

    // The chapter table arrives through the observed property.
    await waitForValue(
      () => chapters.chapters.length,
      (n) => n == 3,
      what: 'observed chapter table (3 entries)',
    );
    expect(chapters.chapters[0].title, '第一章 开场');
    expect(chapters.chapters[1].title, 'Second, Chapter & %50%');
    expect(chapters.chapters[2].title, 'Chapter [3]');
    expect(
      chapters.chapters.map((c) => c.startTime),
      [
        Duration.zero,
        const Duration(seconds: 3),
        const Duration(seconds: 6),
      ],
    );
    // End chaining: chapter N ends where N+1 starts, last runs to the end.
    expect(chapters.chapters[0].endTime, const Duration(seconds: 3));
    expect(chapters.chapters[2].endTime, isNull);

    // mpv reports the active chapter as soon as position time exists.
    await waitForValue(
      () => chapters.currentIndex,
      (n) => n == 0,
      what: 'initial chapter index 0',
    );

    // Jump through the controller: the mpv-native `chapter` property write
    // lands on the chapter start AND mpv reports exactly the target chapter
    // (a plain seek to the start lands 23µs short and reports the previous
    // chapter — probed 2026-11-11, see PlayerChaptersController.jumpToChapter).
    await chapters.jumpToChapter(2);
    expect(seeks, isEmpty,
        reason: 'the mpv-native write must win; the plain seek is only the '
            'degraded fallback');
    await waitForValue(
      () => chapters.currentIndex,
      (n) => n == 2,
      what: 'chapter index 2 after jump',
    );
    final landedAt = await native.getProperty('playback-time');
    expect(
      double.parse(landedAt).round(),
      6,
      reason: 'jump must land on the chapter start, got $landedAt',
    );

    // Previous steps back one chapter (2 -> 1).
    await chapters.previousChapter();
    await waitForValue(
      () => chapters.currentIndex,
      (n) => n == 1,
      what: 'chapter index 1 after previous',
    );

    // Next from there returns to chapter 2.
    await chapters.nextChapter();
    await waitForValue(
      () => chapters.currentIndex,
      (n) => n == 2,
      what: 'chapter index 2 after next',
    );
    // Clamped at the last chapter: still 2, no state change.
    await chapters.nextChapter();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(chapters.currentIndex, 2);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live libmpv: chapterless file keeps the table empty (panel hides)',
      () async {
    expect(ffmpegOnPath, isTrue, reason: 'system ffmpeg required for fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-plain-live-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final result = await Process.run(
      'ffmpeg',
      <String>[
        '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=duration=3:size=160x120:rate=10',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
        '-map', '0:v', '-map', '1:a',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '32k',
        '${dir.path}/plain.mp4',
      ],
    );
    expect(result.exitCode, 0, reason: 'ffmpeg failed: ${result.stderr}');

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

    final chapters = PlayerChaptersController(
      seek: (_) async {},
      position: () => player.state.position,
    );
    addTearDown(chapters.detach);
    await player.open(Media('${dir.path}/plain.mp4'), play: false);
    await chapters.attach(player);

    // Wait past the point where a chaptered file has delivered its table.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(chapters.hasChapters, isFalse,
        reason: 'chapterless media must leave the table empty so the panel '
            'section hides');
    expect(chapters.currentIndex, -1);
    // Navigation stays a safe no-op.
    await chapters.nextChapter();
    await chapters.previousChapter();
    expect(chapters.hasChapters, isFalse);

    // Detach clears the observation and the state.
    await chapters.detach();
    expect(chapters.hasChapters, isFalse);
    expect(() => native.unobserveProperty('chapter-list'),
        throwsArgumentError,
        reason: 'detach must have removed the mpv observations');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
