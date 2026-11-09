// Dart port of mpv-emo src/quality/QualityProfileEngine.{h,cpp} (A-class:
// zero-engine pure decision table, function-level translation; PORT-MAP §1).
// The 1.x provenance comments below ARE the spec and are carried over
// verbatim — every mpv option name and value cited in them was verified
// against the mpv v0.37.0 docs and sources by the 1.x project (CI built
// against libmpv 0.37).
//
// P5 (v1 subset) quality engine: a pure decision table without mpv, GUI or
// filesystem access, so the whole table is unit-testable.
//
// Input: detected media facts + user preferences. Output: the mpv options
// EmoPlay should apply. Every mpv option name and value used here was
// verified against the mpv v0.37.0 docs and sources (CI builds against
// libmpv 0.37):
//   - "scale": default is "lanczos"; "ewa_lanczossharp" is a documented
//     choice (DOCS/man/options.rst --scale; video/out/gpu/video.c
//     gl_video_opts_def).
//   - "deband": flag, default no (video.c gl_video_opts_def has no value).
//   - "tone-mapping": choice set auto/clip/mobius/reinhard/hable/gamma/
//     linear/spline/bt.2390/bt.2446a/st2094-40/st2094-10 (options.rst
//     --tone-mapping). BUT under vo=libmpv only the classic gpu renderer
//     runs (video/out/vo_libmpv.c render_backends[] = { render_backend_gpu,
//     render_backend_sw }); "spline"/"bt.2446a"/"st2094-40" are gpu-next
//     only, so this engine never emits them. Supported here: auto, clip,
//     mobius, reinhard, hable, gamma, linear, bt.2390.
//   - "target-colorspace-hint": requires gpu-next per options.rst, i.e. a
//     no-op in this pipeline. v1 still sets it for HDR sources (harmless
//     and correct once a gpu-next-capable pipeline arrives).
//   - "glsl-shaders": a path-list option (options.rst --glsl-shaders). The
//     applier mutates it with the documented "change-list" command
//     (input.rst change-list; player/command.c cmd_change_list; the list
//     option actions are add/append/clr/pre/set/remove, options/m_option.c).
//
// v1 simplifications versus the mpv-Emo adaptive-quality semantics
// (docs/nativeization-plan.md §2.1): no GPU-tier detection, no release-group
// shader dictionaries (a fixed keyword list instead), and no snapshot of
// user-set values — tier "off" resets the managed options to mpv defaults.
library;

/// Content type the engine optimizes for. "Auto" resolves through the
/// animated content hint of [MediaInfo] (1.x `ContentMode`).
enum ContentMode { auto, anime, live }

/// User-facing quality tiers (1.x `QualityTier`).
enum QualityTier { off, low, medium, high }

ContentMode contentModeFromString(String value) {
  switch (value) {
    case 'anime':
      return ContentMode.anime;
    case 'live':
      return ContentMode.live;
  }
  return ContentMode.auto;
}

String contentModeToString(ContentMode mode) {
  switch (mode) {
    case ContentMode.anime:
      return 'anime';
    case ContentMode.live:
      return 'live';
    case ContentMode.auto:
      return 'auto';
  }
}

QualityTier qualityTierFromString(String value) {
  switch (value) {
    case 'low':
      return QualityTier.low;
    case 'medium':
      return QualityTier.medium;
    case 'high':
      return QualityTier.high;
  }
  return QualityTier.off;
}

String qualityTierToString(QualityTier tier) {
  switch (tier) {
    case QualityTier.low:
      return 'low';
    case QualityTier.medium:
      return 'medium';
    case QualityTier.high:
      return 'high';
    case QualityTier.off:
      return 'off';
  }
}

/// Verified against mpv v0.37.0: "lanczos" is the default --scale
/// (video/out/gpu/video.c gl_video_opts_def), "ewa_lanczossharp" a
/// documented choice (DOCS/man/options.rst --scale).
const String _kDefaultScale = 'lanczos';
const String _kQualityScale = 'ewa_lanczossharp';

