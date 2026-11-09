// Session-level assembly of the M6 quality layer (1.x main.cpp L255-306):
// the three quality controllers are process-wide singletons wired to the
// same settings.json, with the directories the 1.x main() resolved once at
// boot.
//
// 2.0 lifetime adaptation: 1.x held ONE engine for the whole app session
// and called the three startup() routines right after construction. The
// media_kit player is created per playback file instead, so the engine
// attach + the one-shot startup happen on the first player attach
// ([attachPlayer]); every later file re-runs only the event-driven apply
// paths (fileLoaded / video-params / container-fps), exactly the 1.x
// per-file behavior.
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:emoplay/quality/icc_controller.dart';
import 'package:emoplay/quality/interpolation_controller.dart';
import 'package:emoplay/quality/native_quality_engine.dart';
import 'package:emoplay/quality/quality_controller.dart';
import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

class QualityStores {
  QualityStores({
    required EmoPlaySettings settings,
    required this.appDataDir,
    required this.shadersDir,
    required this.scriptsDir,
  })  : quality = QualityController(
          settings: settings,
          shadersDir: shadersDir,
          onError: (message) => EmoLogger().e('quality: $message'),
        ),
        interpolation = InterpolationController(
          settings: settings,
          scriptsDir: scriptsDir,
          onError: (message) => EmoLogger().e('interpolation: $message'),
        ),
        icc = IccController(
          settings: settings,
          appDataDir: appDataDir,
          onError: (message) => EmoLogger().e('icc: $message'),
        );

  final String appDataDir;

  /// The quality panel's shader source: the USER IMPORT directory (1.x
  /// main.cpp L255-268 — an imported mpv config's shaders/ subdirectory
  /// when the import decision was full/selective, otherwise EmoPlay's own
  /// app-data shaders/ directory). The Anime4K 1.x chain table mounts only
  /// files resolved against this directory, so a partial install degrades
  /// gracefully (SPEC §4.5).
  final String shadersDir;

  /// The VapourSynth preset scripts directory: EmoPlay's own app-data vs/
  /// directory (1.x main.cpp L292). The .vpy preset scripts are NOT
  /// shipped; the user drops their own there (e.g. an mpv-Emo vs/ checkout
  /// copy), and the panel shows the expected path per preset.
  final String scriptsDir;

  final QualityController quality;
  final InterpolationController interpolation;
  final IccController icc;

  MpvQualityEngine? _engine;
  bool _startupDone = false;
  Future<void>? _attachFuture;

  /// 1.x main.cpp L255-268, extracted so tests can pin the rule.
  static String resolveShadersDir({
    required String importDecision,
    required String sourceDir,
    required String appDataDir,
  }) {
    if ((importDecision == 'full' || importDecision == 'selective') &&
        sourceDir.isNotEmpty) {
      return '$sourceDir/shaders';
    }
    return '$appDataDir/shaders';
  }

  /// Wires the quality controllers to a freshly created player (called
  /// from the player bootstrap right before the first file opens).
  /// Failures are logged and never block playback.
  Future<void> attachPlayer(Player player) async {
    // Serialize: a rapid open/stop/open sequence must not interleave the
    // attach with the previous engine's teardown.
    final previous = _attachFuture;
    final completer = Completer<void>();
    _attachFuture = completer.future;
    try {
      await previous;
    } catch (_) {}
    try {
      await _attach(player);
    } catch (e) {
      EmoLogger().e('quality: engine attach failed', error: e);
    } finally {
      completer.complete();
    }
  }

  Future<void> _attach(Player player) async {
    detachPlayer();
    final engine = NativeQualityEngine(player);
    await engine.start();
    _engine = engine;
    await quality.attachEngine(engine);
    await interpolation.attachEngine(engine);
    icc.attachEngine(engine);
    if (!_startupDone) {
      // 1.x main.cpp order: quality.startup() -> interpolation.startup()
      // -> icc.startup(), all against the live engine.
      _startupDone = true;
      await quality.startup();
      await interpolation.startup();
      await icc.startup();
    }
  }

  /// Detaches the engine when playback ends (1.x kept the engine alive for
  /// the whole session; the per-file 2.0 player gets disposed by its
  /// owner, so only the listeners are torn down here).
  void detachPlayer() {
    quality.detachEngine();
    interpolation.detachEngine();
    icc.detachEngine();
    _engine?.dispose();
    _engine = null;
  }
}
