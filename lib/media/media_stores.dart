import 'dart:async';

import 'package:path_provider/path_provider.dart';

import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';
import 'package:emoplay/mpv/compat/compat_controller.dart';
import 'package:emoplay/mpv/compat/mpv_profile_scanner.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/quality/quality_stores.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

// The JSON data layer of the app, assembled once at startup (1.x main.cpp
// lines ~230-244): settings.json, library.json + library scan worker,
// history.json, and the ffmpeg thumbnail cache under AppData/thumbnails.
//
// Lifetime follows the GStorage convention (services/storage/storage.dart):
// a root-owned static service initialized in main() before runApp — the
// stores are process-wide singletons, not page-scoped state, so they do not
// belong in a route's provide callback.
//
// Engine-driven history recording (file-loaded -> recordPlayback, the 5 s
// position refresh against a live mpv core) is wired when the
// PlaybackController port lands; until then the history engine is null and
// those paths stay guarded no-ops, exactly like the 1.x headless mode.
class MediaStores {
  MediaStores._({
    required this.settings,
    required this.library,
    required this.history,
    required this.thumbnails,
    required this.compat,
    required this.quality,
    required this.startupMpvProperties,
  }) {
    libraryModel = LibraryModel(library, thumbnails);
  }

  static MediaStores? _instance;

  /// True once [init] succeeded; pages assert [instance] after startup.
  static bool get isReady => _instance != null;

  /// The assembled stores. Throws a [StateError] before [init] — pages are
  /// only reachable on the successful startup path.
  static MediaStores get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('MediaStores.init() has not completed');
    }
    return instance;
  }

  final EmoPlaySettings settings;
  final LibraryStore library;
  final HistoryStore history;
  final ThumbnailService thumbnails;

  // The mpv compat layer (M5): decision persistence + config-dir scan +
  // startup option assembly (1.x CompatController, main.cpp L170-223).
  final CompatController compat;

  // The quality layer (M6): profile decision table / VapourSynth
  // interpolation / ICC controllers wired to the live engine per playback
  // session (1.x QualityController + InterpolationController +
  // IccController, main.cpp L255-306).
  final QualityStores quality;

  // The assembled mpv property preset applied at player creation:
  // compat options -> plugin scripts appended -> player initialization
  // (1.x main.cpp assembly order). Computed once here — a wizard choice
  // made mid-session applies on the NEXT launch, exactly like 1.x.
  final Map<String, String> startupMpvProperties;

  // The grid/list view over the library store with the thumbnail wiring.
  late final LibraryModel libraryModel;

  /// Resolve the application support directory once and build every store
  /// under it: settings.json / library.json / history.json / thumbnails/.
  /// Store constructors take explicit file paths, so tests build the stores
  /// directly against temporary directories (the 1.x QTemporaryDir pattern)
  /// instead of calling this.
  static Future<void> init() async {
    if (_instance != null) {
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final settings = EmoPlaySettings('${dir.path}/settings.json');
    // 1.x main.cpp: settings.json is loaded before the stores so the library
    // scan parameters (behavior section) reach LibraryStore.setScanOptions.
    settings.load();

    // M5 compat: scan the user's mpv config dir and assemble the startup
    // options for the recorded decision. Failure degrades to an empty
    // preset (pure EmoPlay defaults + redirects) instead of blocking
    // startup, the way 1.x logged errorOccurred and continued.
    final compat = CompatController(
      settingsPath: settings.filePath,
      appDataDir: dir.path,
      configDir: MpvProfileScanner.locateDefaultConfigDir(),
      onError: (message) => EmoLogger().e('compat: $message'),
    );
    var startupMpvProperties = const <String, String>{};
    try {
      final compatOptions = compat.startupOptions();
      // Plugin script options would be APPENDED here (1.x
      // PluginManager.appendScriptOptions); the plugin store lands in M6
      // and keeps this exact insertion point.
      startupMpvProperties = MpvPlayerProperties.build(
        compatOptions: compatOptions,
        appDataDir: dir.path,
        pluginScripts: const [],
      );
    } catch (e) {
      EmoLogger().e('compat: startup options failed', error: e);
    }

    final library = LibraryStore('${dir.path}/library.json');
    library.setScanOptions(ScanOptions(
      maxDepth: settings.libraryMaxDepth,
      skipHidden: settings.librarySkipHidden,
    ));

    // P6 v2 thumbnails: on-demand ffmpeg-generated JPEGs. The availability
    // probe is asynchronous; while ffmpeg is missing the model simply keeps
    // empty thumbnails and the grid degrades to type icons.
    final thumbnails = ThumbnailService('${dir.path}/thumbnails');
    unawaited(thumbnails.probe());

    final history = HistoryStore(null, '${dir.path}/history.json');

    // M6 画质层：三个画质控制器 + 1.x main.cpp L255-268 的着色器目录规则
    // （导入决策 full/selective 时用用户 mpv 目录的 shaders/，否则用应用
    // 数据目录自己的 shaders/）+ 应用数据 vs/ 目录（插帧 .vpy 预设，不随
    // 应用分发）。引擎挂接在首个播放器创建时发生（quality_stores.dart）。
    final quality = QualityStores(
      settings: settings,
      appDataDir: dir.path,
      shadersDir: QualityStores.resolveShadersDir(
        importDecision: settings.importDecision,
        sourceDir: compat.sourceDir,
        appDataDir: dir.path,
      ),
      scriptsDir: '${dir.path}/vs',
    );

    _instance = MediaStores._(
      settings: settings,
      library: library,
      history: history,
      thumbnails: thumbnails,
      compat: compat,
      quality: quality,
      startupMpvProperties: startupMpvProperties,
    );
  }
}
