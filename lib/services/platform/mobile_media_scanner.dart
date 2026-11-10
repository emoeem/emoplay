import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/utils/device.dart';

/// One storage folder worth indexing, found by the phone media discovery.
class DiscoveredMediaDirectory {
  const DiscoveredMediaDirectory({
    required this.path,
    required this.mediaCount,
    required this.standard,
  });

  final String path;

  /// Supported media files found within the discovery depth.
  final int mediaCount;

  /// True for the well-known media folders (Movies, DCIM, Music, ...), which
  /// sort first so the user's own folder names can never bury them.
  final bool standard;
}

/// Phone storage discovery for the media library (the missing counterpart of
/// the desktop file-picker flow): walks the storage volumes for folders that
/// hold playable media, so the library fills itself instead of waiting for a
/// folder picker that phones make awkward.
///
/// Access goes through the existing download-directory channel: Android's
/// MANAGE_EXTERNAL_STORAGE is already declared in the manifest and
/// `requestStorageAccess` opens the system "All files access" page, awaited
/// until the user returns.
class MobileMediaScanner {
  const MobileMediaScanner._();

  static const _channel =
      MethodChannel('com.emoplay.emoplay/download_directory');

  /// Standard media folders per storage root, probed first (1.x media-player
  /// convention; matches what cameras/browsers/mail apps write to).
  static const _standardFolders = [
    'Movies',
    'DCIM',
    'Pictures',
    'Download',
    'Music',
    'Recordings',
    'Podcasts',
    'Video',
    'Audio',
    'Bluetooth',
  ];

  /// First-level folders that never contain user media but can be enormous
  /// (app data, caches) — excluded from the per-root sweep.
  static const _sweptFolderBlacklist = [
    'Android',
    'DCIM' /* probed as standard */,
    'data',
    'obb',
    'lost+found',
  ];

  static bool get isSupported =>
      !isDesktop() && (Platform.isAndroid || Platform.isIOS);

  /// True when bulk file access is already granted (Android 11+ all-files
  /// access; legacy read permission below). Check only — opens nothing.
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      final granted = await _channel.invokeMethod<bool>('hasStorageAccess');
      return granted ?? false;
    } on PlatformException catch (e) {
      EmoLogger().w('MobileMediaScanner: access check failed', error: e);
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Requests bulk storage access, opening the system settings page when
  /// needed. Resolves once the user returns (the native side replays the
  /// result through onActivityResult, which often reports RESULT_CANCELED
  /// even after a grant — the native handler re-checks the grant).
  static Future<bool> requestStorageAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      final granted = await _channel.invokeMethod<bool>('requestStorageAccess');
      return granted ?? false;
    } on PlatformException catch (e) {
      // The common case: the access dialog is already open or the channel is
      // busy — report not-granted so the UI can tell the user to retry.
      EmoLogger().w('MobileMediaScanner: access request failed', error: e);
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Finds folders that contain supported media. Runs the directory walks in
  /// a background isolate; a storage root that cannot be listed is skipped
  /// (removed SD cards, restricted volumes).
  static Future<List<DiscoveredMediaDirectory>> discoverMediaDirectories({
    int maxDepth = 2,
  }) async {
    if (!isSupported) {
      return const [];
    }
    final roots = await _storageRoots();
    if (roots.isEmpty) {
      return const [];
    }
    return Isolate.run(() => _discoverSync(roots, maxDepth));
  }

  /// Storage volume roots visible to plain file IO. `/storage` lists every
  /// mounted volume on Android (primary lives under `emulated/0`).
  static Future<List<String>> _storageRoots() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    final roots = <String>[];
    const primary = '/storage/emulated/0';
    if (Directory(primary).existsSync()) {
      roots.add(primary);
    }
    try {
      for (final entry in Directory('/storage').listSync(followLinks: false)) {
        final name = MediaClassifier.fileNameOf(entry.path);
        if (name == 'emulated' || name == 'self' || name.startsWith('.')) {
          continue;
        }
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) ==
            FileSystemEntityType.directory) {
          roots.add(entry.path);
        }
      }
    } catch (_) {
      // /storage not listable (rare): the primary root still covers most
      // phones.
    }
    return roots;
  }

  /// The synchronous walk that runs inside the isolate.
  static List<DiscoveredMediaDirectory> _discoverSync(
    List<String> roots,
    int maxDepth,
  ) {
    final found = <String, DiscoveredMediaDirectory>{};

    void consider(String directory, bool standard) {
      final normalized = directory.endsWith('/')
          ? directory.substring(0, directory.length - 1)
          : directory;
      if (found.containsKey(normalized)) {
        return;
      }
      final count = _countMedia(normalized, maxDepth);
      if (count > 0) {
        found[normalized] = DiscoveredMediaDirectory(
          path: normalized,
          mediaCount: count,
          standard: standard,
        );
      }
    }

    for (final root in roots) {
      // Standard folders: even when absent, missing them is how a library
      // stays half-empty, so probe each by name.
      for (final folder in _standardFolders) {
        final directory = '$root/$folder';
        if (FileSystemEntity.typeSync(directory) ==
            FileSystemEntityType.directory) {
          consider(directory, true);
        }
      }
      // Everything else on the first level: users keep collections in
      // self-named folders the standard list cannot know about.
      List<FileSystemEntity> entries;
      try {
        entries = Directory(root).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entry in entries) {
        final name = MediaClassifier.fileNameOf(entry.path);
        if (name.startsWith('.') || _sweptFolderBlacklist.contains(name)) {
          continue;
        }
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) ==
            FileSystemEntityType.directory) {
          consider(entry.path, false);
        }
      }
    }

    final list = found.values.toList()
      ..sort((a, b) {
        if (a.standard != b.standard) {
          return a.standard ? -1 : 1;
        }
        final byCount = b.mediaCount.compareTo(a.mediaCount);
        if (byCount != 0) {
          return byCount;
        }
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
    return list;
  }

  /// Supported media files under [directory] within [maxDepth] levels.
  /// `MediaClassifier.folderMedia` returns full paths — only the count is
  /// needed here, and the walk must stay cheap: this runs per candidate
  /// folder on every discovery.
  static int _countMedia(String directory, int maxDepth) {
    return MediaClassifier.folderMedia(directory, maxDepth: maxDepth).length;
  }
}
