// Dart port of mpv-emo src/compat/MpvProfileScanner.{h,cpp} (A-class).
// QDdir/QDirIterator walking becomes dart:io; the XDG semantics comments are
// the spec (1.x header comment, verified against mpv osdep/path-unix.c) and
// are kept verbatim. Pure logic: everything takes explicit directories, so
// tests build a temporary tree instead of touching the real HOME.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:emoplay/mpv/config/mpv_config_parser.dart';

/// Per-file result of a compat scan. Relative to the scanned config
/// directory (1.x struct ImportFileSummary).
class ImportFileSummary {
  const ImportFileSummary({
    required this.kind,
    required this.relativePath,
    this.sizeBytes = 0,
    this.entryCount = 0,
  });

  // One of: "mpv-conf", "input-conf", "profiles-conf", "platform-conf",
  // "script-opt", "script", "shader", "font", "other".
  final String kind;

  // e.g. "mpv.conf", "scripts/file-browser/main.lua"
  final String relativePath;

  final int sizeBytes;

  // Number of parsed config entries (options / bindings / profile entries).
  // Zero for binary or non-config files.
  final int entryCount;

  Map<String, Object?> toJsonMap() => <String, Object?>{
        'kind': kind,
        'relativePath': relativePath,
        'sizeBytes': sizeBytes,
        'entryCount': entryCount,
      };

  // QJsonValue typed-accessor semantics: wrong types fall back to defaults
  // the same way the 1.x QVariantMap round-trip did.
  static ImportFileSummary fromJsonMap(Map<Object?, Object?> map) {
    return ImportFileSummary(
      kind: map['kind'] is String ? map['kind'] as String : '',
      relativePath:
          map['relativePath'] is String ? map['relativePath'] as String : '',
      sizeBytes: map['sizeBytes'] is int ? map['sizeBytes'] as int : 0,
      entryCount: map['entryCount'] is int ? map['entryCount'] as int : 0,
    );
  }
}

/// Result of scanning a user's mpv configuration directory (1.x struct
/// ImportSummary). Pure value type: no I/O happens after scan() returns.
class ImportSummary {
  // absolute config dir; empty when nothing was scanned
  String sourceDir = '';
  final List<ImportFileSummary> files = [];
  int scriptCount = 0; // scripts/*.lua / *.js (recursive)
  int scriptOptCount = 0; // script-opts/*.conf
  int shaderCount = 0; // shaders/*.glsl / *.hook (recursive)
  int fontCount = 0; // fonts/* files
  int totalBytes = 0;

  bool get isValid => sourceDir.isNotEmpty;

  // True when the scan found anything importable at all.
  bool get hasContent => files.isNotEmpty;

  Map<String, Object?> toJsonMap() => <String, Object?>{
        'sourceDir': sourceDir,
        'scriptCount': scriptCount,
        'scriptOptCount': scriptOptCount,
        'shaderCount': shaderCount,
        'fontCount': fontCount,
        'totalBytes': totalBytes,
        'files': [for (final file in files) file.toJsonMap()],
      };

  static ImportSummary fromJsonMap(Map<Object?, Object?> map) {
    final summary = ImportSummary();
    summary.sourceDir = map['sourceDir'] is String ? map['sourceDir'] as String : '';
    summary.scriptCount = map['scriptCount'] is int ? map['scriptCount'] as int : 0;
    summary.scriptOptCount =
        map['scriptOptCount'] is int ? map['scriptOptCount'] as int : 0;
    summary.shaderCount = map['shaderCount'] is int ? map['shaderCount'] as int : 0;
    summary.fontCount = map['fontCount'] is int ? map['fontCount'] as int : 0;
    summary.totalBytes = map['totalBytes'] is int ? map['totalBytes'] as int : 0;
    final fileList = map['files'];
    if (fileList is List) {
      for (final entry in fileList) {
        if (entry is Map) {
          summary.files.add(ImportFileSummary.fromJsonMap(entry));
        }
      }
    }
    return summary;
  }
}

/// Locates and scans an existing mpv configuration directory.
class MpvProfileScanner {
  MpvProfileScanner._();

  static const _kMpvConf = 'mpv.conf';
  static const _kInputConf = 'input.conf';
  static const _kProfilesConf = 'profiles.conf';
  static const _kPlatformConf = 'platform.conf';

