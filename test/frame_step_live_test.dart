import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:emoplay/pages/player/controller/ab_loop_model.dart';
import 'package:emoplay/pages/player/controller/player_ab_loop_controller.dart';
import 'package:emoplay/pages/player/controller/player_frame_step_controller.dart';

// Live half of the M3 施工件 C tests, driven against a real libmpv core
// exactly like chapters_live_test.dart — media_kit's native assets resolve
// the bundled fork under flutter_test, so every command/property here goes
// through the linked mpv, not a stub.
//
// What this pins down:
//   * frame-step / frame-back-step exist AND work on the shipped fork
//     ("mpv v0.41.0-11-gf011d73d5-dirty"; `frame-back-step` only exists
//     since mpv 0.38.0, so a fork downgrade breaks this file on purpose);
//   * a paused frame-step advances playback-time by exactly one frame of the
//     fixture and stays paused; frame-back-step goes back;
//   * a frame-step from the playing state pauses the core (mpv 0.41
//     add_step_frame: step_frames=1 + unpause, video.c re-pauses after the
//     frame — probed live, see the harness note below);
//   * the A-B loop command surface really arms mpv: the observed
//     ab-loop-a/b properties echo the writes, a B ≤ A cycle is rejected,
//     and a playing file with A=2/B=4 keeps wrapping instead of ending.
//
// Harness constraints (same probes as chapters_live_test.dart, 2026-11-11,
// plus one of our own probed 2026-11-12):
//   * the fork pre-inits vid=no ("prevent redundant video decoding",
//     real.dart `_create`, documented in mpv_player_properties.dart) until a
//     VideoController attaches — with vo_chain absent, mpv's
//     add_step_frame (playloop.c:217 `if (!mpctx->vo_chain) return;`)
//     silently drops every frame step. Headless tests therefore pin
//     `vid=auto` to restore the video chain. The real player page always has
//     a VideoController attached, so the app path is unaffected.
//   * the fixture carries an audio track and the test pins ao=null (no real
//     audio device needed);
//   * the fork's default demuxer-cache-dir is unwritable under flutter_test,
//     so it is redirected to a temp directory.
void main() {
  final ffmpegOnPath = Process.runSync('which', <String>['ffmpeg']).exitCode ==
      0;

  /// 9s 10fps fixture (frame = 0.1s) with an audio track.
  Future<String> buildFixture(Directory dir) async {
    final result = await Process.run(
      'ffmpeg',
      <String>[
        '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=duration=9:size=160x120:rate=10',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=9',
        '-map', '0:v', '-map', '1:a',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '32k',
        '${dir.path}/fixture9s.mp4',
      ],
    );
    expect(result.exitCode, 0, reason: 'ffmpeg failed: ${result.stderr}');
    return '${dir.path}/fixture9s.mp4';
  }

  Future<void> waitForValueStrict(
    bool Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
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

  Future<Player> openPlayer(String fixture, Directory dir,
      {bool play = false}) async {
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(osc: false),
    );
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;
    final cacheDir = Directory('${dir.path}/mpv-cache')
      ..createSync(recursive: true);
    await native.setProperty('ao', 'null');
    // See the harness note: the fork's vid=no pre-init strips the video chain
    // and with it the entire frame-step path (add_step_frame needs vo_chain).
    await native.setProperty('vid', 'auto');
    await native.setProperty('demuxer-cache-dir', cacheDir.path);
    await player.open(Media(fixture), play: play);
    // Wait until the file is actually loaded (duration known) so playback-time
    // reads a number instead of mpv's "no".
    await waitForValueStrict(
      () => player.state.duration.inMilliseconds > 0,
      what: 'fixture duration to be known',
    );
    return player;
  }

  /// playback-time read straight from mpv (string → seconds), bypassing any
  /// media_kit state throttling.
  Future<double> mpvTime(NativePlayer native) async {
    final raw = await native.getProperty('playback-time');
    return double.parse(raw);
  }

  Future<void> settle(Duration ms) => Future<void>.delayed(ms);

  test('live libmpv: paused frame-step advances one frame, back-step returns',
      () async {
    expect(ffmpegOnPath, isTrue,
        reason: 'system ffmpeg required to build the fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-frame-live-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final fixture = await buildFixture(dir);
    final player = await openPlayer(fixture, dir);
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;

    final steps = PlayerFrameStepController(platform: () => native);

    expect(player.state.playing, isFalse);
    // Start from a decoded mid-file frame: at t=0 the first step lands on
    // frame 0 whose PTS is 0.0 (position does not move), so seek to 1.0s
    // first to make "advance by one frame" observable.
    await player.seek(const Duration(seconds: 1));
    await settle(const Duration(milliseconds: 400));
    final before = await mpvTime(native);
    expect((before - 1.0).abs(), lessThan(0.3),
        reason: 'paused seek lands near 1.0, got $before');

    // One forward step: exactly one frame (0.1s at 10fps), still paused.
    expect(await steps.stepBy(1), isTrue,
        reason: 'frame-step must be accepted by the shipped libmpv');
    await settle(const Duration(milliseconds: 400));
    final afterStep = await mpvTime(native);
    expect(afterStep, greaterThan(before),
        reason: 'frame-step must advance playback-time');
    expect(afterStep - before, lessThan(0.5),
        reason: 'a single step must not jump, got ${afterStep - before}s');
    expect(player.state.playing, isFalse,
        reason: 'frame-step leaves the player paused');

    // A second step advances again.
    expect(await steps.stepBy(1), isTrue);
    await settle(const Duration(milliseconds: 400));
    final afterSecond = await mpvTime(native);
    expect(afterSecond, greaterThan(afterStep));

    // Backward step returns below the position it started from (mpv notes
    // the backward step is seek-based, so only "strictly back" is pinned).
    expect(await steps.stepBy(-1), isTrue,
        reason: 'frame-back-step must be accepted by the shipped libmpv');
    await settle(const Duration(milliseconds: 400));
    final afterBack = await mpvTime(native);
    expect(afterBack, lessThan(afterSecond),
        reason: 'frame-back-step must go back');
    expect(afterSecond - afterBack, lessThan(1.0),
        reason: 'back-step is one frame, got ${afterSecond - afterBack}s');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live libmpv: frame-step from the playing state pauses mid-file',
      () async {
    expect(ffmpegOnPath, isTrue, reason: 'system ffmpeg required for fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-frame-live2-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final fixture = await buildFixture(dir);
    final player = await openPlayer(fixture, dir);
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;

    final steps = PlayerFrameStepController(platform: () => native);

    // Reproduce the PlayerController.frameStep order: seek to a known spot,
    // start playback, then step.
    await player.seek(const Duration(seconds: 1));
    await settle(const Duration(milliseconds: 300));
    await player.play();
    await waitForValueStrict(
      () => player.state.playing,
      what: 'playback to start',
    );

    expect(await steps.stepBy(1), isTrue);
    await waitForValueStrict(
      () => !player.state.playing,
      what: 'frame-step to pause the playing core',
    );
    // The step must have paused NEAR the marked spot, not run to EOF — this
    // guards against the audio-only EOF false positive (before the vid=auto
    // fix this test "passed" because the 9s file simply ended).
    final t = await mpvTime(native);
    expect(t, greaterThan(0.8));
    expect(t, lessThan(2.0),
        reason: 'the pause must come from the frame step, got $t');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live libmpv: ab-loop cycle arms mpv, loops while playing, clears',
      () async {
    expect(ffmpegOnPath, isTrue, reason: 'system ffmpeg required for fixture');
    final dir = Directory.systemTemp.createTempSync('emoplay-abloop-live-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final fixture = await buildFixture(dir);
    final player = await openPlayer(fixture, dir);
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;

    final abLoop = PlayerAbLoopController(
      position: () => player.state.position.inMilliseconds / 1000.0,
    );
    addTearDown(abLoop.detach);
    await abLoop.attach(player);

    expect(abLoop.phase, PlayerAbLoopPhase.none,
        reason: 'a fresh file starts with both marks unset');

    // 设 A at 2.0s.
    await player.seek(const Duration(seconds: 2));
    await settle(const Duration(milliseconds: 400));
    final markA = await abLoop.cycleAbLoop();
    expect(markA, isNotNull);
    expect(markA!.accepted, isTrue);
    expect(markA.phase, PlayerAbLoopPhase.aSet);
    // mpv echoes the write through the observation channel.
    await waitForValue(
      () => abLoop.positionA,
      (a) => a != null && (a - 2.0).abs() < 0.2,
      what: 'observed ab-loop-a ≈ 2.0 (got ${abLoop.positionA})',
    );
    expect(abLoop.positionB, isNull);
    expect(await native.getProperty('ab-loop-b'), 'no');

    // 设 B: rejected first when it would sit before A, accepted once the
    // position passes A.
    await player.seek(const Duration(seconds: 1));
    await settle(const Duration(milliseconds: 400));
    final rejected = await abLoop.cycleAbLoop();
    expect(rejected!.accepted, isFalse,
        reason: 'B at 1.0s sits before A at 2.0s');
    expect(rejected.reason, 'B 点必须晚于 A 点');
    expect(await native.getProperty('ab-loop-b'), 'no',
        reason: 'a rejected cycle must not touch mpv');

    await player.seek(const Duration(seconds: 4, milliseconds: 500));
    await settle(const Duration(milliseconds: 400));
    final markB = await abLoop.cycleAbLoop();
    expect(markB!.accepted, isTrue);
    expect(markB.phase, PlayerAbLoopPhase.looping);
    await waitForValue(
      () => abLoop.positionB,
      (b) => b != null && (b - 4.5).abs() < 0.2,
      what: 'observed ab-loop-b ≈ 4.5 (got ${abLoop.positionB})',
    );

    // The loop actually loops: from 0 with play on, the file would run to
    // 9s and complete; with A=2/B=4 armed it must still be looping inside
    // the window well past that point.
    await player.seek(Duration.zero);
    await settle(const Duration(milliseconds: 200));
    await player.play();
    await Future<void>.delayed(const Duration(seconds: 13));
    expect(player.state.completed, isFalse,
        reason: 'an armed A-B loop must keep the 9s file from ending');
    final loopingTime = await mpvTime(native);
    expect(loopingTime, lessThan(5.5),
        reason:
            'playback must still be inside the A-B window, got $loopingTime');

    // 清除 (third cycle step).
    await abLoop.clearAbLoop();
    await waitForValue(
      () => abLoop.phase,
      (phase) => phase == PlayerAbLoopPhase.none,
      what: 'phase none after clear',
    );
    expect(await native.getProperty('ab-loop-a'), 'no');
    expect(await native.getProperty('ab-loop-b'), 'no');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
