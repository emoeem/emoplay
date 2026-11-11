// Pure A-B loop state machine and mpv string parsing (M3 施工件 C「A-B 循环」).
//
// mpv command surface covered by the model:
//   * `ab-loop-a` / `ab-loop-b` — time-or-`no` properties; a loop is armed
//     exactly when both hold a position. The three UI states map to:
//     none (both `no`) → aSet (A marked) → looping (A+B marked) → clear
//     (both `no` again).
//   * The mpv-convention `L` key (mpv builtin input.conf binds `L` to the
//     `ab-loop` cycle command) is served by [applyAbLoopAction] with
//     [AbLoopAction.cycle], which reproduces that command's three-step cycle
//     while adding a guard mpv leaves undefined: a B mark at or before A is
//     rejected client-side.
//
// Pure logic only — no media_kit, no mpv handle, fully unit-testable (the
// live half lives in PlayerAbLoopController + test/frame_step_live_test.dart).

/// The three UI states of the A-B loop feature.
enum PlayerAbLoopPhase {
  /// No mark: both `ab-loop-a` and `ab-loop-b` are `no`.
  none,

  /// A marked, B still open.
  aSet,

  /// A and B marked; mpv loops A→B.
  looping;

  /// 中文 OSD 标签（播放器 HUD / 菜单项共用）。
  String get label => switch (this) {
        PlayerAbLoopPhase.none => 'A-B 循环',
        PlayerAbLoopPhase.aSet => 'A-B 循环：A 已标记',
        PlayerAbLoopPhase.looping => 'A-B 循环中',
      };

  /// Derives the phase from the two observed mpv properties (seconds; null
  /// when the property reads `no`).
  static PlayerAbLoopPhase of(double? positionA, double? positionB) {
    if (positionA == null) {
      return PlayerAbLoopPhase.none;
    }
    return positionB == null ? PlayerAbLoopPhase.aSet : PlayerAbLoopPhase.looping;
  }
}

/// One user-facing step of the three-state cycle.
enum AbLoopAction { markA, markB, clear, cycle }

/// Outcome of a pure transition; [accepted] is false when the requested mark
/// was refused (no state change, caller should show the reason).
class AbLoopTransition {
  const AbLoopTransition({
    required this.accepted,
    this.positionA,
    this.positionB,
    this.reason,
  });

  final bool accepted;
  final double? positionA;
  final double? positionB;

  /// Rejection reason (Chinese, OSD-ready); null when accepted.
  final String? reason;

  PlayerAbLoopPhase get phase => PlayerAbLoopPhase.of(positionA, positionB);
}

/// Result of one A-B cycle step, for the player-side OSD (PlayerAbLoopHud).
class AbLoopCycleOutcome {
  const AbLoopCycleOutcome({
    required this.accepted,
    required this.phase,
    required this.positionA,
    required this.positionB,
    this.reason,
  });

  final bool accepted;
  final PlayerAbLoopPhase phase;
  final double? positionA;
  final double? positionB;

  /// Rejection reason (Chinese); null when accepted.
  final String? reason;

  /// OSD 一行文案：接受时报告新状态，拒绝时给出原因。
  String get message {
    if (!accepted) {
      return reason ?? 'A-B 循环操作无效';
    }
    return switch (phase) {
      PlayerAbLoopPhase.none => 'A-B 循环已清除',
      PlayerAbLoopPhase.aSet =>
        'A 点 ${formatAbLoopPosition(positionA!)}（再次按 L 标记 B 点）',
      PlayerAbLoopPhase.looping =>
        '循环 ${formatAbLoopPosition(positionA!)} → ${formatAbLoopPosition(positionB!)}',
    };
  }
}

/// Maps [AbLoopAction] onto the three-state machine (the cycle resolves
/// first, so the switch below never sees [AbLoopAction.cycle]).
AbLoopAction _resolveAction(
  AbLoopAction action, {
  required double? positionA,
  required double? positionB,
}) =>
    action == AbLoopAction.cycle
        ? switch (PlayerAbLoopPhase.of(positionA, positionB)) {
            PlayerAbLoopPhase.none => AbLoopAction.markA,
            PlayerAbLoopPhase.aSet => AbLoopAction.markB,
            PlayerAbLoopPhase.looping => AbLoopAction.clear,
          }
        : action;

