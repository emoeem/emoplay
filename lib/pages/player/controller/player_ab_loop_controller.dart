// ignore_for_file: library_private_types_in_public_api

import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

import 'package:emoplay/pages/player/controller/ab_loop_model.dart';
import 'package:emoplay/services/logging/logger.dart';

part 'player_ab_loop_controller.g.dart';

/// A-B loop state for the current playback (M3 施工件 C「A-B 循环」).
///
/// Owns the NativePlayer observation of mpv's `ab-loop-a` / `ab-loop-b`
/// (time-or-`no` properties, observed with MPV_FORMAT_NONE → the fork
/// dispatches the value as a string, same channel as the chapter table). All
/// transitions go through the pure machine in [ab_loop_model.dart]; this
/// class only translates accepted transitions into `setProperty` writes and
/// observed strings back into marks.
///
/// One instance lives on [PlayerController]; attached to each freshly created
/// player after `open` (an mpv observation always fires an initial event, so
/// attaching post-load still receives current values) and detached in the
/// shared release path.
class PlayerAbLoopController = _PlayerAbLoopController
    with _$PlayerAbLoopController;

abstract class _PlayerAbLoopController with Store {
  _PlayerAbLoopController({required double? Function() position})
      : _position = position;

  final double? Function() _position;

  NativePlayer? _platform;

  /// mpv `ab-loop-a` in seconds; null while unset (`no`).
  @observable
  double? positionA;

  /// mpv `ab-loop-b` in seconds; null while unset (`no`).
  @observable
  double? positionB;

  @computed
  PlayerAbLoopPhase get phase => PlayerAbLoopPhase.of(positionA, positionB);

  @action
  void _applyObservation(String property, String value) {
    final parsed = parseMpvAbLoopPosition(value);
    if (property == 'ab-loop-a') {
      positionA = parsed;
    } else {
      positionB = parsed;
    }
  }

  /// Starts observing on [player] (idempotent: re-attach first detaches).
  Future<void> attach(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    await detach();
    _platform = platform;
    try {
      await platform.observeProperty(
        'ab-loop-a',
        (value) async {
          _applyObservation('ab-loop-a', value);
        },
        waitForInitialization: false,
      );
      await platform.observeProperty(
        'ab-loop-b',
        (value) async {
          _applyObservation('ab-loop-b', value);
        },
        waitForInitialization: false,
      );
    } catch (e) {
      EmoLogger().w(
        'PlayerAbLoopController: failed to observe ab-loop properties',
        error: e,
      );
    }
  }

  /// Stops observing and clears state. Safe to call repeatedly and after the
  /// player has already been disposed (the unobserve calls are guarded).
  Future<void> detach() async {
    final platform = _platform;
    _platform = null;
    _setMarks(null, null);
    if (platform == null) {
      return;
    }
    for (final property in const ['ab-loop-a', 'ab-loop-b']) {
      try {
        await platform.unobserveProperty(property);
      } catch (_) {
        // Already unobserved or the player is gone — nothing left to clean.
      }
    }
  }

  @action
  void _setMarks(double? a, double? b) {
    positionA = a;
    positionB = b;
  }

  /// Runs one step of the mpv-convention cycle (L key / panel menu entry).
  ///
  /// The transition is decided by the pure machine first; only accepted
  /// transitions reach mpv as `ab-loop-a` / `ab-loop-b` writes. The state
  /// then settles through the property observations (mpv echoes every
  /// change), so a failed write cannot desync the store.
  ///
  /// Returns null when there is no player; otherwise the outcome (accepted
  /// or rejected with a reason) for the caller's OSD.
  Future<AbLoopCycleOutcome?> cycleAbLoop() async {
    return _runTransition(AbLoopAction.cycle);
  }

  /// Clears the loop from any phase (no-op when nothing is marked).
  Future<AbLoopCycleOutcome?> clearAbLoop() async {
    if (PlayerAbLoopPhase.of(positionA, positionB) == PlayerAbLoopPhase.none) {
      return AbLoopCycleOutcome(
        accepted: true,
        phase: PlayerAbLoopPhase.none,
        positionA: null,
        positionB: null,
      );
    }
    return _runTransition(AbLoopAction.clear);
  }

  Future<AbLoopCycleOutcome?> _runTransition(AbLoopAction action) async {
    final platform = _platform;
    if (platform == null) {
      return null;
    }
    final transition = applyAbLoopAction(
      action,
      positionA: positionA,
      positionB: positionB,
      position: _position(),
    );
    if (!transition.accepted) {
      return AbLoopCycleOutcome(
        accepted: false,
        phase: phase,
        positionA: positionA,
        positionB: positionB,
        reason: transition.reason,
      );
    }
    try {
      await platform.setProperty(
        'ab-loop-a',
        transition.positionA?.toStringAsFixed(3) ?? 'no',
      );
      await platform.setProperty(
        'ab-loop-b',
        transition.positionB?.toStringAsFixed(3) ?? 'no',
      );
    } catch (e) {
      EmoLogger().w(
        'PlayerAbLoopController: ab-loop property write failed',
        error: e,
      );
      return AbLoopCycleOutcome(
        accepted: false,
        phase: phase,
        positionA: positionA,
        positionB: positionB,
        reason: 'A-B 循环设置失败',
      );
    }
    // Optimistic local settle: mpv's echo event confirms it right after, but
    // a rapid double-press (L L) must decide its second step on the first
    // step's result, not on a stale pre-event snapshot.
    _setMarks(transition.positionA, transition.positionB);
    return AbLoopCycleOutcome(
      accepted: true,
      phase: transition.phase,
      positionA: transition.positionA,
      positionB: transition.positionB,
    );
  }
}
