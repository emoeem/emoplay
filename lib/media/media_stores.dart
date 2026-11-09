import 'dart:async';

import 'package:path_provider/path_provider.dart';

import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';
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

    _instance = MediaStores._(
      settings: settings,
      library: library,
      history: history,
      thumbnails: thumbnails,
    );
  }
}
