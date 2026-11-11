import 'package:media_kit/media_kit.dart';

import 'package:emoplay/services/logging/logger.dart';

/// frame-step / frame-back-step command surface (M3 施工件 C「逐帧」).
///
/// mpv semantics (verified live against the bundled fork, see
/// test/frame_step_live_test.dart):
///   * `frame-step` — advance one frame, then pause. Also works while
///     playing: mpv unpauses for exactly one frame and re-pauses after it
///     (0.41 add_step_frame + video.c step_frames consumption), so the
///     caller's pre-pause only aligns the UI state earlier;
///   * `frame-back-step` — go one frame back, then pause (mpv notes the
///     backward step is seek-based and can be off by fractions of a frame).
///
/// Fork support check: the shipped libmpv
/// ("mpv v0.41.0-11-gf011d73d5-dirty", build/linux/x64/debug/bundle/lib)
/// exposes both commands in its command table (`strings libmpv.so.2` lists
/// `frame-step` and `frame-back-step`), and the live test issues both
/// successfully — mpv only gained the native `frame-back-step` command in
/// 0.38.0, so any future fork downgrade below that must re-check here.
///
/// Harness caveat (headless tests only): the fork pre-inits `vid=no` until a
/// VideoController attaches (mpv_player_properties.dart header). Without the
/// video chain mpv's add_step_frame early-returns and every step is a silent
/// no-op — live tests must pin `vid=auto`. The player page always attaches a
/// VideoController, so app behavior is unaffected.
class PlayerFrameStepController {
  PlayerFrameStepController({required NativePlayer? Function() platform})
      : _platform = platform;

  final NativePlayer? Function() _platform;

  /// Steps [direction] frames (+1 forward / -1 backward) and reports whether
  /// the command was issued. Safe no-op without a player; failures are logged
  /// and surfaced as false so the UI can ignore them.
  Future<bool> stepBy(int direction) async {
    final platform = _platform();
    if (platform == null) {
      return false;
    }
    try {
      await platform.command(
        direction >= 0 ? const ['frame-step'] : const ['frame-back-step'],
      );
      return true;
    } catch (e) {
      EmoLogger().w(
        'PlayerFrameStepController: frame ${direction >= 0 ? 'forward' : 'backward'} step failed',
        error: e,
      );
      return false;
    }
  }
}
