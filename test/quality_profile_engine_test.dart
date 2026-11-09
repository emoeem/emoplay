// Dart port of mpv-emo tests/test_quality_profile_engine.cpp — headless
// decision-table tests for the P5 v1 quality engine. Key paths of the
// anime/live/off x tier x fps x HDR matrix (mpv.md P5 acceptance).
// Assertion values are copied verbatim from the C++ file (they are the
// behavior spec; PORT-MAP §4).
import 'package:emoplay/quality/quality_profile_engine.dart';
import 'package:flutter_test/flutter_test.dart';

MediaInfo makeInfo({
  int height = 1080,
  double fps = 23.976,
  String vfFormat = '',
  bool hdr = false,
  List<String> shaders = const <String>[],
}) {
  return MediaInfo()
    ..width = height * 16 ~/ 9
    ..height = height
    ..fps = fps
    ..vfFormat = vfFormat
    ..isHdr = hdr
    ..availableShaders = shaders;
}

// The Anime4K "Fast" files a full upstream install provides, nested in a
// subdirectory to exercise the group resolver's path matching.
List<String> fullAnime4kSet() => const <String>[
      'Anime4K/Anime4K_Clamp_Highlights.glsl',
      'Anime4K/Anime4K_Restore_CNN_M.glsl',
      'Anime4K/Anime4K_Restore_CNN_S.glsl',
      'Anime4K/Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      'Anime4K/Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K/Anime4K_Upscale_CNN_x2_S.glsl',
      'Anime4K/Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K/Anime4K_AutoDownscalePre_x4.glsl',
    ];

UserPrefs makePrefs(
  ContentMode mode,
  QualityTier tier, {
  String tone = 'auto',
  String scaleOverride = '',
}) {
  return UserPrefs()
    ..contentMode = mode
    ..qualityTier = tier
    ..toneMappingMode = tone
    ..scaleOverride = scaleOverride;
}

