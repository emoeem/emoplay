import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/plugins/plugin_git_runner.dart';
import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/plugin_manifest.dart';

// Headless PluginManager tests. All git invocations go through a synchronous
// fake (PluginGitRunner seam) — no network, no real git binary. Paths live in
// temporary directories; the real HOME is never touched.
//
// Covered here: path assembly, the scripts-merge logic (append-only, the P4
// compat layer's assembled value is preserved), the install/update/uninstall
// state machine including the replace-mode protective skip, check-mode
// semantics (comparison only), and state persistence across instances.
//
// Case-for-case port of mpv-emo tests/test_plugin_manager.cpp; assertion
// values are the behavioural contract and are copied verbatim.

class FakeGitRunner implements PluginGitRunner {
  Future<PluginGitResult> Function(List<String>, String)? handler;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<PluginGitResult> run(
      List<String> arguments, String workingDirectory) async {
    calls.add(arguments);
    if (handler != null) {
      return handler!(arguments, workingDirectory);
    }
    return const PluginGitResult(exitCode: 0, started: true);
  }

  bool sawCommand(String command) =>
      calls.any((call) => call.isNotEmpty && call.first == command);
}

// check mode with baseline / single-file destination / replace-mode
// shader pack: the three shapes the manager must tell apart.
const String kCatalogJson = '{"sources": ['
    '{"name": "uosc_danmaku",'
    ' "url": "https://git.example/uosc_danmaku.git",'
    ' "branch": "main", "source": ".",'
    ' "destination": "scripts/uosc_danmaku",'
    ' "mode": "check", "baseline": "old1"},'
    '{"name": "mpv360",'
    ' "url": "https://git.example/mpv360.git",'
    ' "branch": "master", "source": ".",'
    ' "destination": "scripts/mpv360.lua", "mode": "check"},'
    '{"name": "anime4k",'
    ' "url": "https://git.example/anime4k.git",'
    ' "branch": "master", "source": "glsl",'
    ' "destination": "shaders/Anime4K/glsl", "mode": "replace"}'
    ']}';

void writeFile(String path, String content) {
  File(path).writeAsStringSync(content);
}

Map<String, Object?> pluginEntry(PluginManager manager, String name) {
  for (final entry in manager.plugins()) {
    if (entry['name'] == name) {
      return entry;
    }
  }
  return <String, Object?>{};
}

// Creates the target directory of a clone with an entry marker file, like a
// real successful clone of a script plugin.
PluginGitResult fakeClone(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == 'clone') {
    final target = arguments.last;
    final dir = Directory(target);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('$target/main.lua').writeAsStringSync('fake\n');
  }
  return const PluginGitResult(exitCode: 0, started: true);
}

class Fixture {
  Fixture() {
    final dir = Directory.systemTemp.createTempSync('emoplay-plugins-');
    path = dir.path;
    catalogPath = '$path/catalog.json';
    writeFile(catalogPath, kCatalogJson);
    pluginsRoot = '$path/plugins';
    tempDir = dir;
  }

  late final Directory tempDir;
  late final String path;
  late final String catalogPath;
  late final String pluginsRoot;

  void dispose() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  test('scriptSeparatorMatchesMpvPathList', () {
    // mpv's --scripts is an OPT_PATHLIST (':' Unix / ';' Windows), never ','.
    final separator = PluginManager.scriptSeparator;
    if (Platform.isWindows) {
      expect(separator, ';');
    } else {
      expect(separator, ':');
    }
  });

