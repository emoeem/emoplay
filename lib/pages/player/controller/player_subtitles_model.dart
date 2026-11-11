// Pure subtitle-management logic (M3 字幕管理): the sub-delay stepper and the
// track label rules. Kept free of engine calls so the rules are unit-testable
// (test/subtitles_model_test.dart) and the live half only verifies the mpv
// plumbing (test/subtitles_live_test.dart).

/// mpv 惯例的步进由 1.x 倍速键位语义推到字幕延迟：±0.5s 一步（M3 施工件 B）。
const double kSubDelayStep = 0.5;

/// Next sub-delay after one UI step.
///
/// [direction] is +1 (推迟字幕，mpv `sub-delay +`) or -1 (提前字幕)；0 leaves
/// the value untouched. The result is rounded to one decimal: mpv reports
/// `sub-delay` with %.6f formatting ("0.500000") and repeated additions would
/// otherwise accumulate binary-fraction drift (0.30000000000000004-style),
/// which the HUD would faithfully display. One decimal is finer than the
/// 0.5s step, so rounding never changes a step's magnitude.
double nextSubDelay(double current, int direction) {
  if (direction == 0) {
    return _normalizeZero(current);
  }
  final stepped = current + direction * kSubDelayStep;
  return _normalizeZero((stepped * 10).roundToDouble() / 10);
}

double _normalizeZero(double value) => value == 0 ? 0.0 : value;

/// HUD text for a sub-delay value: sign + one decimal, e.g. `+0.5s`,
/// `-1.0s`, `0.0s` (zero is unsigned; -0.0 normalizes to `0.0s`).
String formatSubDelay(double delay) {
  final normalized = _normalizeZero(delay);
  if (normalized == 0) {
    return '0.0s';
  }
  final sign = normalized < 0 ? '-' : '+';
  return '$sign${normalized.abs().toStringAsFixed(1)}s';
}

/// Label of a subtitle track in the switching panel.
///
/// mpv's track-list gives external files the title passed to `sub-add` (the
/// picker surface sends the file name) and container subs whatever the file
/// declares; both may be absent, then the language tag and finally the
/// 1-based position carry the label.
String describeSubtitleTrack(String? title, String? language, int index) {
  final cleanTitle = title?.trim();
  if (cleanTitle != null && cleanTitle.isNotEmpty) {
    return cleanTitle;
  }
  final cleanLanguage = language?.trim();
  if (cleanLanguage != null && cleanLanguage.isNotEmpty) {
    return cleanLanguage;
  }
  return '字幕轨道 $index';
}
