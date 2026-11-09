import 'dart:io';

/// Kind of a classified path/URL. The integer values are part of the
/// classification contract (1.x tests assert them), so the enum is pinned to
/// mpv-emo `MediaClassifier::Kind` (src/media/MediaClassifier.h:20-29).
enum MediaKind {
  video(0),
  audio(1),
  subtitle(2),
  folder(3),
  remoteUrl(4),
  missing(5),
  unreadable(6),
  unknown(7);

  final int value;

  const MediaKind(this.value);

  static MediaKind fromValue(int value) => MediaKind.values
      .firstWhere((kind) => kind.value == value, orElse: () => unknown);

  /// Name of a Kind value, for UI text and tests (1.x `kindName`).
  String get kindName => switch (this) {
        MediaKind.video => 'video',
        MediaKind.audio => 'audio',
        MediaKind.subtitle => 'subtitle',
        MediaKind.folder => 'folder',
        MediaKind.remoteUrl => 'url',
        MediaKind.missing => 'missing',
        MediaKind.unreadable => 'unreadable',
        MediaKind.unknown => 'unknown',
      };
}

/// One classified path/URL — the 1.x classify() QVariantMap with the same
/// fields: path, name, kind (int), kindName (string) and reason (empty when
/// the item is usable).
class MediaClassification {
  const MediaClassification({
    required this.path,
    required this.name,
    required this.kind,
    required this.reason,
  });

  /// Normalised path (file:// URLs resolved to local paths).
  final String path;

  /// File name (or the original text when the path is empty).
  final String name;

  final MediaKind kind;

  /// Empty when the item is usable, human readable otherwise.
  final String reason;

  Map<String, Object?> toMap() => {
        'path': path,
        'name': name,
        'kind': kind.value,
        'kindName': kind.kindName,
        'reason': reason,
      };
}

/// One plan the UI executes verbatim (1.x planDrop QVariantMap).
///
/// action: "play"        paths play in order (first loads, rest append)
///         "subtitle"    subtitles load into the current media
///         "folder"      UI must ask: play folder / add to library
///         "needs-media" subtitles arrived with nothing playing
///         "reject"      nothing usable
class DropPlan {
  const DropPlan({
    required this.action,
    required this.paths,
    required this.subtitles,
    required this.folders,
    required this.rejected,
  });

  final String action;
  final List<String> paths;
  final List<String> subtitles;
  final List<String> folders;
  final List<MediaClassification> rejected;
}

/// Classifies paths/URLs and turns a drop into an explicit playback plan.
///
/// 1.x book §4 requires every dropped item to be validated (scheme,
/// existence, permission, type) and every rejected item to carry a stated
/// reason, and §6 forbids business logic in the view layer. Both the drop
/// overlay and the file picker use the same tables, so a file the picker
/// shows as audio is the same file the drop path classifies as audio.
class MediaClassifier {
  const MediaClassifier._();

  /// 1.x `videoExtensions()` — order kept verbatim.
  static const List<String> videoExtensions = [
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv',
    'wmv', 'm4v', 'mpg', 'mpeg', 'ts', 'm2ts',
    '3gp', 'ogv', 'mts',
  ];

  /// 1.x `audioExtensions()` — order kept verbatim.
  static const List<String> audioExtensions = [
    'mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg',
    'opus', 'wma', 'oga',
  ];

  /// 1.x `subtitleExtensions()` — order kept verbatim.
  static const List<String> subtitleExtensions = [
    'srt', 'ass', 'ssa', 'vtt', 'sub',
  ];

  /// Turns file:// URLs into local paths and leaves everything else alone
  /// (1.x `normalise()`, QUrl::isLocalFile/toLocalFile semantics).
  static String normalise(String urlOrPath) {
    final uri = Uri.tryParse(urlOrPath);
    if (uri != null && uri.isScheme('file')) {
      try {
        return uri.toFilePath();
      } on FormatException {
        return urlOrPath;
      }
    }
    return urlOrPath;
  }

  /// 1.x `isRemote()`: a valid URL with one of the stream schemes.
  static bool isRemote(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.isEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'rtsp' ||
        scheme == 'rtmp' ||
        scheme == 'udp' ||
        scheme == 'ftp';
  }

  /// QFileInfo::suffix() semantics: everything after the last '.', lowercased,
  /// except a dot that starts the file name (".bashrc" has no suffix).
  static String extensionOf(String path) {
    final base = fileNameOf(path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0) {
      return '';
    }
    return base.substring(dot + 1).toLowerCase();
  }

