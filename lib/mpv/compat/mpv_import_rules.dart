// Dart port of mpv-emo src/compat/MpvImportRules.{h,cpp} (A-class, pure
// value logic). The three tables (forced / stripped / redirected) and the
// audit message formats are copied verbatim — they are behavior规格 and the
// ported tests assert them. mpv v0.37 citations from the C++ source comments
// are preserved.

import 'package:emoplay/mpv/config/mpv_config_parser.dart';

/// Result of applying the import rules to a parsed mpv.conf (1.x struct
/// ImportRuleResult).
class ImportRuleResult {
  // Option map ready for the player bootstrap: surviving user options plus
  // the forced embedding options and redirected write paths.
  final Map<String, String> options = {};

  // Audit lines: "vo: user value 'gpu-next' replaced with 'libmpv'".
  final List<String> forced = [];

  // Audit lines: "profile: 'Target' (user profiles are not applied)".
  final List<String> skipped = [];

  // Audit lines: "watch-later-dir: redirected to '<path>'".
  final List<String> redirected = [];

  // Names of [profile] sections seen in the user's mpv.conf (not applied).
  final List<String> profileNames = [];
}

/// Applies EmoPlay's import policy to options parsed from a user's mpv.conf.
/// The policy implements two user principles (1.x class comment):
///
/// 1. GUI embedding constraints win over user config: `vo`, `osc` and
///    `terminal` are forced to the embed-safe values no matter what the
///    imported file says. Under media_kit the equivalents live outside the
///    option map (SPEC §4.3: vo=libmpv is set by VideoController's default
///    `vo` on desktop, osc=no by PlayerConfiguration(osc: false), and
///    libmpv never touches the terminal — see client.h "libmpv profile"):
///    the forced table still runs so the audit records every replacement.
/// 2. EmoPlay never writes into the user's mpv directory: options that make
///    the core write state files (watch-later, screenshots, shader/ICC and
///    demuxer caches, stats/log dumps) are redirected into EmoPlay's own app
///    data directory, and `include=` / `profile=` are dropped entirely.
///
/// Everything else passes through: hwdec, volume, keep-open, scale, and the
/// like are imported as-is. Values containing `~~` are kept — the 1.x engine
/// pointed mpv's config-dir at the user's directory so they resolved there
/// without copying anything. (media_kit exposes no pre-init config-dir hook —
/// client.h lists config-dir among the "options which are only read at
/// initialization time", verified post-init-inert on the shipped libmpv
/// v0.41.0-11 build on 2026-11-10 — so `~~` values survive verbatim here and
/// their resolution is an engine-side concern, unchanged from 1.x at this
/// layer.)
///
/// Pure logic, no I/O: unit-testable in isolation.
class MpvImportRules {
  MpvImportRules._();

  // Embedding-critical options and the values that must win (1.x
  // kForcedValues, order = force order).
  static const List<({String key, String value, String reason})>
      _forcedValues = [
    (key: 'vo', value: 'libmpv', reason: 'embedded render API'),
    (key: 'osc', value: 'no', reason: 'QML UI draws its own controls'),
    (key: 'terminal', value: 'no', reason: 'GUI embedding has no terminal'),
  ];

  // Options removed from user config before applying (1.x kStrippedKeys,
  // order and per-key reasoning preserved).
  static const List<String> _strippedKeys = [
    'include', // arbitrary file loading bypasses the audit
    'profile', // profile refs; user profiles are not defined
    'scripts', // owned by the compat controller
    'input-conf', // owned by the compat controller
    'config-dir', // owned by the compat controller
    'watch-later-dir', // write path -> app data
    'screenshot-directory', // write path -> app data
    'gpu-shader-cache-dir', // write path -> app data
    'icc-cache-dir', // write path -> app data
    'dump-stats', // would write to a user-chosen path
    'log-file', // would write to a user-chosen path
  ];

  // Write paths land in EmoPlay's app data, never in the user's mpv
  // directory (which config-dir pointed at for ~~ resolution in 1.x).
  // Single source of truth shared by this startup pass and the runtime
  // redirects (1.x: MpvImportRules::redirectTarget used by IccController).
  static const List<({String key, String subdir})> _redirects = [
    (key: 'watch-later-dir', subdir: 'watch_later'),
    (key: 'screenshot-directory', subdir: 'screenshots'),
    (key: 'gpu-shader-cache-dir', subdir: 'shader_cache'),
    (key: 'icc-cache-dir', subdir: 'icc_cache'),
    (key: 'demuxer-cache-dir', subdir: 'demuxer_cache'),
  ];

