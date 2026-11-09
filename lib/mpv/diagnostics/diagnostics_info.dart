// Diagnostics for the settings page (SPEC §6 category 10:
// appVersion/mpvVersion/renderBackend/dataDir/configDir/logDir — 全部运行时
// 读取). Dart counterpart of mpv-emo src/app/DiagnosticsInfo.{h,cpp}, with
// the Qt-specific fields replaced by their Flutter-stack equivalents:
//
//   appVersion     compile-time constant (utils/constants.dart), the
//                  EMOPLAY_VERSION define of 1.x
//   mpvVersion     read live from the attached player's `mpv-version`
//                  property; 1.x re-queried lazily for the same reason —
//                  mpv only reports the version once the client exists
//   renderBackend  1.x reported the forced QSG_RHI_BACKEND (the mpv render
//                  context was built on QOpenGLContext). 2.0 renders through
//                  media_kit's libmpv render API, so the honest runtime read
//                  is the live `gpu-context` / `current-vo` pair — no
//                  env-var guess
//   dataDir        the application support directory (every JSON store,
//                  plugin state and thumbnail cache lives there)
//   configDir      EmoPlay keeps ONE tree: the application support directory
//                  doubles as the config home (1.x split
//                  AppDataLocation/AppConfigLocation; nothing in 2.0 writes
//                  a second directory)
//   logDir         <support>/logs (services/logging/logger.dart)
library;

import 'package:media_kit/media_kit.dart';

import 'package:emoplay/utils/constants.dart' as meta;

/// One collected read of the live-engine values (the two that need a
/// player); the static ones come straight off [DiagnosticsInfo].
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.mpvVersion,
    required this.renderBackend,
  });

  final String mpvVersion;
  final String renderBackend;
}

class DiagnosticsInfo {
  DiagnosticsInfo({required this.appDataDir, Player? Function()? playerProvider})
      : _playerProvider = playerProvider;

  final String appDataDir;
  final Player? Function()? _playerProvider;

  String get appVersion => meta.appVersion;

  String get dataDir => appDataDir;

  String get configDir => appDataDir;

  String get logDir => '$appDataDir/logs';

  NativePlayer? get _platform {
    final player = _playerProvider?.call();
    if (player == null || player.platform is! NativePlayer) {
      return null;
    }
    return player.platform as NativePlayer;
  }

  /// The live libmpv version string; "unknown" while no player is attached
  /// (1.x behaviour: never cached as unknown — every call re-reads).
  Future<String> mpvVersion() async {
    final platform = _platform;
    if (platform == null) {
      return 'unknown';
    }
    try {
      final version = await platform.getProperty('mpv-version');
      return version.isEmpty ? 'unknown' : version;
    } catch (_) {
      return 'unknown';
    }
  }

  /// The rendering path the current player uses: the mpv `gpu-context` when
  /// one is active, otherwise the `current-vo` value (libmpv render API),
  /// otherwise "unknown" (no player).
  Future<String> renderBackend() async {
    final platform = _platform;
    if (platform == null) {
      return 'unknown';
    }
    try {
      final context = await platform.getProperty('gpu-context');
      if (context.isNotEmpty) {
        return context;
      }
      final vo = await platform.getProperty('current-vo');
      return vo.isEmpty ? 'unknown' : vo;
    } catch (_) {
      return 'unknown';
    }
  }
}
