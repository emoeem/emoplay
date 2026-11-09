// Dart port of mpv-emo src/quality/InterpolationDecision.{h,cpp} (A-class:
// zero-engine pure decision table, function-level translation; PORT-MAP §1).
// The 1.x provenance comments below ARE the spec and are carried over.
//
// P5 v2 frame interpolation: the pure decision table for the honest
// external-dependency pattern (docs/nativeization-plan.md §2.1, vs/ row).
// No mpv, no GUI, no filesystem access — the controller gathers the facts
// and applies the result, so the whole table is unit-testable.
//
// mpv v0.37.0 facts this table builds on (verified against the upstream
// sources by the 1.x project; CI linked libmpv 0.37):
//   - The vapoursynth video filter takes "file" (string, M_OPT_FILE),
//     "buffered-frames" (default 4) and "concurrent-frames" (default auto)
//     (video/filter/vf_vapoursynth.c vf_opts_fields); the filter name is
//     "vapoursynth". All interpolation logic lives in the .vpy script, so
//     the assembled entry carries the script path, nothing else.
//   - Filter chain entries accept a "@label:" prefix (DOCS/man/vf.rst;
//     labels restricted to [A-Za-z0-9_-], options/m_option.c NAMECH), and
//     "change-list vf append/remove" mutates the list at runtime
//     (m_option_type_obj_settings_list actions; player/command.c
//     cmd_change_list). Appending an entry with an existing label replaces
//     it in place; "remove @label" deletes by label (parse_obj_settings_del).
//   - Sub-param values may be quoted as "%len%<len bytes>" (read_subparam),
//     which is byte-exact: it protects Windows drive letters ("C:/..."),
//     commas and other metacharacters inside the script path.
//   - "vf" read back as MPV_FORMAT_NODE is an array of maps with
//     name/label/enabled/params (get_obj_settings_list) — the probe reads
//     that back to verify mpv actually accepted our entry.
//
// 2.0 note (probed 2026-11-10, throwaway dlopen harness against the shipped
// build/native_assets/linux/libmpv.so.2 = "mpv v0.41.0-11-gf011d73d5-dirty"):
// the media-kit fork only exposes MPV_FORMAT_STRING property reads, where
// the vf chain serializes as comma-joined "[@label:]name[=k=v:k=v]" entries
// (measured: `@emoplay-interp:crop=w=100:h=100,scale=w=64:h=64`); a
// change-list append with an existing label replaces in place (measured);
// `remove @label` of a missing label only warns (rc=0). The NODE-shaped
// classification functions below stay byte-identical to 1.x and are fed by
// MpvQualityEngine.vfChain(), which parses the measured string form into
// {name, label} maps (see lib/quality/mpv_quality_engine.dart).
library;

import 'dart:convert';

/// The vf entry label EmoPlay owns. The controller only ever touches the
/// chain entry carrying this label; anything else is user/imported config.
String entryLabel() => 'emoplay-interp';

/// The mpv filter name the entry uses ("vapoursynth").
String vapoursynthFilterName() => 'vapoursynth';

/// vs/ preset semantics from docs/nativeization-plan.md §2.1 (mpv-Emo
/// 补帧 presets): only the naming/admission semantics are adopted — the
/// .vpy script files themselves stay external user assets (nativeization
/// plan §0: no asset copying), expected in the controller's scripts dir
/// under the documented preset file names.
class PresetInfo {
  const PresetInfo(this.id, this.scriptName, this.note);

  /// Persisted id, e.g. "MEMC_RIFE_STD".
  final String id;

  /// Expected script file, e.g. "MEMC_RIFE_STD.vpy".
  final String scriptName;

  /// One-line backend semantics for the code reader.
  final String note;
}

/// The preset table mirrors the mpv-Emo vs/ interpolation preset semantics
/// documented in docs/nativeization-plan.md §2.1 (MEMC_* names). The .vpy
/// files are NOT shipped: the user points EmoPlay at a scripts directory
/// holding their own scripts (e.g. an existing mpv-Emo vs/ checkout), so
/// the app never fakes a capability it does not carry.
const List<PresetInfo> _kPresets = <PresetInfo>[
  PresetInfo('MEMC_RIFE_NV', 'MEMC_RIFE_NV.vpy',
      'RIFE motion interpolation, NVIDIA-preferred backend'),
  PresetInfo(
      'MEMC_RIFE_STD', 'MEMC_RIFE_STD.vpy', 'RIFE motion interpolation, standard backend'),
  PresetInfo(
      'MEMC_RIFE_DML', 'MEMC_RIFE_DML.vpy', 'RIFE motion interpolation, DirectML backend'),
  PresetInfo('MEMC_SVP_PRO', 'MEMC_SVP_PRO.vpy', 'SVP 4 Pro motion interpolation'),
  PresetInfo('MEMC_MVT_LQ', 'MEMC_MVT_LQ.vpy',
      'MVtools motion interpolation, low quality/low cost'),
  PresetInfo('MEMC_DRBA_NV', 'MEMC_DRBA_NV.vpy',
      'DRBA (depth-aware rate adjustment) NVIDIA variant'),
];

List<PresetInfo> get presets => _kPresets;

bool isKnownPreset(String id) {
  for (final preset in _kPresets) {
    if (id == preset.id) {
      return true;
    }
  }
  return false;
}