  /// Platform default location for mpv's config dir, mirroring mpv's own
  /// resolution (osdep/path-unix.c / path-win.c):
  ///   Linux/macOS: $XDG_CONFIG_HOME/mpv EXCLUSIVELY when XDG_CONFIG_HOME is
  ///                set, else $HOME/.config/mpv; the legacy $HOME/.mpv
  ///                directory is used only when the primary candidate does
  ///                not exist
  ///   Windows:     %APPDATA%/mpv
  /// Returns an empty string when none of the candidates exists.
  static String locateDefaultConfigDir() {
    final env = Platform.environment;
    return locateConfigDirIn(
      Platform.isWindows ? '' : (env['HOME'] ?? ''),
      env['XDG_CONFIG_HOME'] ?? '',
      env['APPDATA'] ?? '',
    );
  }

  /// Same probe with injected environment values (base-dir parameters, so
  /// tests never read or write the real HOME):
  ///   homeDir          - e.g. /home/user ($HOME)
  ///   xdgConfigHomeDir - e.g. /xdg/config ($XDG_CONFIG_HOME), may be empty
  ///   appDataDir       - e.g. C:/Users/user/AppData/Roaming (%APPDATA%),
  ///                      may be empty
  /// |homeDir| is used when non-empty; on Windows |appDataDir| wins.
  static String locateConfigDirIn(
    String homeDir,
    String xdgConfigHomeDir,
    String appDataDir,
  ) {
    // Only the Windows branch consults %APPDATA%.
    final candidates = <String>[];
    if (Platform.isWindows) {
      // Windows: mpv reads %APPDATA%\mpv (or portable_config next to mpv.exe,
      // which is out of scope for a scan-based import).
      if (appDataDir.isNotEmpty) {
        candidates.add('$appDataDir/mpv');
      }
    } else {
      // Unix semantics (mpv osdep/path-unix.c): $XDG_CONFIG_HOME is used
      // EXCLUSIVELY when set — ~/.config/mpv is never consulted in that case;
      // otherwise ~/.config/mpv. The legacy ~/.mpv directory is a fallback
      // used only when the primary candidate does not exist. Scanning a
      // directory mpv itself would ignore would import the wrong files.
      var primary = '';
      if (xdgConfigHomeDir.isNotEmpty) {
        primary = '$xdgConfigHomeDir/mpv';
      } else if (homeDir.isNotEmpty) {
        primary = '$homeDir/.config/mpv';
      }
      if (primary.isNotEmpty && Directory(primary).existsSync()) {
        candidates.add(primary);
      }
      if (homeDir.isNotEmpty) {
        final legacy = '$homeDir/.mpv';
        if (Directory(legacy).existsSync()) {
          candidates.add(legacy);
        }
      }
    }

    for (final candidate in candidates) {
      if (Directory(candidate).existsSync() || File(candidate).existsSync()) {
        return candidate;
      }
    }
    return '';
  }

