import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Persisted application settings (settings.json in the application support
// directory).
//
// Field-for-field the 1.x schema (docs/SPEC.md §7). Currently carries:
//  - the P4 mpv-config import decision:
//   - importDecision: "" (unset, first run), "full", "selective",
//     "standalone" or "skip"
//   - selectedFiles:  relative paths chosen for "selective"
//   - dontAskAgain:   user chose "skip and don't ask again"
//   - lastImportSummary: the ImportSummary of the imported configuration
//   - importedAt:     ISO-8601 timestamp of the decision
//  - the P5 quality preferences in a nested "quality" section:
//   - contentMode ("auto"/"anime"/"live", default "auto")
//   - qualityTier (1.x domain "off"/"low"/"medium"/"high", default "off";
//     §7 lists the 2.0 domain "low|medium|high" — the store itself is
//     domain-agnostic and keeps the 1.x default so old files load unchanged)
//   - toneMappingMode ("auto" or an explicit mpv tone-mapping value,
//     default "auto")
//   - scaleOverride ("" = engine picks, or an explicit --scale value; §7
//     shows the not-set case as JSON null, 1.x wrote "" — both load as "")
//   - debandMode (1.x domain "auto"/"yes"/"no" user override, default
//     "auto"; §7 lists the 2.0 domain "off|low|medium|high")
//   - manualShaderList (absolute shader paths checked in the quality panel)
//  - the P5 v2 objects in the same quality section:
//   - interpolation (frame interpolation):
//     - enabled (bool, default false)
//     - preset (vs/ preset id; 1.x default "MEMC_RIFE_STD", §7 lists the
//       2.0 presets "MEMC_01|...|MEMC_06")
//   - icc (display configuration):
//     - enabled (bool, default false)
//     - profilePath (absolute ICC file path, default "")
//  - the app-level behavior preferences in a nested "behavior" section:
//   - resumeOnReopen (click a recent entry -> continue at the stored
//     position instead of starting over, default true)
//   - libraryMaxDepth (folder levels below a media root that the library
//     scan descends into, 0 = unlimited, default 2)
//   - librarySkipHidden (skip hidden files and directories, default true)
//  - the P7 music preferences in a nested "music" section:
//   - equalizerEnabled (10-band EQ wired to mpv's af chain, default false)
//   - equalizerPreset ("flat"/"bass"/"vocal"/"live"/"custom", default "flat")
//   - equalizerGains (per-band gains in dB, up to 10 doubles, default all 0)
//
// Storage is a single JSON document written atomically (temp file + rename,
// the QSaveFile pattern), mirroring HistoryStore/LibraryStore. The file path
// is injectable so tests use a temporary dir. Wrong-typed values in
// hand-edited files fall back to the defaults the way QJsonValue's typed
// accessors do (toString(default)/toBool(default)/toInt(default)).
class EmoPlaySettings extends ChangeNotifier {
  EmoPlaySettings(this.filePath);

  // Default storage location; the application support directory needs
  // path_provider's platform channel, so this is async.
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/settings.json';
  }

  // JSON keys (1.x AppSettings.cpp key table, verbatim).
  static const String _kImportDecision = 'importDecision';
  static const String _kDontAskAgain = 'dontAskAgain';
  static const String _kSelectedFiles = 'selectedFiles';
  static const String _kLastImportSummary = 'lastImportSummary';
  static const String _kImportedAt = 'importedAt';
  static const String _kQuality = 'quality';
  static const String _kQualityContentMode = 'contentMode';
  static const String _kQualityTier = 'qualityTier';
  static const String _kQualityToneMapping = 'toneMappingMode';
  static const String _kQualityScaleOverride = 'scaleOverride';
  static const String _kQualityDebandMode = 'debandMode';
  static const String _kQualityManualShaders = 'manualShaderList';
  static const String _kQualityInterpolation = 'interpolation';
  static const String _kInterpolationEnabled = 'enabled';
  static const String _kInterpolationPreset = 'preset';
  static const String _kQualityIcc = 'icc';
  static const String _kIccEnabled = 'enabled';
  static const String _kIccProfilePath = 'profilePath';
  static const String _kBehavior = 'behavior';
  static const String _kResumeOnReopen = 'resumeOnReopen';
  static const String _kLibraryMaxDepth = 'libraryMaxDepth';
  static const String _kLibrarySkipHidden = 'librarySkipHidden';
  static const String _kMusic = 'music';
  static const String _kMusicEqualizerEnabled = 'equalizerEnabled';
  static const String _kMusicEqualizerPreset = 'equalizerPreset';
  static const String _kMusicEqualizerGains = 'equalizerGains';

  // Path of the backing JSON document (shown in the settings UI so the
  // user can find / back it up).
  final String filePath;

  // "" while undecided (first run or wizard dismissed without a choice).
  String get importDecision => _importDecision;
  String _importDecision = '';
  void setImportDecision(String decision) {
    if (_importDecision == decision) {
      return;
    }
    _importDecision = decision;
    // 1.x stamped the decision time in UTC.
    _importedAt = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
  }

  // 1.x had this one as a silent inline setter (no changed() signal, no
  // guard) — a plain public field keeps the same contract.
  bool dontAskAgain = false;

  List<String> get selectedFiles => List.unmodifiable(_selectedFiles);
  final List<String> _selectedFiles = <String>[];
  set selectedFiles(List<String> files) {
    _selectedFiles
      ..clear()
      ..addAll(files);
  }

  Map<String, Object?> get lastImportSummary =>
      Map<String, Object?>.unmodifiable(_lastImportSummary);
  final Map<String, Object?> _lastImportSummary = <String, Object?>{};
  set lastImportSummary(Map<String, Object?> summary) {
    _lastImportSummary
      ..clear()
      ..addAll(summary);
  }

  String get importedAt => _importedAt;
  String _importedAt = '';

  // P5 quality section. All setters notify and persist only when the caller
  // calls save() (same contract as the import decision).
  String get qualityContentMode => _qualityContentMode;
  String _qualityContentMode = 'auto';
  set qualityContentMode(String mode) {
    if (_qualityContentMode == mode) {
      return;
    }
    _qualityContentMode = mode;
    notifyListeners();
  }

  String get qualityTier => _qualityTier;
  String _qualityTier = 'off';
  set qualityTier(String tier) {
    if (_qualityTier == tier) {
      return;
    }
    _qualityTier = tier;
    notifyListeners();
  }

  String get qualityToneMapping => _qualityToneMapping;
  String _qualityToneMapping = 'auto';
  set qualityToneMapping(String mode) {
    if (_qualityToneMapping == mode) {
      return;
    }
    _qualityToneMapping = mode;
    notifyListeners();
  }

  String get qualityScaleOverride => _qualityScaleOverride;
  String _qualityScaleOverride = '';
  set qualityScaleOverride(String scale) {
    if (_qualityScaleOverride == scale) {
      return;
    }
    _qualityScaleOverride = scale;
    notifyListeners();
  }

  String get qualityDebandMode => _qualityDebandMode;
  String _qualityDebandMode = 'auto';
  set qualityDebandMode(String mode) {
    if (_qualityDebandMode == mode) {
      return;
    }
    _qualityDebandMode = mode;
    notifyListeners();
  }

  List<String> get manualShaderList => List.unmodifiable(_manualShaderList);
  final List<String> _manualShaderList = <String>[];
  set manualShaderList(List<String> shaders) {
    if (_listEquals(_manualShaderList, shaders)) {
      return;
    }
    _manualShaderList
      ..clear()
      ..addAll(shaders);
    notifyListeners();
  }

  // P5 v2 interpolation / icc objects (nested in the quality section).
  bool get qualityInterpolationEnabled => _qualityInterpolationEnabled;
  bool _qualityInterpolationEnabled = false;
  set qualityInterpolationEnabled(bool enabled) {
    if (_qualityInterpolationEnabled == enabled) {
      return;
    }
    _qualityInterpolationEnabled = enabled;
    notifyListeners();
  }

  String get qualityInterpolationPreset => _qualityInterpolationPreset;
  String _qualityInterpolationPreset = 'MEMC_RIFE_STD';
  set qualityInterpolationPreset(String preset) {
    if (_qualityInterpolationPreset == preset) {
      return;
    }
    _qualityInterpolationPreset = preset;
    notifyListeners();
  }

  bool get qualityIccEnabled => _qualityIccEnabled;
  bool _qualityIccEnabled = false;
  set qualityIccEnabled(bool enabled) {
    if (_qualityIccEnabled == enabled) {
      return;
    }
    _qualityIccEnabled = enabled;
    notifyListeners();
  }

  String get qualityIccProfilePath => _qualityIccProfilePath;
  String _qualityIccProfilePath = '';
  set qualityIccProfilePath(String path) {
    if (_qualityIccProfilePath == path) {
      return;
    }
    _qualityIccProfilePath = path;
    notifyListeners();
  }

  // App-level behavior section ("behavior"); same contract as above.
  bool get resumeOnReopen => _resumeOnReopen;
  bool _resumeOnReopen = true;
  set resumeOnReopen(bool resume) {
    if (_resumeOnReopen == resume) {
      return;
    }
    _resumeOnReopen = resume;
    notifyListeners();
  }

  int get libraryMaxDepth => _libraryMaxDepth;
  int _libraryMaxDepth = 2;
  set libraryMaxDepth(int depth) {
    final value = depth < 0 ? 0 : depth; // qMax(0, depth)
    if (_libraryMaxDepth == value) {
      return;
    }
    _libraryMaxDepth = value;
    notifyListeners();
  }

  bool get librarySkipHidden => _librarySkipHidden;
  bool _librarySkipHidden = true;
  set librarySkipHidden(bool skip) {
    if (_librarySkipHidden == skip) {
      return;
    }
    _librarySkipHidden = skip;
    notifyListeners();
  }

  // P7 music section. Same contract as the quality section: setters notify
  // and persist only when the caller calls save().
  bool get musicEqualizerEnabled => _musicEqualizerEnabled;
  bool _musicEqualizerEnabled = false;
  set musicEqualizerEnabled(bool enabled) {
    if (_musicEqualizerEnabled == enabled) {
      return;
    }
    _musicEqualizerEnabled = enabled;
    notifyListeners();
  }

  String get musicEqualizerPreset => _musicEqualizerPreset;
  String _musicEqualizerPreset = 'flat';
  set musicEqualizerPreset(String preset) {
    if (_musicEqualizerPreset == preset) {
      return;
    }
    _musicEqualizerPreset = preset;
    notifyListeners();
  }

  List<double> get musicEqualizerGains =>
      List<double>.unmodifiable(_musicEqualizerGains);
  final List<double> _musicEqualizerGains = <double>[];
  set musicEqualizerGains(List<double> gains) {
    if (_listEquals(_musicEqualizerGains, gains)) {
      return;
    }
    _musicEqualizerGains
      ..clear()
      ..addAll(gains);
    notifyListeners();
  }

  // Reads the file. Missing or corrupt files reset to defaults and return
  // false; a valid file returns true. Never throws.
  bool load() {
    _importDecision = '';
    dontAskAgain = false;
    _selectedFiles.clear();
    _lastImportSummary.clear();
    _importedAt = '';
    _qualityContentMode = 'auto';
    _qualityTier = 'off';
    _qualityToneMapping = 'auto';
    _qualityScaleOverride = '';
    _qualityDebandMode = 'auto';
    _manualShaderList.clear();
    _qualityInterpolationEnabled = false;
    _qualityInterpolationPreset = 'MEMC_RIFE_STD';
    _qualityIccEnabled = false;
    _qualityIccProfilePath = '';
    _resumeOnReopen = true;
    _libraryMaxDepth = 2;
    _librarySkipHidden = true;
    _musicEqualizerEnabled = false;
    _musicEqualizerPreset = 'flat';
    _musicEqualizerGains.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return false; // nothing persisted yet
    }

    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return false; // corrupt: stay at defaults, caller may rewrite
    }
    if (document is! Map) {
      return false; // corrupt: stay at defaults, caller may rewrite
    }
    final obj = document;

    _importDecision = _stringOr(obj, _kImportDecision, '');
    dontAskAgain = _boolOr(obj, _kDontAskAgain, false);
    final files = obj[_kSelectedFiles];
    if (files is List) {
      // QJsonValue::toString() semantics: non-string elements become "".
      _selectedFiles
        ..clear()
        ..addAll([for (final value in files) value is String ? value : '']);
    }
    final summary = obj[_kLastImportSummary];
    if (summary is Map) {
      _lastImportSummary.clear();
      summary.forEach((key, value) {
        _lastImportSummary[key.toString()] = value;
      });
    }
    _importedAt = _stringOr(obj, _kImportedAt, '');

    final quality = _mapOr(obj, _kQuality);
    _qualityContentMode = _stringOr(quality, _kQualityContentMode, _qualityContentMode);
    _qualityTier = _stringOr(quality, _kQualityTier, _qualityTier);
    _qualityToneMapping =
        _stringOr(quality, _kQualityToneMapping, _qualityToneMapping);
    // toString() without a default: wrong types fall back to "".
    _qualityScaleOverride =
        quality[_kQualityScaleOverride] is String
            ? quality[_kQualityScaleOverride] as String
            : '';
    _qualityDebandMode = _stringOr(quality, _kQualityDebandMode, _qualityDebandMode);
    final shaders = quality[_kQualityManualShaders];
    if (shaders is List) {
      _manualShaderList
        ..clear()
        ..addAll([for (final value in shaders) value is String ? value : '']);
    }

    final interpolation = _mapOr(quality, _kQualityInterpolation);
    _qualityInterpolationEnabled =
        _boolOr(interpolation, _kInterpolationEnabled, _qualityInterpolationEnabled);
    _qualityInterpolationPreset =
        _stringOr(interpolation, _kInterpolationPreset, _qualityInterpolationPreset);

    final icc = _mapOr(quality, _kQualityIcc);
    _qualityIccEnabled = _boolOr(icc, _kIccEnabled, _qualityIccEnabled);
    _qualityIccProfilePath =
        icc[_kIccProfilePath] is String ? icc[_kIccProfilePath] as String : '';

    final behavior = _mapOr(obj, _kBehavior);
    _resumeOnReopen = _boolOr(behavior, _kResumeOnReopen, _resumeOnReopen);
    _libraryMaxDepth = _intOr(behavior, _kLibraryMaxDepth, _libraryMaxDepth);
    _librarySkipHidden =
        _boolOr(behavior, _kLibrarySkipHidden, _librarySkipHidden);

    final music = _mapOr(obj, _kMusic);
    _musicEqualizerEnabled =
        _boolOr(music, _kMusicEqualizerEnabled, _musicEqualizerEnabled);
    _musicEqualizerPreset =
        _stringOr(music, _kMusicEqualizerPreset, _musicEqualizerPreset);
    final gains = music[_kMusicEqualizerGains];
    if (gains is List) {
      // QJsonValue::toDouble() semantics: non-numeric elements become 0.0.
      _musicEqualizerGains
        ..clear()
        ..addAll([
          for (final value in gains)
            value is num ? value.toDouble() : 0.0,
        ]);
    }
    return true;
  }

  // Writes the current state atomically. Returns false on I/O failure.
  bool save() {
    final quality = <String, Object?>{
      _kQualityContentMode: _qualityContentMode,
      _kQualityTier: _qualityTier,
      _kQualityToneMapping: _qualityToneMapping,
      _kQualityScaleOverride: _qualityScaleOverride,
      _kQualityDebandMode: _qualityDebandMode,
      _kQualityManualShaders: List<String>.of(_manualShaderList),
      _kQualityInterpolation: <String, Object?>{
        _kInterpolationEnabled: _qualityInterpolationEnabled,
        _kInterpolationPreset: _qualityInterpolationPreset,
      },
      _kQualityIcc: <String, Object?>{
        _kIccEnabled: _qualityIccEnabled,
        _kIccProfilePath: _qualityIccProfilePath,
      },
    };

    final music = <String, Object?>{
      _kMusicEqualizerEnabled: _musicEqualizerEnabled,
      _kMusicEqualizerPreset: _musicEqualizerPreset,
      _kMusicEqualizerGains: List<double>.of(_musicEqualizerGains),
    };

    final behavior = <String, Object?>{
      _kResumeOnReopen: _resumeOnReopen,
      _kLibraryMaxDepth: _libraryMaxDepth,
      _kLibrarySkipHidden: _librarySkipHidden,
    };

    final obj = <String, Object?>{
      _kImportDecision: _importDecision,
      _kDontAskAgain: dontAskAgain,
      _kSelectedFiles: List<String>.of(_selectedFiles),
      _kLastImportSummary: Map<String, Object?>.of(_lastImportSummary),
      _kImportedAt: _importedAt,
      _kBehavior: behavior,
      _kQuality: quality,
      _kMusic: music,
    };

    // Atomic write via temp file + rename: a crash mid-write leaves the
    // previous settings intact, mirroring HistoryStore. Indented output
    // like 1.x (QJsonDocument::Indented), so hand editing stays pleasant.
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final temp = File('${dir.path}/${file.uri.pathSegments.last}.tmp');
      temp.writeAsStringSync(
          const JsonEncoder.withIndent('    ').convert(obj),
          flush: true);
      temp.renameSync(filePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  // element-wise comparison, the QVariantList == QVariantList semantics the
  // guarded setters rely on (no extra dependency: package:collection is not
  // a direct one).
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  // ------------------------------------------------- Qt-tolerant accessors

  // QJsonObject::value(key).toString(default): strings pass through, wrong
  // types fall back to |fallback|.
  static String _stringOr(Map<Object?, Object?> obj, String key,
          String fallback) =>
      obj[key] is String ? obj[key] as String : fallback;

  // QJsonValue::toBool(default): booleans pass through, wrong types fall
  // back to |fallback|.
  static bool _boolOr(Map<Object?, Object?> obj, String key, bool fallback) =>
      obj[key] is bool ? obj[key] as bool : fallback;

  // QJsonValue::toInt(default): integral values pass through, everything
  // else falls back.
  static int _intOr(Map<Object?, Object?> obj, String key, int fallback) {
    final value = obj[key];
    if (value is int) {
      return value;
    }
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return fallback;
  }

  // QJsonObject::value(key).toObject(): objects pass through, wrong types
  // become empty.
  static Map<Object?, Object?> _mapOr(Map<Object?, Object?> obj, String key) {
    final value = obj[key];
    return value is Map ? value : const {};
  }
}
