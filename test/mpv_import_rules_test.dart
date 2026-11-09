// Dart port of mpv-emo tests/test_import_rules.cpp — headless tests for the
// P4 import policy: embedding-critical options are forced, write paths are
// redirected out of the user's mpv directory, and everything else passes
// through. Assertion values copied verbatim.
import 'dart:io';

import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/mpv/config/mpv_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<MpvConfEntry> _parse(String text) => MpvConfigParser.parseMpvConf(text);

void main() {
  late Directory appData;

  setUp(() async {
    // 1.x QTemporaryDir: a fresh app-data directory per test.
    appData = await Directory.systemTemp.createTemp('emoplay_rules_');
  });

  tearDown(() async {
    await appData.delete(recursive: true);
  });

  test('forcedKeysAlwaysWin', () {
    final result = MpvImportRules.apply(
      _parse('vo=gpu-next\nosc=yes\nterminal=yes\nvolume=80\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options['vo'], 'libmpv');
    expect(result.options['osc'], 'no');
    expect(result.options['terminal'], 'no');
    // Untouched option survives.
    expect(result.options['volume'], '80');
    // All three replacements are audited.
    expect(result.forced, hasLength(3));
    expect(result.forced.first, startsWith("vo: user value 'gpu-next'"));
  });

  test('userOptionsPassThrough', () {
    final result = MpvImportRules.apply(
      _parse('hwdec=auto-copy\nkeep-open=yes\nvolume=65\nslang=chs,eng\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options['hwdec'], 'auto-copy');
    expect(result.options['keep-open'], 'yes');
    expect(result.options['volume'], '65');
    expect(result.options['slang'], 'chs,eng');
    expect(result.forced, isEmpty);
    expect(result.profileNames, isEmpty);
  });

  test('lastOccurrenceWins', () {
    final result = MpvImportRules.apply(
      _parse('volume=80\nvolume=90\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options['volume'], '90');
  });

  test('profileSectionsSkippedAndReported', () {
    final result = MpvImportRules.apply(
      _parse('volume=50\n[hq]\nscale=ewa_lanczossharp\ndeband=yes\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    // Top-level option kept; profile options dropped, profile reported.
    expect(result.options['volume'], '50');
    expect(result.options.containsKey('scale'), isFalse);
    expect(result.options.containsKey('deband'), isFalse);
    expect(result.profileNames, ['hq']);
    expect(result.skipped.first, contains('[hq]'));
  });

  test('profileReferencesSkipped', () {
    final result = MpvImportRules.apply(
      _parse('profile=Target\nprofile=Dither\nvolume=50\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options.containsKey('profile'), isFalse);
    expect(result.skipped, hasLength(2));
    expect(result.skipped.first, startsWith('profile:'));
    // Options after a profile reference still apply (not inside a section).
    expect(result.options['volume'], '50');
  });

  test('includeAndDumpOptionsStripped', () {
    final result = MpvImportRules.apply(
      _parse('include=extra.conf\nlog-file=~~/mpv.log\ndump-stats=stats.bin\nvolume=50\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options.containsKey('include'), isFalse);
    expect(result.options.containsKey('log-file'), isFalse);
    expect(result.options.containsKey('dump-stats'), isFalse);
    expect(result.skipped, hasLength(3));
  });

  test('writePathsRedirectedToAppData', () {
    final result = MpvImportRules.apply(
      _parse('watch-later-dir=~~/cache/watch_later\nvolume=50\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    // The five write paths always point into EmoPlay's app data.
    expect(result.options['watch-later-dir'], '${appData.path}/watch_later');
    expect(result.options['screenshot-directory'], '${appData.path}/screenshots');
    expect(result.options['gpu-shader-cache-dir'], '${appData.path}/shader_cache');
    expect(result.options['icc-cache-dir'], '${appData.path}/icc_cache');
    expect(result.options['demuxer-cache-dir'], '${appData.path}/demuxer_cache');
    expect(result.redirected, hasLength(5));
  });

  test('configRelativeScreenshotTemplateStripped', () {
    final result = MpvImportRules.apply(
      _parse('screenshot-template=~~/files/screen/%n\nvolume=50\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options.containsKey('screenshot-template'), isFalse);
    expect(result.skipped.first, startsWith('screenshot-template:'));
  });

  test('plainScreenshotTemplateKept', () {
    final result = MpvImportRules.apply(
      _parse('screenshot-template=%F-%n\nvolume=50\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options['screenshot-template'], '%F-%n');
  });

  test('configRelativeShaderValuesKept', () {
    // ~~ values are read paths: they must survive so the engine side can
    // resolve them against the user's config dir (no file copying).
    final result = MpvImportRules.apply(
      _parse(
          'glsl-shaders=~~/shaders/Anime4K/glsl/x.glsl\nicc-profile=~~/icc/display.icc\n'),
      '/home/user/.config/mpv',
      appData.path,
    );

    expect(result.options['glsl-shaders'], '~~/shaders/Anime4K/glsl/x.glsl');
    expect(result.options['icc-profile'], '~~/icc/display.icc');
  });

  test('forcedAndStrippedKeyLists', () {
    final forced = MpvImportRules.forcedKeys;
    expect(forced, hasLength(3));
    expect(forced, contains('vo'));
    expect(forced, contains('osc'));
    expect(forced, contains('terminal'));

    final stripped = MpvImportRules.strippedKeys;
    expect(stripped, contains('include'));
    expect(stripped, contains('profile'));
    expect(stripped, contains('watch-later-dir'));
    // Forced keys are not stripped keys: they are replaced, not removed.
    for (final key in forced) {
      expect(stripped, isNot(contains(key)));
    }
  });

  test('redirectTargetSharesTheStartupTable', () {
    // The runtime layers (ICC controller) reuse the same redirect table as
    // the startup pass, so both always agree on sub-directory names.
    // The ICC cache is a write path: redirected to app data.
    expect(MpvImportRules.redirectTarget('icc-cache-dir', appData.path),
        '${appData.path}/icc_cache');
    // The other write paths agree with the startup redirects.
    expect(MpvImportRules.redirectTarget('watch-later-dir', appData.path),
        '${appData.path}/watch_later');
    expect(MpvImportRules.redirectTarget('demuxer-cache-dir', appData.path),
        '${appData.path}/demuxer_cache');

    // Read paths (icc-profile keeps its user value, see
    // configRelativeShaderValuesKept) and unknown keys are not targets.
    expect(MpvImportRules.redirectTarget('icc-profile', appData.path), isEmpty);
    expect(MpvImportRules.redirectTarget('volume', appData.path), isEmpty);
  });
}
