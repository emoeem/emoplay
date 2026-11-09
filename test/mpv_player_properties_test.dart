// Tests for the media_kit integration preset (MpvPlayerProperties.build):
// the pure-logic half of the 1.x MpvEngine::initialize default table + the
// PluginManager::mergeScriptOptions append semantics. The apply() half needs
// a live libmpv and is exercised by the real player bootstrap, not here.
import 'dart:io';

import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory appData;

  setUp(() async {
    appData = await Directory.systemTemp.createTemp('emoplay_props_');
  });

  tearDown(() async {
    await appData.delete(recursive: true);
  });

  test('presetCarriesEngineDefaultsAndRedirects', () {
    final properties = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
    );

    // load-scripts forced off (1.x MpvEngine::initialize; see the module
    // header for the media_kit init-time-only caveat and the probe results).
    expect(properties['load-scripts'], 'no');
    // All five write paths land in EmoPlay's app data, from the same table
    // the import pass uses (redirectTargetSharesTheStartupTable).
    final redirects = MpvImportRules.redirectTargetsFor(appData.path);
    expect(redirects, hasLength(5));
    redirects.forEach((key, value) {
      expect(properties[key], value);
    });
    expect(properties['watch-later-dir'], '${appData.path}/watch_later');
    expect(properties['screenshot-directory'], '${appData.path}/screenshots');
    expect(properties['gpu-shader-cache-dir'], '${appData.path}/shader_cache');
    expect(properties['icc-cache-dir'], '${appData.path}/icc_cache');
    expect(properties['demuxer-cache-dir'], '${appData.path}/demuxer_cache');
  });

  test('compatOptionsOverridePresetDefaults', () {
    // CompatController.startupOptions() pins input-conf to EmoPlay's own
    // empty file; an imported input.conf replaces it. The preset must let
    // compat options win over the defaults.
    final properties = MpvPlayerProperties.build(
      compatOptions: {
        'input-conf': '/user/mpv/input.conf',
        'volume': '80',
      },
      appDataDir: appData.path,
    );

    expect(properties['input-conf'], '/user/mpv/input.conf');
    expect(properties['volume'], '80');
    // Redirects survive (the import rules redirect them to the same table
    // values; compat values win but are identical here).
    expect(properties['watch-later-dir'], '${appData.path}/watch_later');
  });

  test('pluginScriptsAppendWithoutReplacingImportedScripts', () {
    // 1.x PluginManager::mergeScriptOptions: append-only; the user's
    // imported script list keeps its position; no empty "scripts" value is
    // ever created.
    final separator = Platform.isWindows ? ';' : ':';

    final merged = MpvPlayerProperties.build(
      compatOptions: const {'scripts': '/user/mpv/scripts/a.lua'},
      appDataDir: appData.path,
      pluginScripts: const ['/plugins/uosc/uosc.lua', '/plugins/anime4k.lua'],
    );
    expect(merged['scripts'],
        '/user/mpv/scripts/a.lua$separator/plugins/uosc/uosc.lua$separator/plugins/anime4k.lua');

    final created = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
      pluginScripts: const ['/plugins/uosc/uosc.lua'],
    );
    expect(created['scripts'], '/plugins/uosc/uosc.lua');

    final untouched = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
      pluginScripts: const [],
    );
    expect(untouched.containsKey('scripts'), isFalse);
  });
}