  /// QFileInfo::fileName() semantics: the part after the last separator
  /// ('/' everywhere, '\' also honoured for Windows paths).
  static String fileNameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final cut = slash > backslash ? slash : backslash;
    return cut < 0 ? path : path.substring(cut + 1);
  }

  /// QFileInfo::isReadable() approximation: any read permission bit set
  /// (owner 0o400 / group 0o040 / other 0o004 — dart:io exposes no octal
  /// literals or modeRead constant here, hence the hex values).
  /// Covers the 1.x contract (own files are readable; permission-stripped
  /// files are reported unreadable); root and ACL corner cases differ.
  static bool isReadable(String path) {
    try {
      final stat = FileStat.statSync(path);
      if (stat.type == FileSystemEntityType.notFound) {
        return false;
      }
      const anyRead = 0x100 | 0x20 | 0x4;
      return stat.mode & anyRead != 0;
    } catch (_) {
      return false;
    }
  }

  static MediaClassification classify(String urlOrPath) {
    final path = normalise(urlOrPath);
    final name = path.isEmpty ? urlOrPath : fileNameOf(path);

    if (path.isEmpty) {
      return MediaClassification(
        path: path,
        name: name,
        kind: MediaKind.unknown,
        reason: 'Empty path',
      );
    }

    final ext = extensionOf(path);
    if (isRemote(urlOrPath)) {
      final media = videoExtensions.contains(ext) ||
          audioExtensions.contains(ext) ||
          subtitleExtensions.contains(ext);
      return MediaClassification(
        path: path,
        name: name,
        kind: media ? MediaKind.remoteUrl : MediaKind.unknown,
        reason: media
            ? ''
            : 'Unsupported URL type (.${ext.isEmpty ? '?' : ext})',
      );
    }

    FileSystemEntityType type;
    try {
      type = FileStat.statSync(path).type;
    } catch (_) {
      type = FileSystemEntityType.notFound;
    }
    if (type == FileSystemEntityType.notFound) {
      return MediaClassification(
        path: path,
        name: name,
        kind: MediaKind.missing,
        reason: 'File not found',
      );
    }
    if (type == FileSystemEntityType.directory) {
      return MediaClassification(
        path: path,
        name: name,
        kind: MediaKind.folder,
        reason: isReadable(path) ? '' : 'Folder is not readable',
      );
    }
    if (!isReadable(path)) {
      return MediaClassification(
        path: path,
        name: name,
        kind: MediaKind.unreadable,
        reason: 'File is not readable',
      );
    }

    MediaKind kind = MediaKind.unknown;
    if (videoExtensions.contains(ext)) {
      kind = MediaKind.video;
    } else if (audioExtensions.contains(ext)) {
      kind = MediaKind.audio;
    } else if (subtitleExtensions.contains(ext)) {
      kind = MediaKind.subtitle;
    }
    return MediaClassification(
      path: path,
      name: name,
      kind: kind,
      reason: kind == MediaKind.unknown ? 'Unsupported file type (.$ext)' : '',
    );
  }

  static List<MediaClassification> classifyAll(List<String> urls) =>
      [for (final url in urls) classify(url)];

  /// Turns a drop into one plan the UI executes verbatim (1.x planDrop).
  static DropPlan planDrop(List<String> urls, bool hasMedia) {
    final playable = <String>[];
    final subtitles = <String>[];
    final folders = <String>[];
    final rejected = <MediaClassification>[];

    for (final entry in classifyAll(urls)) {
      switch (entry.kind) {
        case MediaKind.video:
        case MediaKind.audio:
        case MediaKind.remoteUrl:
          playable.add(entry.path);
          break;
        case MediaKind.subtitle:
          subtitles.add(entry.path);
          break;
        case MediaKind.folder:
          if (entry.reason.isEmpty) {
            folders.add(entry.path);
          } else {
            rejected.add(entry);
          }
          break;
        default:
          rejected.add(entry);
          break;
      }
    }

    String action = 'reject';
    if (playable.isNotEmpty) {
      action = 'play';
    } else if (subtitles.isNotEmpty) {
      action = hasMedia ? 'subtitle' : 'needs-media';
    } else if (folders.isNotEmpty) {
      action = 'folder';
    }

    return DropPlan(
      action: action,
      paths: playable,
      subtitles: subtitles,
      folders: folders,
      rejected: rejected,
    );
  }

  /// Recursively collects supported media files below [dir] (bounded depth,
  /// hidden entries skipped) for "play this folder". Empty when the folder
  /// holds nothing playable, so the UI can say so instead of doing nothing.
  ///
  /// [maxDepth] is the number of subdirectory levels below the root:
  /// 0 = root only, 1 = root + one level of subdirectories, and so on.
  static List<String> folderMedia(String dir, {int maxDepth = 4}) {
    final files = <String>[];
    final path = normalise(dir);
    if (path.isEmpty) {
      return files;
    }

    final root = Directory(path);
    if (!root.existsSync()) {
      return files;
    }

    final depth = maxDepth < 0 ? 0 : maxDepth;
    // Walk level by level: Directory.list(recursive: true) cannot bound its
    // recursion depth, and an unbounded walk over a network mount is exactly
    // what we must avoid (1.x walked manually for the same reason —
    // QDirIterator cannot bound its recursion depth either).
    void walk(String current, int level) {
      List<FileSystemEntity> entries;
      try {
        entries = Directory(current).listSync(followLinks: false);
      } catch (_) {
        // Unreadable directory: nothing collectable at this level.
        return;
      }
      for (final entity in entries) {
        final name = fileNameOf(entity.path);
        // QDir::Files|Dirs without QDir::Hidden skips hidden entries
        // (".*" on Unix); QDir::Readable skips unreadable ones.
        if (name.startsWith('.')) {
          continue;
        }
        final isDir = FileSystemEntity.typeSync(entity.path,
                followLinks: false) ==
            FileSystemEntityType.directory;
        if (!isDir) {
          if (!isReadable(entity.path)) {
            continue;
          }
          if (isSupportedMedia(name) || isSupportedMedia(entity.path)) {
            files.add(entity.path);
          }
        }
      }
      if (level >= depth) {
        return;
      }
      for (final entity in entries) {
        final name = fileNameOf(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
            FileSystemEntityType.directory) {
          if (isReadable(entity.path)) {
            walk(entity.path, level + 1);
          }
        }
      }
    }

    walk(path, 0);
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return files;
  }

  /// True when the path's extension is in the video or audio tables (1.x
  /// `isSupportedMedia` — subtitles deliberately excluded).
  static bool isSupportedMedia(String path) {
    final ext = extensionOf(normalise(path));
    return videoExtensions.contains(ext) || audioExtensions.contains(ext);
  }
}