/// Tone-mapping picks by tier. "spline"/"bt.2446a" would be nicer but are
/// gpu-next only in v0.37 (see the library comment); "bt.2390" is the
/// perceptual EETF available under the classic gpu renderer.
const String _kToneMappingDefault = 'auto';
const String _kToneMappingQuality = 'bt.2390';
const String _kToneMappingLight = 'mobius';

/// Keyword list for the "animated" content hint — a v1 simplification of the
/// mpv-Emo release-group dictionary (docs/nativeization-plan.md §2.1).
/// Deliberately conservative to avoid flagging live-action titles.
const List<String> _animeHintTokens = <String>[
  'anime',
  'at-x',
  'bs11',
  'baha',
  'b-global',
  'bglobal',
  'cr.webrip',
  'cr-webrip',
  'vcb-studio',
  'leopard-raws',
  'ma10p',
];

/// Tone-mapping values valid under vo=libmpv (classic gpu renderer) in mpv
/// v0.37.0 — see the library comment for the verification trail.
const List<String> _supportedToneMappings = <String>[
  'auto',
  'clip',
  'mobius',
  'reinhard',
  'hable',
  'gamma',
  'linear',
  'bt.2390',
];

/// --scale choices documented in the mpv v0.37.0 manual (options.rst
/// --scale). The manual notes there are more undocumented filters; only the
/// documented set is accepted as a user override.
const List<String> _supportedScales = <String>[
  'bilinear',
  'lanczos',
  'ewa_lanczos',
  'ewa_lanczossharp',
  'ewa_lanczos4sharpest',
  'mitchell',
  'hermite',
  'catmull_rom',
  'oversample',
  'linear',
];

