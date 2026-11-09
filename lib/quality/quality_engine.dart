// The mpv surface the quality controllers drive (M6, PORT-MAP §2 B-class
// "src/mpv/MpvEngine.cpp（语义层）" consumers: QualityController /
// InterpolationController / IccController used the raw MpvEngine* pointer).
//
// 1.x semantics preserved one-for-one:
//   - facts are read ON DEMAND from the live engine (docs/architecture.md
//     decision 7 — no cached play state in the controllers);
//   - the 1.x engine signals fileLoaded / videoParamsChanged /
//     containerFpsChanged / frameDropCountChanged become broadcast streams;
//   - scalar options go through setProperty, list options through the
//     documented change-list command (mpv input.rst change-list;
//     player/command.c cmd_change_list).
//
// The interface lives without the media_kit import so the controllers and
// their tests stay engine-agnostic (1.x passed a null MpvEngine in tests —
// "then nothing reaches mpv"); NativeQualityEngine in
// native_quality_engine.dart adapts a media_kit Player.
library;

import 'dart:async';

/// The subset of mpv the quality controllers need.
abstract interface class MpvQualityEngine {
  // ------------------------------------------------------------- fact reads

  /// The "video-params" NODE property as a map (w/h/primaries/gamma keys,
  /// values as provided by mpv). Empty when idle or not yet decoded — the
  /// controllers treat that as "unknown, wait" (1.x QVariantMap read).
  Future<Map<Object?, Object?>> videoParams();

  /// The "container-fps" property as a double; 0.0 when unavailable
  /// (1.x getProperty(...).toDouble() on the observed value).
  Future<double> containerFps();

  /// The "path" property; "" when unavailable. 1.x gatherMediaInfo used it
  /// for the animated-content hint (file name first).
  Future<String> mediaPath();

  /// The "media-title" property; "" when unavailable (1.x hint fallback).
  Future<String> mediaTitle();

  /// The "glsl-shaders" path list currently mounted (absolute paths).
  Future<List<String>> glslShaders();

  /// The "vf" chain as NODE-shaped entries (maps with "name" and optional
  /// "label"; 1.x MPV_FORMAT_NODE read of get_obj_settings_list). Feeds
  /// InterpolationDecision.vfHasLabeledEntry/vfHasForeignVapoursynth.
  Future<List<Object?>> vfChain();

  /// The "icc-profile" property; "" when unset (1.x startup snapshot read).
  Future<String> iccProfile();

  // -------------------------------------------------------------- mutations

  /// Sets a scalar property (string format — the media-kit fork exposes
  /// mpv_set_property_string only; booleans arrive as "yes"/"no").
  Future<void> setProperty(String property, String value);

  /// Runs an mpv command (change-list clr/append for the list options).
  /// The 1.x controllers never trusted the command's return value for
  /// acceptance decisions — the fork logs errors without throwing, so
  /// readbacks stay the source of truth (InterpolationController probe).
  Future<void> command(List<String> args);

  // ------------------------------------------------------- 1.x engine events

  /// 1.x MpvEngine::fileLoaded — fires once per loaded file.
  Stream<void> get fileLoaded;

  /// 1.x MpvEngine::videoParamsChanged — fires whenever video-params change
  /// (including going empty when a file ends).
  Stream<void> get videoParamsChanged;

  /// 1.x MpvEngine::containerFpsChanged — fires with the parsed fps value.
  Stream<double> get containerFpsChanged;

  /// 1.x MpvEngine::frameDropCountChanged — the cumulative dropped-frame
  /// counter (MpvItem's 2s sampler turned deltas into a rate).
  Stream<int> get frameDropCountChanged;

  /// Stops the engine-driven streams. The underlying player is owned by the
  /// player bootstrap; this only detaches the listeners.
  void dispose();
}

/// Parses the "vf" STRING readback into the NODE-shaped chain the pure
/// classification functions expect.
///
/// Measured serialization on the shipped libmpv (v0.41.0-11-gf011d73d5-dirty,
/// probed 2026-11-10 with a throwaway dlopen harness; see
/// native_quality_engine.dart): entries joined by ','; each entry
/// `[@label:]name[=k=v:k=v]`; %len% quoting is UNQUOTED in the print form
/// (appended `crop=w=%3%100:h=100` printed as `crop=w=100:h=100`).
///
/// Documented limitation (vs 1.x NODE reads): a foreign entry whose params
/// embed commas (e.g. a lavfi graph) splits into fragments. Classification
/// only needs the name/label of vapoursynth entries; a fragment can never
/// MINT our label (it would have to start with "@emoplay-interp:"), so the
/// decision semantics stay conservative the way 1.x designed them —
/// a mis-fragmented foreign entry can only ever ADD a stand-down, never
/// remove one.
List<Map<String, Object?>> parseVfChain(String readback) {
  final chain = <Map<String, Object?>>[];
  if (readback.isEmpty) {
    return chain;
  }
  for (final raw in readback.split(',')) {
    var entry = raw.trim();
    if (entry.isEmpty) {
      continue;
    }
    final parsed = <String, Object?>{};
    // "@label:name=..." — label restricted to [A-Za-z0-9_-] by mpv
    // (options/m_option.c NAMECH), so the first ':' is the separator.
    if (entry.startsWith('@')) {
      final colon = entry.indexOf(':');
      if (colon > 1) {
        parsed['label'] = entry.substring(1, colon);
        entry = entry.substring(colon + 1);
      } else {
        entry = entry.substring(1);
      }
    }
    final equals = entry.indexOf('=');
    parsed['name'] = equals >= 0 ? entry.substring(0, equals) : entry;
    chain.add(parsed);
  }
  return chain;
}

/// Parses the "glsl-shaders" STRING readback into the mounted path list.
///
/// Measured on the shipped libmpv (same harness): a list built with
/// change-list appends prints colon-joined ("/tmp/one.glsl:/tmp/two.glsl")
/// while a value set as one comma-joined string echoes the comma form.
/// Both separators are therefore accepted; the known mpv limitation stands —
/// paths containing the separator character cannot round-trip (1.x noted
/// the same for the --scripts PATH list; 1.x itself read the list as NODE
/// and had no separator ambiguity).
List<String> parsePathList(String readback) {
  if (readback.isEmpty) {
    return const [];
  }
  // Prefer the comma form; fall back to the change-list colon form. On
  // Linux a leading "C:/"-style drive prefix does not occur (POSIX paths),
  // and a colon inside a mounted shader path is the documented limitation.
  final parts = readback.contains(',') ? readback.split(',') : readback.split(':');
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}
