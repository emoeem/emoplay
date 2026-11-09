// Dart port of mpv-emo src/compat/CompatController.{h,cpp} (B-class:
// QObject signals -> ChangeNotifier, QVariantMap -> Map<String, String>).
// Semantics preserved one-for-one; the 1.x consent-invariant comments are
// the spec and are kept.
//
// Glue between the mpv compat layer and the app: persists the import
// decision, scans the user's mpv directory, and assembles the option map
// that the player applies at startup.
//
// Startup order (1.x main.cpp, now MediaStores.init + the player bootstrap):
//   1. read settings.json (import decision)
//   2. scan the user's mpv config dir
//   3. build options for the recorded decision (full/selective/standalone)
//   4. player bootstrap applies the assembled map (media_kit properties)
//   5. first run with a detected config: the wizard asks; the choice
//      persists and the imported options take effect on the NEXT launch.
//
// User principles enforced here and in MpvImportRules:
//   - EmoPlay never writes into the user's mpv directory (config-dir points
//     there only for reading; all write paths are redirected to app data).
//   - Any decision is user-initiated; nothing is imported without consent.
//     1.x考证 (mpv v0.37, player/main.c mp_input_load_config): mpv loads
//     input.conf in mpv_initialize regardless of --config, and auto-loads
//     every script in the config dir's scripts/ subdirectory (load-scripts
//     defaults to yes even under libmpv). The shipped 2.0 libmpv
//     (v0.41.0-11-gf011d73d5-dirty, probed 2026-11-10) gates BOTH behind the
//     libmpv `config` option (default no): with no input-conf option set,
//     neither the default config dir's input.conf nor MPV_HOME's is loaded,
//     and scripts/ is never auto-executed (this build also ships no lua/js
//     scripting backend). The pinning below stays regardless — it keeps the
//     1.x guarantee for builds where that gate moves (client.h still lists
//     input-conf/load-scripts as init-time-only options), and it is what the
//     settings audit table reports.
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/mpv/compat/mpv_profile_scanner.dart';
import 'package:emoplay/mpv/config/mpv_config_parser.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

class CompatController extends ChangeNotifier {
  /// Injectable paths for tests (1.x second constructor): settings file,
  /// app data dir (receives redirected write paths) and the mpv config dir
  /// to scan.
  CompatController({
    required String settingsPath,
    required this.appDataDir,
    required this.configDir,
    void Function(String message)? onError,
  })  : settings = EmoPlaySettings(settingsPath),
        _onError = onError;

  final EmoPlaySettings settings;
  final String appDataDir;
  final String configDir;
  final void Function(String message)? _onError;

  ImportSummary _summary = ImportSummary();
  bool _wizardRequested = false;
  int _appliedOptionCount = 0;

  // True when a user mpv config directory with importable content exists.
  bool get configDetected => _summary.hasContent;

  // First run (no decision recorded), config found, not told to be quiet.
  bool get firstRunPromptNeeded =>
      configDetected && settings.importDecision.isEmpty && !settings.dontAskAgain;

  // Set by requestWizard() until the wizard reports a choice.
  bool get wizardRequested => _wizardRequested;

  String get sourceDir => _summary.sourceDir;

  // File entries for the selective-import checklist: kind, relativePath,
  // sizeBytes, entryCount (1.x QVariantList contract, same keys).
  List<Map<String, Object?>> get importFiles => [
        for (final file in _summary.files)
          <String, Object?>{
            'kind': file.kind,
            'relativePath': file.relativePath,
            'sizeBytes': file.sizeBytes,
            'entryCount': file.entryCount,
          },
      ];

  // Number of engine options the recorded import decision actually fed into
  // the player at startup (startupOptions()). 0 means nothing was imported,
  // which is what "skip"/"standalone" must report instead of pretending.
  int get appliedOptionCount => _appliedOptionCount;

  // Recorded import decision: "full" | "selective" | "standalone" | "skip"
  // | "" (undecided). Exposed so the UI states the truth instead of guessing.
  String get importDecision => settings.importDecision;

  // Discovered resource counts from the last scan (scripts, shaders, fonts).
  int get discoveredScriptCount => _summary.scriptCount;
  int get discoveredShaderCount => _summary.shaderCount;
  int get discoveredFontCount => _summary.fontCount;

  void _reportError(String message) {
    final callback = _onError;
    if (callback != null) {
      callback(message);
    } else {
      debugPrint('compat: $message');
    }
  }

  /// Steps 1-3 above. Safe to call once at startup.
  Map<String, String> startupOptions() {
    settings.load();
    _summary = MpvProfileScanner.scan(configDir);

    final decision = settings.importDecision;
    var options = <String, String>{};
    if (decision == 'full') {
      options = buildImportOptions(_allRelativePaths());
    } else if (decision == 'selective') {
      options = buildImportOptions(settings.selectedFiles);
    } else if (decision == 'standalone') {
      options = buildStandaloneOptions();
    }
    // "skip" or undecided: pure EmoPlay defaults — but see below.

    // mpv loads input.conf inside mpv_initialize regardless of --config
    // (1.x: input/input.c mp_input_load_config), falling back to the config
    // dir's input.conf when input-conf is unset or unreadable. Whenever the
    // user did not explicitly import their input.conf, pin it to EmoPlay's
    // own empty file so nothing is loaded without consent.
    final ownInputConf = ensureOwnInputConf();
    if (!options.containsKey('input-conf')) {
      options['input-conf'] = ownInputConf;
    }

    // Report what the decision actually produced. input-conf is always
    // present — usually pointing at EmoPlay's own empty file — so the count
    // excludes it: "how many options of the user's config did mpv really
    // receive". This is what the Home status card shows instead of the vague
    // "imported" claim.
    _appliedOptionCount = options.length;
    if (options['input-conf'] == ownInputConf) {
      _appliedOptionCount--;
    }
    notifyListeners();
    return options;
  }