/// Anime4K v4 group chains, file names and order verified against upstream
/// bloc97/Anime4K md/Template/GLSL_Mac_Linux_Low-end/input.conf (the "Fast"
/// variants chosen so lower-end GPUs survive; verified 2026-11-07 against
/// the upstream repository — the v4.0.1 GLSL_Instructions.md carried an
/// older A+A ordering and upstream has since replaced it with the template
/// files). The engine mounts only files that actually exist in the user's
/// shaders directory, so partial installs degrade gracefully.
///
/// Mode A   = Clamp_Highlights -> Restore_CNN_M -> Upscale_CNN_x2_M ->
///            AutoDownscalePre_x2 -> AutoDownscalePre_x4 -> Upscale_CNN_x2_S
/// Mode A+A = Clamp_Highlights -> Restore_CNN_M -> Upscale_CNN_x2_M ->
///            Restore_CNN_S -> AutoDownscalePre_x2 -> AutoDownscalePre_x4
///            -> Upscale_CNN_x2_S (second restore pass runs on the
///            upscaled texture, before the downscale preparation)
/// Mode C   = Clamp_Highlights -> Upscale_Denoise_CNN_x2_M ->
///            AutoDownscalePre_x2 -> AutoDownscalePre_x4 -> Upscale_CNN_x2_S
///
/// 1.x provenance: the three chains are a verbatim copy of
/// mpv-emo/src/quality/QualityProfileEngine.cpp L82-118 (SPEC §4.5
/// invariant: "多文件精确序列照抄").
const List<String> _anime4kGroupA = <String>[
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

const List<String> _anime4kGroupAPlusA = <String>[
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_Restore_CNN_S.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

const List<String> _anime4kGroupC = <String>[
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

// Live-action high tier: optional SSimSuperRes group (agyild's shader;
// mounted only when present among the available files).
const List<String> _ssimSuperResGroup = <String>['SSimSuperRes.glsl'];

/// Resolution -> Anime4K group (v1 constant table). Bigger sources need less
/// upscaling work, so the heaviest chain is reserved for SD sources.
///
/// 1.x provenance: mpv-emo/src/quality/QualityProfileEngine.cpp L130-137
/// (height >= 1440 -> "C", >= 900 -> "A", else "A+A" — the SPEC §4.5
/// 900/1440 grouping).
String anime4kGroupForHeight(int height) {
  if (height >= 1440) {
    return 'C';
  }
  if (height >= 900) {
    return 'A';
  }
  return 'A+A';
}

List<String> _shaderGroupByName(String group) {
  switch (group) {
    case 'A':
      return _anime4kGroupA;
    case 'A+A':
      return _anime4kGroupAPlusA;
    case 'C':
      return _anime4kGroupC;
  }
  return _ssimSuperResGroup;
}

/// Match a wanted group file against the available shader list: an entry
/// matches when it equals the file name or sits in a subdirectory carrying
/// it (e.g. "Anime4K/Anime4K_Restore_CNN_M.glsl").
List<String> resolveShaderGroup(String group, List<String> available) {
  final wanted = _shaderGroupByName(group);
  final resolved = <String>[];
  for (final name in wanted) {
    for (final candidate in available) {
      if (candidate == name || candidate.endsWith('/$name')) {
        if (!resolved.contains(candidate)) {
          resolved.add(candidate);
        }
        break;
      }
    }
  }
  return resolved;
}

/// Facts about the current media, gathered by the caller from observed mpv
/// properties and file heuristics (QualityController does this).
class MediaInfo {
  int width = 0; // video-params/w; 0 = unknown
  int height = 0; // video-params/h
  double fps = 0.0; // container-fps; 0 = unknown

  /// "animated" when the track-tag/filename heuristics say anime, else "".
  String vfFormat = '';

  /// video-params primaries/gamma hint (see [isHdrVideoParams]).
  bool isHdr = false;

  /// Shader files (relative paths, "*.glsl") present in the user's shaders
  /// directory. The engine only ever mounts files from this list.
  List<String> availableShaders = const [];
}

/// User preferences shown in the quality panel and persisted in the
/// settings.json "quality" section.
class UserPrefs {
  ContentMode contentMode = ContentMode.auto;
  QualityTier qualityTier = QualityTier.off;

  /// "auto" (engine picks by tier) or an explicit tone-mapping value for
  /// HDR sources. Values outside the vo=libmpv-supported set fall back to
  /// the tier pick.
  String toneMappingMode = 'auto';

  /// "" (engine picks by tier) or an explicit --scale value used whenever
  /// the engine is active.
  String scaleOverride = '';

  /// "auto" (decision table: deband on while the engine is active), "yes"
  /// or "no" — user override from the panel's deband control.
  String debandMode = 'auto';
}

/// Engine decision (1.x `Result`; renamed to avoid the overly generic
/// library-level name). [options] carries scalar mpv options for
/// setProperty; the special key "glsl-shaders" holds a `List<String>` of
/// desired shader paths, which the applier sends as "change-list" commands
/// instead of setProperty. [shaders] mirrors that list.
class QualityResult {
  final Map<String, Object?> options = <String, Object?>{};
  final List<String> shaders = <String>[];
}

/// Run the decision table (table documented in QualityProfileEngine.cpp,
/// ported function-for-function below).
QualityResult compute(MediaInfo info, UserPrefs prefs) {
  final result = QualityResult();

  if (prefs.qualityTier == QualityTier.off) {
    // Decision table row "off": clear everything back to mpv defaults
    // (verified defaults; see the library comment).
    result.options['scale'] = _kDefaultScale;
    result.options['deband'] = false;
    result.options['tone-mapping'] = _kToneMappingDefault;
    result.options['target-colorspace-hint'] = false;
    result.options['glsl-shaders'] = <String>[];
    return result;
  }

  // Content resolution: explicit mode wins, "auto" follows the hint.
  final anime = prefs.contentMode == ContentMode.anime ||
      (prefs.contentMode == ContentMode.auto &&
          info.vfFormat == 'animated');

  // High-frame-rate sources (>= 50 fps): heavy shader groups cannot keep
  // up, so they are dropped (downgrade rule keeps only the scale filter).
  final highFps = info.fps >= 50.0;

  // Shader groups: high tier only, never on HDR sources (HDR 避让) and
  // never on high-frame-rate sources. With unknown video parameters
  // (height<=0, e.g. media info not decoded yet or audio-only files) no
  // group is mounted at all: the resolution table and the HDR/HFR checks
  // cannot be evaluated — the caller re-runs the table when
  // video-params/container-fps arrive.
  var shaders = <String>[];
  final paramsKnown = info.height > 0;
  if (paramsKnown &&
      prefs.qualityTier == QualityTier.high &&
      !info.isHdr &&
      !highFps) {
    final group =
        anime ? anime4kGroupForHeight(info.height) : 'SSimSuperRes';
    shaders = resolveShaderGroup(group, info.availableShaders);
  }

  // Scale: low tier stays at the mpv default, medium/high sharpen; an
  // explicit user override wins whenever it names a documented --scale
  // value (corrupted settings.json values fall back to the tier pick).
  var scale =
      prefs.qualityTier == QualityTier.low ? _kDefaultScale : _kQualityScale;
  if (prefs.scaleOverride.isNotEmpty && isSupportedScale(prefs.scaleOverride)) {
    scale = prefs.scaleOverride;
  }

  result.options['scale'] = scale;
  // Deband: the mode is normalized first — "yes" forces it on, "no"
  // forces it off, and any other value (corrupted settings.json values
  // included) means "auto", where the table turns deband on for every
  // active tier (mpv's own default is "no").
  result.options['deband'] = prefs.debandMode != 'no';

  // Tone-mapping series: managed on every active apply so that values
  // left by a previous HDR file cannot leak into SDR playback (and vice
  // versa). While the engine is active it owns the managed option set
  // (scale/deband behave the same way); the inert-at-off rule keeps
  // imported values untouched as long as the engine is never engaged.
  if (info.isHdr) {
    // HDR sources: the explicit user mode wins when it is usable under
    // vo=libmpv; otherwise the engine picks by tier.
    var tone = prefs.toneMappingMode;
    if (!isSupportedToneMapping(tone) || tone == _kToneMappingDefault) {
      tone = prefs.qualityTier == QualityTier.low
          ? _kToneMappingLight
          : _kToneMappingQuality;
    }
    result.options['tone-mapping'] = tone;
    // gpu-next only in v0.37 (no-op here); set for pipeline parity.
    result.options['target-colorspace-hint'] = true;
  } else {
    result.options['tone-mapping'] = _kToneMappingDefault;
    result.options['target-colorspace-hint'] = false;
  }

  result.options['glsl-shaders'] = shaders;
  result.shaders.addAll(shaders);
  return result;
}

/// True when video-params (the map obtained by observing the "video-params"
/// NODE property) indicates HDR: BT.2020 primaries or PQ/HLG transfer.
bool isHdrVideoParams(Map<Object?, Object?> videoParams) {
  // mpv v0.37 property values (input.rst video-params/*): "primaries"
  // e.g. "bt.709"/"bt.2020"; "gamma" (transfer) e.g. "bt.1886"/"pq"/"hlg".
  final primaries = videoParams['primaries'] is String
      ? videoParams['primaries'] as String
      : '';
  final gamma = videoParams['gamma'] is String
      ? videoParams['gamma'] as String
      : '';
  return primaries == 'bt.2020' || gamma == 'pq' || gamma == 'hlg';
}

/// Filename/title heuristic (v1 keyword list, see [_animeHintTokens]):
/// returns "animated" when the name carries one of the anime release
/// tokens, otherwise "".
String animatedHintFrom(String pathOrTitle) {
  final lower = pathOrTitle.toLowerCase();
  for (final token in _animeHintTokens) {
    if (lower.contains(token)) {
      return 'animated';
    }
  }
  return '';
}

/// Tone-mapping values that work under vo=libmpv (verified against mpv
/// v0.37.0, see the library comment). Used to validate the user preference.
bool isSupportedToneMapping(String value) =>
    _supportedToneMappings.contains(value);

/// --scale values documented in the mpv v0.37.0 manual (options.rst
/// --scale): bilinear, lanczos, ewa_lanczos, ewa_lanczossharp,
/// ewa_lanczos4sharpest, mitchell, hermite, catmull_rom, oversample,
/// linear. Used to validate the panel's scale override so that corrupted
/// settings.json values are never forwarded to mpv.
bool isSupportedScale(String value) => _supportedScales.contains(value);