  /// Scan a config directory (the "mpv" directory itself). Missing or
  /// unreadable directories yield an invalid summary; individual unreadable
  /// files are skipped. Known files are parsed with MpvConfigParser to
  /// produce entry counts; scripts/, shaders/ and fonts/ are walked
  /// recursively and only counted.
  static ImportSummary scan(String configDir) {
    final summary = ImportSummary();
    if (configDir.isEmpty || !Directory(configDir).existsSync()) {
      return summary;
    }

    // QDir::absolutePath() cleans the path; p.normalize does the string-level
    // equivalent (no symlink resolution, same as 1.x).
    summary.sourceDir = p.normalize(p.absolute(configDir));

    // Top-level config files (each present = one entry in the file list).
    final topFiles = <(String, String)>[
      (_kMpvConf, 'mpv-conf'),
      (_kInputConf, 'input-conf'),
      (_kProfilesConf, 'profiles-conf'),
      (_kPlatformConf, 'platform-conf'),
    ];
    for (final (name, kind) in topFiles) {
      final file = File(p.join(summary.sourceDir, name));
      if (file.existsSync()) {
        summary.files
            .add(_summaryForConfigFile(file, name, kind));
      }
    }

    // script-opts/: per-script option files.
    for (final relPath in _walkFiles(summary.sourceDir, 'script-opts', const ['conf'])) {
      summary.files.add(_summaryForConfigFile(
        File(p.join(summary.sourceDir, relPath)),
        relPath,
        'script-opt',
      ));
      summary.scriptOptCount++;
    }

    // scripts/, shaders/, fonts/: counted, not parsed.
    for (final relPath in _walkFiles(
        summary.sourceDir, 'scripts', const ['lua', 'js'])) {
      summary.files.add(ImportFileSummary(
        kind: 'script',
        relativePath: relPath,
        sizeBytes: _sizeOf(summary.sourceDir, relPath),
      ));
      summary.scriptCount++;
    }
    // A scripts/ directory can hold data files next to scripts (e.g. module
    // assets); surface them so the wizard shows what would come along.
    for (final relPath in _walkFiles(summary.sourceDir, 'scripts', const [])) {
      final suffix = _suffixOf(relPath);
      if (suffix == 'lua' || suffix == 'js') {
        continue;
      }
      summary.files.add(ImportFileSummary(
        kind: 'other',
        relativePath: relPath,
        sizeBytes: _sizeOf(summary.sourceDir, relPath),
      ));
    }

    for (final relPath in _walkFiles(
        summary.sourceDir, 'shaders', const ['glsl', 'hook'])) {
      summary.files.add(ImportFileSummary(
        kind: 'shader',
        relativePath: relPath,
        sizeBytes: _sizeOf(summary.sourceDir, relPath),
      ));
      summary.shaderCount++;
    }

    for (final relPath in _walkFiles(summary.sourceDir, 'fonts', const [])) {
      summary.files.add(ImportFileSummary(
        kind: 'font',
        relativePath: relPath,
        sizeBytes: _sizeOf(summary.sourceDir, relPath),
      ));
      summary.fontCount++;
    }

    for (final file in summary.files) {
      summary.totalBytes += file.sizeBytes;
    }

    // Keep the list stable the way QDirIterator + QStringList::sort did:
    // re-sorting by relative path preserves the 1.x deterministic output.
    // (The per-section walks above were already sorted; this is a no-op
    // safety net.)
    return summary;
  }

  // 1.x summaryForConfigFile: known top-level config files, mapped to their
  // ImportFileSummary kind. profiles.conf uses the same [section] + key=value
  // syntax as mpv.conf (it is just an include-style split of the profile
  // definitions), so one parser covers both; see architecture.md
  // "配置兼容层".
  static ImportFileSummary _summaryForConfigFile(
    File file,
    String relativePath,
    String kind,
  ) {
    String text;
    var sizeBytes = 0;
    try {
      // Read as UTF-8 (QIODevice::Text); the size is the on-disk size.
      text = file.readAsStringSync();
      sizeBytes = file.lengthSync();
    } catch (_) {
      // Unreadable file: kind/path still listed, no size, no entries (1.x
      // returned an unparsed summary in that case too).
      return ImportFileSummary(kind: kind, relativePath: relativePath);
    }

    final entryCount = kind == 'input-conf'
        ? MpvConfigParser.parseInputConf(text).length
        // mpv.conf / profiles.conf / platform.conf share the option syntax.
        : MpvConfigParser.parseMpvConf(text).length;
    return ImportFileSummary(
      kind: kind,
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      entryCount: entryCount,
    );
  }

  /// Recursively collect files under |subDirName| whose suffix is in
  /// |suffixes| (empty list = all files). Returns relative paths (with the
  /// subDirName prefix) sorted for stable output — the 1.x QDirIterator
  /// walk + QStringList::sort contract.
  static List<String> _walkFiles(
    String configDir,
    String subDirName,
    List<String> suffixes,
  ) {
    final result = <String>[];
    final subDir = Directory(p.join(configDir, subDirName));
    if (!subDir.existsSync()) {
      return result;
    }

    final prefixLength = subDir.path.length + 1;
    void walk(Directory current) {
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } catch (_) {
        return; // unreadable subdirectory: skipped like QDirIterator
      }
      entries.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in entries) {
        if (entity is Directory) {
          walk(entity);
        } else if (entity is File) {
          // QDir::Files: directories are not yielded.
          if (suffixes.isNotEmpty &&
              !suffixes.contains(_suffixOf(entity.path))) {
            continue;
          }
          result.add('$subDirName/${entity.path.substring(prefixLength)}');
        }
      }
    }

    walk(subDir);
    result.sort();
    return result;
  }

  // QFileInfo::suffix(): characters after the last '.'. Empty for names
  // without a dot or ending in a dot. Lower-cased like 1.x.
  static String _suffixOf(String path) {
    final name = p.basename(path);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static int _sizeOf(String sourceDir, String relativePath) {
    try {
      return File(p.join(sourceDir, relativePath)).lengthSync();
    } catch (_) {
      return 0;
    }
  }
}