/// Applies [action] to the current marks.
///
/// Cycle rule (mirrors mpv's `ab-loop` command): none→markA, aSet→markB,
/// looping→clear. Explicit [AbLoopAction.markA]/[markB]/[clear] force the
/// respective step from any phase (the panel menu uses those to keep its
/// label honest even when the phase drifted mid-open).
///
/// Guards:
///   * [AbLoopAction.markB] (or the cycle's markB step) requires [position] >
///     positionA; marking B at or before A is rejected — mpv leaves a B
///     before A undefined (the manual only defines the loop for A ≤ B), so
///     the client refuses instead of arming a broken range.
///   * [position] must be finite; null/NaN/Inf marks are rejected.
AbLoopTransition applyAbLoopAction(
  AbLoopAction action, {
  required double? positionA,
  required double? positionB,
  double? position,
}) {
  final resolved = _resolveAction(
    action,
    positionA: positionA,
    positionB: positionB,
  );

  switch (resolved) {
    case AbLoopAction.markA || AbLoopAction.cycle:
      final mark = _validPosition(position);
      if (mark == null) {
        return AbLoopTransition(
          accepted: false,
          positionA: positionA,
          positionB: positionB,
          reason: '无法获取当前位置',
        );
      }
      // Re-marking A restarts the pair: a stale B would corrupt the range.
      return AbLoopTransition(accepted: true, positionA: mark);
    case AbLoopAction.markB:
      final mark = _validPosition(position);
      if (mark == null) {
        return AbLoopTransition(
          accepted: false,
          positionA: positionA,
          positionB: positionB,
          reason: '无法获取当前位置',
        );
      }
      if (positionA == null) {
        return AbLoopTransition(
          accepted: false,
          positionA: positionA,
          positionB: positionB,
          reason: '请先标记 A 点',
        );
      }
      if (mark <= positionA) {
        return AbLoopTransition(
          accepted: false,
          positionA: positionA,
          positionB: positionB,
          reason: 'B 点必须晚于 A 点',
        );
      }
      return AbLoopTransition(
        accepted: true,
        positionA: positionA,
        positionB: mark,
      );
    case AbLoopAction.clear:
      return const AbLoopTransition(accepted: true);
  }
}

double? _validPosition(double? position) {
  if (position == null) {
    return null;
  }
  if (position.isNaN || position.isInfinite || position < 0) {
    return null;
  }
  return position;
}

/// Parses the observed string of `ab-loop-a` / `ab-loop-b` (the fork delivers
/// observed properties through `readNativeString`, same channel as the
/// chapter table).
///
/// Accepts:
///   * `no` / empty / `""` → null (property unset);
///   * plain seconds `12.345` / `2.000000` → seconds;
///   * mpv time grammar `M:SS.mmm` / `H:MM:SS.mmm` → seconds.
/// Anything else → null (display falls back to hiding the mark).
double? parseMpvAbLoopPosition(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == 'no') {
    return null;
  }
  final segments = text.split(':');
  if (segments.length > 3) {
    return null;
  }
  var seconds = 0.0;
  for (final segment in segments) {
    final value = double.tryParse(segment);
    if (value == null || value.isNaN || value.isInfinite) {
      return null;
    }
    seconds = seconds * 60 + value;
  }
  if (seconds < 0) {
    return null;
  }
  return seconds;
}

/// Formats a mark position for the OSD/菜单 label: `M:SS.d`（超过一小时进位到
/// H:MM:SS.d）。
String formatAbLoopPosition(double seconds) {
  // Round to tenths first so 59.96 renders as 1:00.0, not 0:59.9→溢出截断.
  final tenthsTotal = (seconds < 0 ? 0.0 : seconds * 10).round();
  final wholeSeconds = tenthsTotal ~/ 10;
  final tenths = tenthsTotal % 10;
  final hours = wholeSeconds ~/ 3600;
  final minutes = (wholeSeconds % 3600) ~/ 60;
  final secs = wholeSeconds % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final base =
      '${hours > 0 ? '$hours:' : ''}$mm:${secs.toString().padLeft(2, '0')}';
  return '$base.$tenths';
}