/// Script file name for a known preset id, "" otherwise.
String scriptNameForPreset(String id) {
  for (final preset in _kPresets) {
    if (id == preset.id) {
      return preset.scriptName;
    }
  }
  return '';
}

/// Facts the controller gathers from the live engine and filesystem.
class MediaFacts {
  double fps = 0.0; // container-fps; 0 = not known yet

  /// video-params BT.2020 primaries / PQ / HLG.
  bool isHdr = false;

  /// The preset's script file exists in the scripts directory.
  bool scriptAvailable = false;

  /// The vf chain already carries a vapoursynth entry EmoPlay does not own
  /// (imported mpv.conf or a script): we stand down rather than fight it.
  bool foreignVapoursynth = false;
}

/// Why interpolation is not active for the current file. Not all of these
/// are errors: disabled/fpsUnknown are the ordinary idle/no-media states.
enum InterpolationBlock {
  none,
  disabled, // switch off (or preset id unknown)
  fpsUnknown, // media params not decoded yet — wait, don't guess
  highFps, // fps at/above the threshold: nothing to interpolate
  hdr, // HDR sources excluded (safety fallback semantics)
  scriptMissing, // preset .vpy not found in the scripts directory
  foreignVapoursynth, // a vapoursynth entry we do not own is already in vf
}

/// Admission decision for the current facts. |enabled| is the persisted
/// switch; a disabled controller is blocked with
/// [InterpolationBlock.disabled], not an error.
InterpolationBlock admission(MediaFacts facts, bool enabled) {
  if (!enabled) {
    return InterpolationBlock.disabled;
  }
  // A vapoursynth entry we do not own wins: the user's imported config
  // (or a script) manages interpolation already — never fight it.
  if (facts.foreignVapoursynth) {
    return InterpolationBlock.foreignVapoursynth;
  }
  // Script presence is the hardest precondition: no script means nothing
  // to apply regardless of media state. Check BEFORE fps/ HDR so the user
  // always sees the actionable hint first (not the transient fps-unknown
  // while nothing is playing yet).
  if (!facts.scriptAvailable) {
    return InterpolationBlock.scriptMissing;
  }
  // Media parameters unknown (idle or not yet decoded): never guess.
  // The controller re-runs admission when video-params/fps arrive.
  if (facts.fps <= 0.0) {
    return InterpolationBlock.fpsUnknown;
  }
  if (facts.fps >= highFpsThreshold()) {
    return InterpolationBlock.highFps;
  }
  if (facts.isHdr) {
    return InterpolationBlock.hdr;
  }
  return InterpolationBlock.none;
}

/// Stable id strings for the UI hint mapping (panel shows a localized
/// text). Same values as 1.x blockToString().
String blockToString(InterpolationBlock block) {
  switch (block) {
    case InterpolationBlock.none:
      return '';
    case InterpolationBlock.disabled:
      return 'disabled';
    case InterpolationBlock.fpsUnknown:
      return 'fps-unknown';
    case InterpolationBlock.highFps:
      return 'high-fps';
    case InterpolationBlock.hdr:
      return 'hdr';
    case InterpolationBlock.scriptMissing:
      return 'script-missing';
    case InterpolationBlock.foreignVapoursynth:
      return 'foreign-vapoursynth';
  }
}

/// Frame rates at or above this value are not interpolated (HFR safety
/// fallback; same threshold as the v1 shader HFR avoidance).
double highFpsThreshold() => 50.0;

/// The labeled vf entry the controller appends for |scriptPath|, with the
/// file value in mpv's %len% quoting so paths with ':' (Windows drives),
/// ',' or '[' survive the sub-param parser verbatim.
String vfEntry(String scriptPath) {
  // "%len%" quoting (options/m_option.c read_subparam): byte-exact, so
  // the script path survives the ':'-separated sub-param parser on every
  // platform ("C:/Users/..." would otherwise split into extra params).
  final utf8Bytes = utf8.encode(scriptPath).length;
  return '@${entryLabel()}:${vapoursynthFilterName()}=file=%$utf8Bytes%$scriptPath';
}

/// True when the vf readback contains OUR entry (our label AND the
/// vapoursynth filter name). The label, not just the name, is what
/// distinguishes our entry from a user-configured one.
///
/// |vfChain| is the NODE-shaped readback: a list of maps carrying "name"
/// and optionally "label" (mpv get_obj_settings_list; see the library
/// comment for the 2.0 string-form adapter that feeds this).
bool vfHasLabeledEntry(List<Object?> vfChain) {
  for (final entry in vfChain) {
    if (entry is Map) {
      if (_entryString(entry, 'name') == vapoursynthFilterName() &&
          _entryString(entry, 'label') == entryLabel()) {
        return true;
      }
    }
  }
  return false;
}

/// True when the vf readback contains a vapoursynth entry that is NOT ours.
bool vfHasForeignVapoursynth(List<Object?> vfChain) {
  for (final entry in vfChain) {
    if (entry is! Map) {
      continue;
    }
    if (_entryString(entry, 'name') != vapoursynthFilterName()) {
      continue;
    }
    if (_entryString(entry, 'label') != entryLabel()) {
      return true;
    }
  }
  return false;
}

String _entryString(Map<Object?, Object?> entry, String key) {
  final value = entry[key];
  return value is String ? value : '';
}
