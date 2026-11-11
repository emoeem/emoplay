import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/pages/player/controller/player_subtitles_model.dart';

// Pure half of the M3 字幕管理 tests: the sub-delay stepper math and the
// subtitle-track label rules, engine-free (the mpv plumbing behind them is
// verified against a real libmpv core in test/subtitles_live_test.dart,
// same split as equalizer_test / chapters_live_test).
void main() {
  test('subDelayStepIsHalfSecond', () {
    expect(kSubDelayStep, 0.5);
  });

  test('nextSubDelayStepsBothDirections', () {
    expect(nextSubDelay(0, 1), 0.5);
    expect(nextSubDelay(0, -1), -0.5);
    expect(nextSubDelay(0.5, 1), 1.0);
    expect(nextSubDelay(0.5, -1), 0.0);
    expect(nextSubDelay(-0.5, 1), 0.0);
    expect(nextSubDelay(-0.5, -1), -1.0);
    // Zero direction is an explicit no-op.
    expect(nextSubDelay(0.25, 0), 0.25);
    // Unbounded like mpv's sub-delay (no artificial clamp).
    expect(nextSubDelay(120.0, 1), 120.5);
    expect(nextSubDelay(-120.0, -1), -120.5);
  });

  test('nextSubDelayDoesNotAccumulateFloatDrift', () {
    // mpv reports sub-delay as %.6f ("0.100000"); naive repeated addition
    // drifts (0.1 + 0.5*3 = 1.6000000000000003). The stepper rounds to one
    // decimal — finer than the 0.5s step, so magnitudes never change.
    var delay = 0.1;
    for (var i = 0; i < 3; i++) {
      delay = nextSubDelay(delay, 1);
    }
    expect(delay, 1.6);
    expect(delay.toStringAsFixed(1), '1.6');
  });

  test('nextSubDelayNormalizesNegativeZero', () {
    expect(nextSubDelay(-0.0, 1), 0.5);
    // -0.5 + 0.5 lands on negative zero in IEEE-754 without the guard.
    expect(nextSubDelay(-0.5, 1).isNegative, isFalse);
    expect(formatSubDelay(nextSubDelay(-0.5, 1)), '0.0s');
    // A zero-direction no-op still normalizes -0.0 to +0.0.
    expect(nextSubDelay(-0.0, 0).isNegative, isFalse);
  });

  test('formatSubDelaySignAndPrecision', () {
    expect(formatSubDelay(0), '0.0s');
    expect(formatSubDelay(0.0), '0.0s');
    expect(formatSubDelay(0.5), '+0.5s');
    expect(formatSubDelay(-0.5), '-0.5s');
    expect(formatSubDelay(1.0), '+1.0s');
    expect(formatSubDelay(-1.0), '-1.0s');
    expect(formatSubDelay(12.5), '+12.5s');
    // mpv's %.6f readback parse → clean HUD text.
    expect(formatSubDelay(double.parse('0.500000')), '+0.5s');
    expect(formatSubDelay(double.parse('-1.000000')), '-1.0s');
  });

  test('describeSubtitleTrackPrefersTitle', () {
    expect(describeSubtitleTrack('subs-en', 'en', 1), 'subs-en');
    // A whitespace-only title counts as absent.
    expect(describeSubtitleTrack('  ', 'en', 1), 'en');
  });

  test('describeSubtitleTrackFallsBackToLanguageThenIndex', () {
    expect(describeSubtitleTrack(null, 'zh', 2), 'zh');
    expect(describeSubtitleTrack(null, null, 3), '字幕轨道 3');
    expect(describeSubtitleTrack('', '', 1), '字幕轨道 1');
  });
}