void main() {
  test('offTierResetsEverythingToDefaults', () {
    // "off" clears everything back to the verified mpv defaults, whatever
    // the media is (anime or not, HDR or not).
    final info = makeInfo(height: 2160, vfFormat: 'animated', hdr: true);
    final result = compute(
        info, makePrefs(ContentMode.anime, QualityTier.off));
    expect(result.options['scale'], 'lanczos');
    expect(result.options['deband'], false);
    expect(result.options['tone-mapping'], 'auto');
    expect(result.options['target-colorspace-hint'], false);
    expect(result.shaders, isEmpty);
    expect(result.options['glsl-shaders'] as List<String>, isEmpty);
  });

  test('animeHighFhdMountsGroupA', () {
    final info = makeInfo(
        vfFormat: 'animated', shaders: fullAnime4kSet());
    final result = compute(
        info, makePrefs(ContentMode.auto, QualityTier.high));
    expect(result.options['scale'], 'ewa_lanczossharp');
    expect(result.options['deband'], true);
    // FHD anime resolves to group A (Fast): 6 files in upstream order.
    expect(
      result.shaders,
      <String>[
        'Anime4K/Anime4K_Clamp_Highlights.glsl',
        'Anime4K/Anime4K_Restore_CNN_M.glsl',
        'Anime4K/Anime4K_Upscale_CNN_x2_M.glsl',
        'Anime4K/Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K/Anime4K_AutoDownscalePre_x4.glsl',
        'Anime4K/Anime4K_Upscale_CNN_x2_S.glsl',
      ],
    );
  });

  test('animeHighSdMountsHeavierGroup', () {
    // SD sources get the double-pass A+A chain: upstream CTRL+4 mounts the
    // second Restore_CNN_S right after the first upscale (restore on the
    // upscaled texture, before the downscale preparation).
    final info = makeInfo(height: 720, vfFormat: 'animated',
        shaders: fullAnime4kSet());
    final result = compute(
        info, makePrefs(ContentMode.auto, QualityTier.high));
    expect(result.shaders, hasLength(7));
    expect(result.shaders[1], 'Anime4K/Anime4K_Restore_CNN_M.glsl');
    expect(result.shaders[3], 'Anime4K/Anime4K_Restore_CNN_S.glsl');
  });

  test('animeHighUhdMountsLightestGroup', () {
    // UHD sources only need the lightest chain (mode C).
    final info = makeInfo(height: 2160, vfFormat: 'animated',
        shaders: fullAnime4kSet());
    final result = compute(
        info, makePrefs(ContentMode.auto, QualityTier.high));
    expect(
      result.shaders,
      <String>[
        'Anime4K/Anime4K_Clamp_Highlights.glsl',
        'Anime4K/Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
        'Anime4K/Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K/Anime4K_AutoDownscalePre_x4.glsl',
        'Anime4K/Anime4K_Upscale_CNN_x2_S.glsl',
      ],
    );
  });

  test('liveHighMountsSsimSuperResWhenAvailable', () {
    final info = makeInfo(shaders: <String>['SSimSuperRes.glsl']);
    final result = compute(
        info, makePrefs(ContentMode.live, QualityTier.high));
    expect(result.shaders, <String>['SSimSuperRes.glsl']);
  });

  test('missingShaderFilesAreSkipped', () {
    // Without any available shaders nothing is mounted, but the scale
    // decision still applies ("若存在" semantics).
    final info = makeInfo(vfFormat: 'animated');
    final result = compute(
        info, makePrefs(ContentMode.auto, QualityTier.high));
    expect(result.shaders, isEmpty);
    expect(result.options['scale'], 'ewa_lanczossharp');

    // A partial install mounts only the files that exist.
    final partial = makeInfo(
        vfFormat: 'animated',
        shaders: <String>['Anime4K/Anime4K_Clamp_Highlights.glsl']);
    final partialResult = compute(
        partial, makePrefs(ContentMode.auto, QualityTier.high));
    expect(partialResult.shaders,
        <String>['Anime4K/Anime4K_Clamp_Highlights.glsl']);
  });

  test('unknownVideoParametersSkipShaderGroups', () {
    // Unknown video parameters (height 0: media info not decoded yet, or
    // audio-only files) must not mount any group — neither the heaviest
    // anime chain (which height=0 would otherwise resolve to) nor the
    // live path (HDR/HFR avoidance cannot be evaluated). Scale/deband
    // still apply; the caller reruns the table when params arrive.
    final animeInfo =
        makeInfo(height: 0, fps: 0.0, vfFormat: 'animated',
            shaders: fullAnime4kSet());
    final anime = compute(
        animeInfo, makePrefs(ContentMode.auto, QualityTier.high));
    expect(anime.shaders, isEmpty);
    expect(anime.options['scale'], 'ewa_lanczossharp');
    expect(anime.options['deband'], true);

    final liveInfo = makeInfo(
        height: 0,
        fps: 0.0,
        shaders: <String>['SSimSuperRes.glsl']);
    final live = compute(
        liveInfo, makePrefs(ContentMode.live, QualityTier.high));
    expect(live.shaders, isEmpty);
  });

  test('mediumAndLowTiersNeverMountShaders', () {
    final full = makeInfo(height: 720, vfFormat: 'animated',
        shaders: fullAnime4kSet());

    final medium = compute(
        full, makePrefs(ContentMode.auto, QualityTier.medium));
    expect(medium.shaders, isEmpty);
    expect(medium.options['scale'], 'ewa_lanczossharp');
    expect(medium.options['deband'], true);

    final low = compute(
        full, makePrefs(ContentMode.auto, QualityTier.low));
    expect(low.shaders, isEmpty);
    expect(low.options['scale'], 'lanczos');
    expect(low.options['deband'], true);
  });

  test('highFpsStripsShaderGroupsButKeepsScale', () {
    // Downgrade rule: fps >= 50 keeps the scale filter but drops the
    // shader groups even at the high tier.
    final hfrAnime = makeInfo(fps: 59.94, vfFormat: 'animated',
        shaders: fullAnime4kSet());
    final result = compute(
        hfrAnime, makePrefs(ContentMode.auto, QualityTier.high));
    expect(result.shaders, isEmpty);
    expect(result.options['scale'], 'ewa_lanczossharp');

    // Exactly 50 fps counts as high-frame-rate; 49.94 does not.
    final edge = makeInfo(fps: 50.0, vfFormat: 'animated',
        shaders: fullAnime4kSet());
    expect(
        compute(edge, makePrefs(ContentMode.auto, QualityTier.high))
            .shaders,
        isEmpty);
    final below = makeInfo(fps: 49.94, vfFormat: 'animated',
        shaders: fullAnime4kSet());
    expect(
        compute(below, makePrefs(ContentMode.auto, QualityTier.high))
            .shaders,
        hasLength(6));
  });

  test('hdrAvoidsShadersAndSetsToneMappingByTier', () {
    final hdr = makeInfo(height: 2160, vfFormat: 'animated', hdr: true,
        shaders: fullAnime4kSet());

    final high = compute(
        hdr, makePrefs(ContentMode.auto, QualityTier.high));
    expect(high.shaders, isEmpty);
    expect(high.options['tone-mapping'], 'bt.2390');
    expect(high.options['target-colorspace-hint'], true);

    final medium = compute(
        hdr, makePrefs(ContentMode.auto, QualityTier.medium));
    expect(medium.options['tone-mapping'], 'bt.2390');

    final low =
        compute(hdr, makePrefs(ContentMode.auto, QualityTier.low));
    expect(low.options['tone-mapping'], 'mobius');
  });

  test('hdrExplicitToneMappingWinsWhenSupported', () {
    final hdr = makeInfo(height: 2160, hdr: true);
    final result = compute(
        hdr, makePrefs(ContentMode.live, QualityTier.high, tone: 'hable'));
    expect(result.options['tone-mapping'], 'hable');
  });

  test('hdrUnsupportedToneMappingFallsBack', () {
    // "spline"/"bt.2446a" are gpu-next only in mpv 0.37 (options.rst
    // --tone-mapping): the engine must not emit them under vo=libmpv.
    final hdr = makeInfo(height: 2160, hdr: true);
    for (final requested in <String>[
      'spline',
      'bt.2446a',
      'st2094-40',
      'garbage',
    ]) {
      final result = compute(
          hdr, makePrefs(ContentMode.live, QualityTier.high, tone: requested));
      expect(result.options['tone-mapping'], 'bt.2390');
    }
  });

  test('nonHdrResetsToneMappingOptions', () {
    // SDR sources get the tone-mapping series reset on every active apply,
    // so values left by a previous HDR file cannot leak into SDR playback.
    final sdr = makeInfo();
    final result = compute(
        sdr, makePrefs(ContentMode.auto, QualityTier.high));
    expect(result.options['tone-mapping'], 'auto');
    expect(result.options['target-colorspace-hint'], false);
  });

  test('autoContentModeFollowsAnimatedHint', () {
    // Auto + animated hint resolves to an Anime4K group.
    final animeInfo = makeInfo(vfFormat: 'animated',
        shaders: fullAnime4kSet());
    final anime = compute(
        animeInfo, makePrefs(ContentMode.auto, QualityTier.high));
    expect(anime.shaders.first, contains('Anime4K'));

    // Auto without the hint falls back to the live path.
    final liveInfo =
        makeInfo(shaders: <String>['SSimSuperRes.glsl']);
    final live = compute(
        liveInfo, makePrefs(ContentMode.auto, QualityTier.high));
    expect(live.shaders, <String>['SSimSuperRes.glsl']);
  });

  test('explicitContentModeOverridesHint', () {
    const shaders = <String>[
      'SSimSuperRes.glsl',
      'Anime4K/Anime4K_Clamp_Highlights.glsl',
    ];
    // Animated hint present, but the user forces live content mode.
    final info = makeInfo(vfFormat: 'animated', shaders: shaders);
    final live = compute(
        info, makePrefs(ContentMode.live, QualityTier.high));
    expect(live.shaders, <String>['SSimSuperRes.glsl']);
    // No hint, but the user forces anime content mode.
    final plain = makeInfo(shaders: shaders);
    final anime = compute(
        plain, makePrefs(ContentMode.anime, QualityTier.high));
    expect(anime.shaders,
        <String>['Anime4K/Anime4K_Clamp_Highlights.glsl']);
  });

  test('scaleOverrideWinsWhileActive', () {
    final info = makeInfo(vfFormat: 'animated');
    final result = compute(
        info,
        makePrefs(ContentMode.auto, QualityTier.medium,
            scaleOverride: 'bilinear'));
    expect(result.options['scale'], 'bilinear');

    // Corrupted or undocumented override values fall back to the tier pick.
    final bad = makePrefs(ContentMode.auto, QualityTier.medium,
        scaleOverride: 'spline36');
    expect(
        compute(info, bad).options['scale'], 'ewa_lanczossharp');
    final garbage = makePrefs(ContentMode.auto, QualityTier.medium,
        scaleOverride: 'garbage');
    expect(compute(info, garbage).options['scale'],
        'ewa_lanczossharp');

    expect(isSupportedScale('lanczos'), isTrue);
    expect(isSupportedScale('ewa_lanczossharp'), isTrue);
    // not documented for --scale in 0.37
    expect(isSupportedScale('spline36'), isFalse);
    expect(isSupportedScale(''), isFalse);
  });

  test('debandModeOverride', () {
    // "auto" and "yes" keep the table's deband-on while active; "no" wins.
    final info = makeInfo(vfFormat: 'animated');
    final prefs =
        makePrefs(ContentMode.auto, QualityTier.high);
    expect(compute(info, prefs).options['deband'], true);

    final forcedOn = UserPrefs()
      ..contentMode = prefs.contentMode
      ..qualityTier = prefs.qualityTier
      ..toneMappingMode = prefs.toneMappingMode
      ..scaleOverride = prefs.scaleOverride
      ..debandMode = 'yes';
    expect(compute(info, forcedOn).options['deband'], true);

    final forcedOff = UserPrefs()
      ..contentMode = prefs.contentMode
      ..qualityTier = prefs.qualityTier
      ..toneMappingMode = prefs.toneMappingMode
      ..scaleOverride = prefs.scaleOverride
      ..debandMode = 'no';
    expect(compute(info, forcedOff).options['deband'], false);

    // Corrupted mode values normalize to "auto" (table decides: on).
    final corrupted = UserPrefs()
      ..contentMode = prefs.contentMode
      ..qualityTier = prefs.qualityTier
      ..toneMappingMode = prefs.toneMappingMode
      ..scaleOverride = prefs.scaleOverride
      ..debandMode = 'garbage';
    expect(compute(info, corrupted).options['deband'], true);

    // "off" tier always clears deband, whatever the override says.
    forcedOff.qualityTier = QualityTier.off;
    expect(compute(info, forcedOff).options['deband'], false);
  });

  test('hdrVideoParamsDetection', () {
    expect(isHdrVideoParams(<String, Object?>{}), isFalse);
    expect(
        isHdrVideoParams(<String, Object?>{'w': 1920, 'h': 1080}), isFalse);
    // SDR BT.709.
    expect(
        isHdrVideoParams(
            <String, Object?>{'primaries': 'bt.709', 'gamma': 'bt.1886'}),
        isFalse);
    // HDR10: BT.2020 primaries with PQ transfer.
    expect(
        isHdrVideoParams(
            <String, Object?>{'primaries': 'bt.2020', 'gamma': 'pq'}),
        isTrue);
    // HLG without BT.2020 primaries is still HDR.
    expect(isHdrVideoParams(<String, Object?>{'gamma': 'hlg'}), isTrue);
  });

  test('animatedHintHeuristic', () {
    expect(
        animatedHintFrom('[VCB-Studio] Kimi no Na wa [Ma10p_1080p]'),
        'animated');
    expect(
        animatedHintFrom('Movie.2023.1080p.BluRay.x264-GRP'), '');
    expect(animatedHintFrom(''), '');
  });

  test('enumStringRoundTrips', () {
    expect(contentModeToString(contentModeFromString('auto')), 'auto');
    expect(contentModeToString(contentModeFromString('anime')), 'anime');
    expect(contentModeToString(contentModeFromString('live')), 'live');
    expect(qualityTierToString(qualityTierFromString('off')), 'off');
    expect(qualityTierToString(qualityTierFromString('low')), 'low');
    expect(qualityTierToString(qualityTierFromString('medium')), 'medium');
    expect(qualityTierToString(qualityTierFromString('high')), 'high');
    // Unknown strings fall back to safe defaults.
    expect(contentModeToString(contentModeFromString('???')), 'auto');
    expect(qualityTierToString(qualityTierFromString('???')), 'off');
    expect(isSupportedToneMapping('bt.2390'), isTrue);
    expect(isSupportedToneMapping('spline'), isFalse);
  });
}