  /// Redirect target for a write-path option, e.g. "icc-cache-dir" ->
  /// "|appDataDir|/icc_cache". Empty string when the option is not a
  /// redirect target (unknown keys and read paths like icc-profile).
  static String redirectTarget(String key, String appDataDir) {
    for (final redirect in _redirects) {
      if (key == redirect.key) {
        return '$appDataDir/${redirect.subdir}';
      }
    }
    return '';
  }

  /// All five write-path redirects resolved against |appDataDir|, from the
  /// same table as [redirectTarget] (single source of truth, 1.x invariant:
  /// the startup pass and the player-side preset must always agree on the
  /// sub-directory names).
  static Map<String, String> redirectTargetsFor(String appDataDir) => {
        for (final redirect in _redirects)
          redirect.key: redirectTarget(redirect.key, appDataDir),
      };

  /// Options forced to embed-safe values, in force order.
  static List<String> get forcedKeys =>
      [for (final forced in _forcedValues) forced.key];

  /// Options dropped from user config (replaced or removed by the engine).
  static List<String> get strippedKeys => List.of(_strippedKeys);

  static bool _isStripped(String key) => _strippedKeys.contains(key);

  static ({String key, String value, String reason})? _findForced(String key) {
    for (final forced in _forcedValues) {
      if (key == forced.key) {
        return forced;
      }
    }
    return null;
  }

  /// |mpvDir| is the user's mpv config directory (for audit messages),
  /// |appDataDir| EmoPlay's writable app data directory receiving redirected
  /// write paths. appDataDir must be non-empty.
  static ImportRuleResult apply(
    List<MpvConfEntry> entries,
    String mpvDir,
    String appDataDir,
  ) {
    final result = ImportRuleResult();

    // Pass 1: user options. Top-level options only — everything after a
    // [profile] header belongs to that profile and is not applied (profiles
    // cannot be defined through mpv_set_option_string; they are reported
    // instead). Last occurrence of an option wins, matching mpv.
    var currentProfile = '';
    for (final entry in entries) {
      switch (entry.kind) {
        case MpvConfEntryKind.profileHeader:
          currentProfile = entry.profileName;
          result.profileNames.add(entry.profileName);
          result.skipped.add(
              'profile [${entry.profileName}] in $mpvDir: section not applied in P4');
          break;
        case MpvConfEntryKind.option:
          if (currentProfile.isNotEmpty) {
            continue; // belongs to the profile above; already reported
          }

          // Values reach mpv as runtime properties, where a raw line's
          // inline comment would ride along (mpv strips it only when it
          // reads the file itself — see
          // MpvConfigParser.runtimeOptionValue). Strip here so string-typed
          // options cannot swallow their own annotation; the parser keeps
          // the raw line for the settings editor's round-trip.
          final value = MpvConfigParser.runtimeOptionValue(entry.value);

          if (entry.key == 'screenshot-template' &&
              value.contains('~~')) {
            // A config-dir-relative screenshot template would land inside
            // the user's mpv directory even with screenshot-directory
            // redirected, because ~~ expands to the user config dir.
            result.skipped.add(
                "screenshot-template: '$value' (~~ path would write into the user's mpv directory)");
            continue;
          }

          if (_isStripped(entry.key)) {
            result.skipped.add(
                '${entry.key}: \'$value\' (${entry.key == 'profile' ? 'profiles are not applied in P4' : 'managed by EmoPlay'})');
            continue;
          }

          final forced = _findForced(entry.key);
          if (forced != null) {
            result.forced.add(
                '${entry.key}: user value \'$value\' replaced with \'${forced.value}\' (${forced.reason})');
            continue; // the forced value is written in pass 2
          }

          result.options[entry.key] = value;
          break;
        case MpvConfEntryKind.unknown:
          break;
      }
    }

    // Pass 2: forced embedding values win over everything from pass 1.
    for (final forced in _forcedValues) {
      result.options[forced.key] = forced.value;
    }

    // Pass 3: write paths land in EmoPlay's app data, never in the user's
    // mpv directory (which config-dir pointed at for ~~ resolution).
    for (final redirect in _redirects) {
      final path = redirectTarget(redirect.key, appDataDir);
      result.options[redirect.key] = path;
      result.redirected.add('${redirect.key} -> $path');
    }

    return result;
  }
}
