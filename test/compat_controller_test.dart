// Dart port of mpv-emo tests/test_compat_controller.cpp — headless tests
// for the compat decision flow. All paths are injected: the scanned config
// dir is a rebuilt fixture tree (same contents as tests/fixtures/mpv-conf,
// see mpv_profile_scanner_test.dart), settings and app data live in
// temporary directories. The real HOME is never touched.
//
// Consent invariant exercised throughout: mpv loads input.conf inside
// mpv_initialize regardless of --config (1.x v0.37考证) and auto-loads the
// config dir's scripts/ when load-scripts=yes, so without an explicit import
// decision input-conf is pinned to EmoPlay's own empty input.conf (and
// load-scripts is forced off in the player preset — asserted in
// mpv_player_properties_test.dart).
import 'dart:convert';
import 'dart:io';

import 'package:emoplay/mpv/compat/compat_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

late Directory fixtureDir;

void main() {
  setUpAll(() async {
    fixtureDir =
        await Directory.systemTemp.createTemp('emoplay_compat_fixture_');
    Future<void> write(String relativePath, String text) async {
      final file = File(p.join(fixtureDir.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(utf8.encode(text));
    }

    await write('mpv.conf', '# sample user mpv.conf (fixture)\n'
        'vo=gpu-next\n'
        'volume=80\n'
        'keep-open=yes\n'
        '\n'
        '[hq]\n'
        'scale=ewa_lanczossharp\n'
        'deband=yes\n');
    await write('input.conf', '# sample user input.conf (fixture)\n'
        'SPACE cycle pause\n'
        'RIGHT seek 30\n'
        'ctrl+s screenshot #menu: Screenshot\n');
    await write('scripts/a.lua', '-- probe script a\n'.padRight(18));
    await write('scripts/lib/b.js', '// probe script b\n'.padRight(18));
    await write('shaders/x.glsl', '//!HOOK LUMA\n'.padRight(23));
    await write('fonts/Fake.ttf', '.' * 8);
  });

  tearDownAll(() async {
    await fixtureDir.delete(recursive: true);
  });

  test('undecidedPinsOwnInputConfAndShowsPrompt', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      final options = controller.startupOptions();
      // No decision: nothing from the user config is imported, but mpv's own
      // fallback must be blocked — input-conf points at our empty file.
      expect(options['input-conf'], p.join(appData.path, 'input.conf'));
      expect(File(p.join(appData.path, 'input.conf')).existsSync(), isTrue);
      expect(options, hasLength(1));
      expect(controller.configDetected, isTrue);
      expect(controller.firstRunPromptNeeded, isTrue);
      expect(controller.sourceDir, fixtureDir.path);
      expect(controller.importFiles, isNotEmpty);
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('fullImportBuildsOptionMap', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.chooseFullImport();

      final options = controller.startupOptions();
      // Embedding-critical values.
      expect(options['vo'], 'libmpv');
      expect(options['osc'], 'no');
      expect(options['terminal'], 'no');
      // User option passes through (fixture mpv.conf: volume=80).
      expect(options['volume'], '80');
      // input.conf is loaded from the user's directory, not copied.
      expect(options['input-conf'], p.join(fixtureDir.path, 'input.conf'));
      // config-dir points at the user's dir for ~~ resolution.
      expect(options['config-dir'], fixtureDir.path);
      // Both fixture scripts are listed as a PATH list: ':' on Unix, ';' on
      // Windows (mpv options.rst "--scripts=file1.lua:file2.lua:...").
      final scripts = options['scripts']!;
      expect(scripts, contains(p.join(fixtureDir.path, 'scripts', 'a.lua')));
      expect(
          scripts, contains(p.join(fixtureDir.path, 'scripts', 'lib', 'b.js')));
      if (Platform.isWindows) {
        expect(scripts, contains(';'));
      } else {
        expect(scripts, contains(':'));
      }
      expect(scripts, isNot(contains(',')));
      // fonts-dir points at the user's fonts directory.
      expect(options['fonts-dir'], p.join(fixtureDir.path, 'fonts'));
      // Write paths are redirected into EmoPlay's app data.
      expect(
          options['watch-later-dir'], p.join(appData.path, 'watch_later'));
      expect(options['screenshot-directory'],
          p.join(appData.path, 'screenshots'));
      // Profile section [hq] from the fixture is not applied.
      expect(options.containsKey('scale'), isFalse);
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('fullImportForcesEmbeddingOptions', () async {
    // The fixture mpv.conf contains vo=gpu-next: the forced value must win.
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.chooseFullImport();

      expect(controller.startupOptions()['vo'], 'libmpv');
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('selectiveImportHonorsFileList', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.chooseSelectiveImport(['mpv.conf']);

      var options = controller.startupOptions();
      expect(options['volume'], '80');
      // input.conf was not selected: pinned to our own empty file, not the
      // user's (mpv would otherwise load it behind our back).
      expect(options['input-conf'], p.join(appData.path, 'input.conf'));
      expect(options.containsKey('scripts'), isFalse);
      expect(options.containsKey('fonts-dir'), isFalse);
      // Forced values still apply — the embedding constraints are not
      // optional.
      expect(options['vo'], 'libmpv');
      // config-dir is still set so ~~ values resolve somewhere defined.
      expect(options['config-dir'], fixtureDir.path);

      // Selecting only input.conf: no user options, but bindings load.
      controller.chooseSelectiveImport(['input.conf']);
      final inputOnly = controller.startupOptions();
      expect(inputOnly.containsKey('volume'), isFalse);
      expect(
          inputOnly['input-conf'], p.join(fixtureDir.path, 'input.conf'));
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('selectiveImportOfNothingPinsOwnInputConf', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.chooseSelectiveImport([]);
      final options = controller.startupOptions();
      expect(options['input-conf'], p.join(appData.path, 'input.conf'));
      expect(options, hasLength(1));
      expect(controller.firstRunPromptNeeded, isFalse);
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('standaloneUsesOwnInputConf', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.chooseStandalone();

      final options = controller.startupOptions();
      expect(options['input-conf'], p.join(appData.path, 'input.conf'));
      // The empty input.conf is created in EmoPlay's own app data.
      expect(File(p.join(appData.path, 'input.conf')).existsSync(), isTrue);
      // No user config leak: no config-dir, no scripts, no user options.
      expect(options, hasLength(1));
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('skipPinsOwnInputConfAndSuppressesPrompt', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      controller.startupOptions();
      controller.skipAndDontAskAgain();

      expect(controller.firstRunPromptNeeded, isFalse);
      expect(controller.configDetected, isTrue);
      // Skip still blocks mpv's silent fallback to the user's input.conf.
      final options = controller.startupOptions();
      expect(options['input-conf'], p.join(appData.path, 'input.conf'));
      expect(options, hasLength(1));
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('decisionPersistsAcrossInstances', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final settingsFile = p.join(appData.path, 'settings.json');

      final first = CompatController(
        settingsPath: settingsFile,
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      first.startupOptions();
      first.chooseFullImport();

      final controller = CompatController(
        settingsPath: settingsFile,
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      final options = controller.startupOptions();
      expect(options.length, greaterThan(1));
      expect(controller.firstRunPromptNeeded, isFalse);
      expect(options['vo'], 'libmpv');
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('missingConfigDirIsUndetected', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: '/definitely/not/a/real/mpv/dir',
      );
      controller.startupOptions();
      expect(controller.configDetected, isFalse);
      expect(controller.firstRunPromptNeeded, isFalse);
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('requestWizardTogglesProperty', () async {
    final appData =
        await Directory.systemTemp.createTemp('emoplay_compat_app_');
    try {
      final controller = CompatController(
        settingsPath: p.join(appData.path, 'settings.json'),
        appDataDir: appData.path,
        configDir: fixtureDir.path,
      );
      expect(controller.wizardRequested, isFalse);
      controller.requestWizard();
      expect(controller.wizardRequested, isTrue);
      controller.chooseStandalone();
      expect(controller.wizardRequested, isFalse);
    } finally {
      await appData.delete(recursive: true);
    }
  });
}