  test('scriptEntryPathsCoverDestinationShapes', () {
    const root = '/appdata/plugins';

    // Directory destination: the content root itself — mpv loads a directory
    // entry via its "main.lua" (player/scripting.c mp_load_script).
    final dirManifest = PluginManifest.parse(<String, Object?>{
      'name': 'uosc_danmaku',
      'url': 'https://git.example/u.git',
      'destination': 'scripts/uosc_danmaku',
    });
    expect(PluginManager.scriptEntryPaths(dirManifest, root),
        ['$root/uosc_danmaku']);

    // Source subtree: the entry is <clone>/<source>.
    final subtree = <String, Object?>{
      'name': 'uosc',
      'url': 'https://git.example/u.git',
      'destination': 'scripts/uosc',
      'source': 'src/uosc',
    };
    expect(PluginManager.scriptEntryPaths(PluginManifest.parse(subtree), root),
        ['$root/uosc/src/uosc']);

    // Single-file destination (manager.json also lists these): the file
    // inside the content root.
    final fileEntry = <String, Object?>{
      'name': 'mpv360',
      'url': 'https://git.example/u.git',
      'destination': 'scripts/mpv360.lua',
    };
    expect(PluginManager.scriptEntryPaths(PluginManifest.parse(fileEntry), root),
        ['$root/mpv360/mpv360.lua']);
  });

  test('scriptEntryPathsIgnoreShaderPacks', () {
    final shaderManifest = PluginManifest.parse(<String, Object?>{
      'name': 'anime4k',
      'url': 'https://git.example/a.git',
      'destination': 'shaders/Anime4K/glsl',
    });
    expect(PluginManager.scriptEntryPaths(shaderManifest, '/p'), isEmpty);
  });

  test('mergeScriptOptionsCreatesAppendsAndProtects', () {
    const entries = <String>['/plugins/uosc_danmaku'];

    // Absent key: created.
    final options = <String, String>{};
    PluginManager.mergeScriptOptions(options, entries);
    expect(options['scripts'], entries.first);

    // Existing user value (assembled by the P4 compat layer): append only,
    // user paths keep their position.
    final withUser = <String, String>{'scripts': '/user/a.lua:/user/b.lua'};
    PluginManager.mergeScriptOptions(withUser, entries);
    expect(withUser['scripts'],
        '/user/a.lua:/user/b.lua:/plugins/uosc_danmaku');

    // Nothing to append: the map is left completely untouched (no empty
    // "scripts" value is ever created).
    final untouched = <String, String>{'other': 'x'};
    PluginManager.mergeScriptOptions(untouched, const []);
    expect(untouched.length, 1);
    expect(untouched.containsKey('scripts'), isFalse);
  });

  test('installClonesAndRecordsHead', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );

    git.handler = (arguments, workingDirectory) async {
      // rev-parse runs inside the new clone after a successful clone.
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'head0123456789\n', started: true);
      }
      return fakeClone(arguments);
    };

    var ok = false;
    String? message;
    String? action;
    manager.onOperationFinished =
        (name, finishedAction, success, finishedMessage) {
      action = finishedAction;
      ok = success;
      message = finishedMessage;
    };
    await manager.install('uosc_danmaku');

    expect(ok, isTrue);
    expect(action, 'install');
    expect(message, contains('head0123456789'));

    // Exactly one clone with depth 1, pinned branch, upstream URL.
    List<String>? clone;
    for (final call in git.calls) {
      if (call.first == 'clone') {
        clone = call;
      }
    }
    expect(clone, isNotNull);
    expect(clone, contains('--depth'));
    expect(clone, contains('1'));
    expect(clone, contains('--branch'));
    expect(clone, contains('main'));
    expect(clone, contains('https://git.example/uosc_danmaku.git'));
    expect(clone!.last, '${f.pluginsRoot}/uosc_danmaku');

    final entry = pluginEntry(manager, 'uosc_danmaku');
    expect(entry['installed'], isTrue);
    expect(entry['enabled'], isTrue);
    expect(entry['head'], 'head0123456789');
    // Installing a script plugin assembles an entry path under the plugin root.
    expect(entry['entryPath'], '${f.pluginsRoot}/uosc_danmaku');
  });

  test('installRefusedWhenAlreadyInstalled', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async => fakeClone(arguments);
    var ok = true;
    manager.onOperationFinished = (name, action, success, message) => ok = success;

    await manager.install('uosc_danmaku');
    expect(ok, isTrue);
    final callsAfterInstall = git.calls.length;

    await manager.install('uosc_danmaku');
    expect(ok, isFalse);
    expect(git.calls.length, callsAfterInstall); // no second clone
  });

  test('statePersistsAcrossInstances', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    {
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: git,
      );
      git.handler = (arguments, _) async {
        if (arguments.first == 'rev-parse') {
          return const PluginGitResult(
              exitCode: 0, standardOutput: 'abc123', started: true);
        }
        return fakeClone(arguments);
      };
      var ok = false;
      manager.onOperationFinished = (name, action, success, message) => ok = success;
      await manager.install('uosc_danmaku');
      expect(ok, isTrue);
      manager.setEnabled('uosc_danmaku', false);
    }

    // A fresh instance reloads state.json from disk.
    final reloaded = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    final entry = pluginEntry(reloaded, 'uosc_danmaku');
    expect(entry['installed'], isTrue); // directory still there
    expect(entry['enabled'], isFalse);
    expect(entry['head'], 'abc123');

    final options = <String, String>{};
    reloaded.appendScriptOptions(options);
    expect(options.containsKey('scripts'), isFalse); // disabled: nothing appended
  });

  test('appendScriptOptionsCoexistsWithUserScripts', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'abc123', started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    manager.onOperationFinished = (name, action, success, message) => ok = success;
    await manager.install('uosc_danmaku');
    expect(ok, isTrue);

    // The compat layer already assembled the user's own scripts list.
    final options = <String, String>{'scripts': '/user/config/a.lua'};
    manager.appendScriptOptions(options);

    final merged = options['scripts']!;
    expect(merged, startsWith('/user/config/a.lua'));
    expect(merged, contains(PluginManager.scriptSeparator));
    expect(merged, contains('${f.pluginsRoot}/uosc_danmaku'));

    // A shader-pack plugin (anime4k) never feeds the scripts option.
    PluginManager.mergeScriptOptions(options, const []);
    expect(options['scripts'], merged);
  });

  test('replaceUpdateSwapsAtomicallyWithBackup', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, workingDirectory) async {
      if (arguments.first == 'rev-parse') {
        final head =
            workingDirectory.contains('.staging-') ? 'newhead' : 'oldhead';
        return PluginGitResult(
            exitCode: 0, standardOutput: '$head\n', started: true);
      }
      // status --porcelain: clean tree.
      if (arguments.first == 'status') {
        return const PluginGitResult(exitCode: 0, started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };
    await manager.install('anime4k');
    expect(ok, isTrue);

    await manager.update('anime4k');
    expect(ok, isTrue);
    expect(message, contains('oldhead'));
    expect(message, contains('newhead'));

    // The staging clone was swapped into place; the old install became the
    // backup (备份先行).
    expect(File('${f.pluginsRoot}/anime4k/main.lua').existsSync(), isTrue);
    expect(
        File('${f.pluginsRoot}/.backup-anime4k/main.lua').existsSync(), isTrue);
    expect(Directory('${f.pluginsRoot}/.staging-anime4k').existsSync(), isFalse);
    expect(pluginEntry(manager, 'anime4k')['head'], 'newhead');
  });

  test('replaceUpdateRefusedOnLocalModifications', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, workingDirectory) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'oldhead\n', started: true);
      }
      if (arguments.first == 'status') {
        // Local customization: an untracked file in the plugin dir.
        final marker = '$workingDirectory/my-custom-shader.glsl';
        if (File(marker).existsSync()) {
          return const PluginGitResult(
              exitCode: 0,
              standardOutput: '?? my-custom-shader.glsl\n',
              started: true);
        }
        return const PluginGitResult(exitCode: 0, started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };
    await manager.install('anime4k');
    expect(ok, isTrue);
    File('${f.pluginsRoot}/anime4k/my-custom-shader.glsl')
        .writeAsStringSync('custom\n');

    final callsBefore = git.calls.length;
    await manager.update('anime4k');
    expect(ok, isFalse);
    // Protective skip: local customizations win (本地定制永不覆盖).
    expect(message, contains('local modifications'));
    expect(
        File('${f.pluginsRoot}/anime4k/my-custom-shader.glsl').existsSync(),
        isTrue);
    expect(Directory('${f.pluginsRoot}/.backup-anime4k').existsSync(), isFalse);
    expect(
        Directory('${f.pluginsRoot}/.staging-anime4k').existsSync(), isFalse);
    // No clone was attempted after the guard.
    expect(git.calls.length, callsBefore + 1); // only the status call
  });

  test('checkModeUpdateComparesBaselineWithoutTouchingFiles', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, workingDirectory) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'installedhead\n', started: true);
      }
      if (arguments.first == 'ls-remote') {
        return const PluginGitResult(
            exitCode: 0,
            standardOutput: 'remotehead\trefs/heads/main\n',
            started: true);
      }
      if (arguments.first == 'status') {
        return const PluginGitResult(exitCode: 0, started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };
    await manager.install('uosc_danmaku');
    expect(ok, isTrue);

    await manager.checkForUpdate('uosc_danmaku');
    expect(ok, isTrue);
    // The reference is the manifest baseline ("old1"), not the install HEAD.
    expect(message, contains('update available'));
    expect(message, contains('old1'));
    expect(message, contains('remotehead'));
    expect(pluginEntry(manager, 'uosc_danmaku')['updateAvailable'], isTrue);

    // check mode: the "update" action is the comparison itself — no clone,
    // no file changes.
    final callsBefore = git.calls.length;
    await manager.update('uosc_danmaku');
    expect(ok, isTrue);
    expect(git.calls.length, callsBefore + 2); // ls-remote + status only
    var clonesSince = 0;
    for (var i = callsBefore; i < git.calls.length; ++i) {
      if (git.calls[i].first == 'clone') {
        ++clonesSince;
      }
    }
    expect(clonesSince, 0);
    expect(Directory('${f.pluginsRoot}/uosc_danmaku').existsSync(), isTrue);
  });

  test('uninstallRemovesDirectoryAndState', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'abc123', started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    manager.onOperationFinished = (name, action, success, message) => ok = success;
    await manager.install('uosc_danmaku');
    expect(ok, isTrue);
    expect(Directory('${f.pluginsRoot}/uosc_danmaku').existsSync(), isTrue);

    await manager.uninstall('uosc_danmaku');
    expect(ok, isTrue);
    expect(Directory('${f.pluginsRoot}/uosc_danmaku').existsSync(), isFalse);

    final reloaded = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    expect(pluginEntry(reloaded, 'uosc_danmaku')['installed'], isFalse);

    // Uninstalling a not-installed plugin is refused without side effects.
    ok = true;
    await manager.uninstall('uosc_danmaku');
    expect(ok, isFalse);
  });

  test('planOperationListsChanges', () {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );

    final install = manager.planOperation('uosc_danmaku', 'install');
    expect(install.containsKey('error'), isFalse);
    final details = install['details']! as List<String>;
    expect(details, isNotEmpty);
    expect(details.any((line) => line.contains('Clone')), isTrue);

    // check-mode update plans state the comparison-only semantics.
    final update = manager.planOperation('uosc_danmaku', 'update');
    expect(
      (update['details']! as List<String>)
          .any((line) => line.contains('No local file is touched')),
      isTrue,
    );

    expect(manager.planOperation('uosc_danmaku', 'nuke').containsKey('error'),
        isTrue);
    expect(
        manager.planOperation('nope', 'install').containsKey('error'), isTrue);
  });

  test('checkAllRunsForEveryEntry', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: kCatalogJson,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'installedhead\n', started: true);
      }
      if (arguments.first == 'ls-remote') {
        return const PluginGitResult(
            exitCode: 0,
            standardOutput: 'remotehead\trefs/heads/main\n',
            started: true);
      }
      return const PluginGitResult(exitCode: 0, started: true);
    };
    var ok = false;
    var finishes = 0;
    final checked = <String>[];
    manager.onOperationFinished = (name, action, success, message) {
      ++finishes;
      ok = ok || success;
      if (action == 'check') {
        checked.add(name);
      }
    };

    await manager.checkAll();
    // One check per catalog entry (all three), each reporting a result.
    expect(finishes, 3);
    expect(ok, isTrue);
    expect(checked.length, 3);
    for (final value in manager.plugins()) {
      expect((value['remoteHead'] as String).isEmpty, isFalse);
    }
    expect(manager.busy, isFalse);
  });
}