  Map<String, String> buildImportOptions(List<String> selected) {
    final options = <String, String>{};
    if (!_summary.isValid || selected.isEmpty) {
      return options;
    }

    final sourceDir = _summary.sourceDir;

    // mpv.conf: apply through the import rules (forced/strip/redirect).
    if (selected.contains('mpv.conf')) {
      try {
        final text =
            File('$sourceDir/mpv.conf').readAsStringSync();
        final entries = MpvConfigParser.parseMpvConf(text);
        final rules =
            MpvImportRules.apply(entries, sourceDir, appDataDir);
        options.addAll(rules.options);
      } catch (e) {
        // Unreadable mpv.conf: skipped like the 1.x failed QFile::open.
        _reportError('cannot read $sourceDir/mpv.conf: $e');
      }
    }

    // input.conf: loaded by mpv directly from the user's directory — the
    // file is never copied or written.
    if (selected.contains('input.conf') &&
        File('$sourceDir/input.conf').existsSync()) {
      options['input-conf'] = '$sourceDir/input.conf';
    }

    // scripts: explicit file list (files, never a directory overwrite). The
    // --scripts option is a PATH list: ':' on Unix, ';' on Windows (mpv
    // options.rst "--scripts=file1.lua:file2.lua:..."), NOT the ',' used by
    // ordinary list options — a comma would make the whole string one
    // nonexistent path. Paths containing the separator character are
    // unsupported (documented limitation).
    final scriptPaths = <String>[
      for (final file in _summary.files)
        if (file.kind == 'script' && selected.contains(file.relativePath))
          '$sourceDir/${file.relativePath}',
    ];
    if (scriptPaths.isNotEmpty) {
      options['scripts'] = scriptPaths.join(scriptSeparator);
    }

    // fonts: point mpv's fonts-dir at the user's fonts/ directory.
    if (_summary.fontCount > 0) {
      final anyFontSelected = _summary.files.any((file) =>
          file.kind == 'font' && selected.contains(file.relativePath));
      if (anyFontSelected) {
        options['fonts-dir'] = '$sourceDir/fonts';
      }
    }

    // config-dir makes ~~ paths inside imported option values (shaders,
    // ICC profiles, script-opts lookups from scripts) resolve against the
    // user's original directory — read-only usage. (1.x passed this through
    // mpv_set_option_string pre-init; media_kit has no pre-init hook, so the
    // value travels in the option map for the audit and any future
    // pre-init-capable path. See mpv_player_properties.dart.)
    options['config-dir'] = sourceDir;

    return options;
  }

  Map<String, String> buildStandaloneOptions() {
    // Deterministic EmoPlay-only configuration: no user config-dir, no user
    // scripts; input-conf is pinned by startupOptions().
    return {};
  }

  /// Returns the path of EmoPlay's own empty input.conf, creating it if
  /// needed; reports via [onError] when creation fails (1.x errorOccurred).
  String ensureOwnInputConf() {
    final path = '$appDataDir/input.conf';
    final file = File(path);
    if (!file.existsSync()) {
      // The app support directory is not auto-created on a fresh machine;
      // without this the write below fails and mpv would fall back to the
      // user's own input.conf.
      try {
        Directory(appDataDir).createSync(recursive: true);
        file.writeAsStringSync('');
      } catch (e) {
        // input-conf pointing at a missing file makes mpv fall back to the
        // config dir's input.conf — report this instead of failing silently.
        _reportError(
            "cannot create $path ($e): mpv may fall back to loading the user's input.conf");
      }
    }
    return path;
  }

  void _persistDecision(String decision, List<String> selected) {
    settings.setImportDecision(decision);
    settings.selectedFiles = selected;
    settings.lastImportSummary = _summary.toJsonMap();
    settings.save();
    _wizardRequested = false;
    notifyListeners();
  }

  /// Wizard outcomes. Each persists the decision immediately and clears
  /// wizardRequested. Imported engine options apply on the next launch.
  void chooseFullImport() {
    _persistDecision('full', _allRelativePaths());
  }

  void chooseSelectiveImport(List<String> relativePaths) {
    _persistDecision('selective', relativePaths);
  }

  void chooseStandalone() {
    _persistDecision('standalone', []);
  }

  void skipAndDontAskAgain() {
    settings.dontAskAgain = true;
    _persistDecision('skip', []);
  }

  /// "Re-run import" entry point (settings UI in a later phase).
  void requestWizard() {
    _wizardRequested = true;
    notifyListeners();
  }

  List<String> _allRelativePaths() =>
      [for (final file in _summary.files) file.relativePath];

  // The --scripts PATH-list separator (mpv options.rst): ':' on Unix, ';'
  // on Windows. Exposed for the plugin scripts merge, which appends to the
  // same option value.
  static String get scriptSeparator => Platform.isWindows ? ';' : ':';
}
