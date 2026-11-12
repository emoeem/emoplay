import 'dart:convert';
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
// M6-T3 adds an independent anti-traversal fuzz section (group below): a
// hostile-destination corpus driven through the manifest parse gate and the
// manager pipeline, real-filesystem symlink cases, and the operations
// allow-list (default-deny) contract.
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

// M6-T3 fuzz corpus — hostile manifest destinations (路径穿越/绝对路径/
// 反斜杠/'..' 混合). Every entry must be rejected by PluginManifest.parse
// with the unsafe-destination error before it can reach any manager state.
// Each pair is (destination, human-readable class label for failure reasons).
const List<(String, String)> kHostileDestinations = <(String, String)>[
  ('../escape.lua', 'leading .. traversal'),
  ('scripts/../../escape.lua', 'prefixed .. traversal'),
  ('scripts/a/../../../../../../etc/passwd', 'deep .. chain'),
  ('scripts/../..', 'trailing .. mix'),
  ('scripts//../../escape.lua', 'empty segment + .. mix'),
  ('./scripts/../escape.lua', 'dot + .. mix'),
  ('....//....//escape.lua', 'dot-run + empty segment mix'),
  ('scripts/uosc/', 'trailing slash segment'),
  ('/etc/mpv/scripts', 'absolute unix path'),
  ('C:\\apps\\mpv\\scripts', 'windows drive-absolute path'),
  ('\\windows\\scripts', 'backslash-rooted absolute path'),
  ('scripts\\..\\..\\escape.lua', 'backslash traversal mix'),
];

// M6-T3 fuzz corpus — destinations that PASS the parse gate: look-alike
// segments which are not '..', not separators and not backslashes. They are
// ordinary (if odd) file names, so parse accepts them — but any entry path
// derived from them must still stay inside the content root.
const List<String> kLookalikeDestinations = <String>[
  'scripts/..%2f..%2fescape.lua', // percent-encoded separators are literal characters
  'scripts/foo../bar...lua', // dot-run segments are ordinary names
  'scripts/ .lua', // whitespace stem
  'scripts/插件.lua', // unicode stem
];

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

  // ---- M6-T1: the asset-integrity checkpoint sits at the front of the
  // install chain — an incomplete size+hash pair refuses BEFORE any git
  // command, and a pinned manifest has the cloned content verified before
  // the install is recorded (or the replace swap touches anything).

  test('installRefusedBeforeAnyGitWhenIntegrityIncomplete', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final git = FakeGitRunner();
    // 缺一拒装: the entry pins only the hash — the install must refuse
    // without a single git invocation.
    const catalog = '{"sources": ['
        '{"name": "pinned",'
        ' "url": "https://git.example/pinned.git",'
        ' "destination": "scripts/pinned",'
        ' "sha256": '
        '"a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"}'
        ']}';
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: catalog,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    var ok = true;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };

    await manager.install('pinned');
    expect(ok, isFalse);
    expect(message, contains('without sizeBytes'));
    expect(git.calls, isEmpty); // the checkpoint is in front of every git step
  });

  test('installWithPinnedContentVerifiesAfterClone', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    // Seed an identical tree to compute the pin for (fakeClone writes
    // exactly {main.lua: "fake\n"} into the clone target).
    final seed = await Directory.systemTemp.createTemp('emoplay-pin-');
    addTearDown(() {
      try {
        seed.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${seed.path}/main.lua').writeAsStringSync('fake\n');
    final digest = await PluginContentIntegrity.compute(seed.path);
    expect(digest, isNotNull);

    final catalog = '{"sources": ['
        '{"name": "pinned",'
        ' "url": "https://git.example/pinned.git",'
        ' "destination": "scripts/pinned",'
        ' "sizeBytes": ${digest!.sizeBytes},'
        ' "sha256": "${digest.sha256}"}'
        ']}';
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: catalog,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async {
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'head0123456789\n', started: true);
      }
      return fakeClone(arguments);
    };
    var ok = false;
    manager.onOperationFinished = (name, action, success, message) =>
        ok = success;

    await manager.install('pinned');
    expect(ok, isTrue); // matching content passes the post-clone gate
    final entry = pluginEntry(manager, 'pinned');
    expect(entry['installed'], isTrue);
    expect(entry['head'], 'head0123456789');
    expect(entry['sha256'], digest.sha256);
    expect(entry['sizeBytes'], digest.sizeBytes);
  });

  test('installWithTamperedContentRefusedAndCleaned', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final seed = await Directory.systemTemp.createTemp('emoplay-pin-');
    addTearDown(() {
      try {
        seed.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${seed.path}/main.lua').writeAsStringSync('fake\n');
    final digest = await PluginContentIntegrity.compute(seed.path);

    final catalog = '{"sources": ['
        '{"name": "pinned",'
        ' "url": "https://git.example/pinned.git",'
        ' "destination": "scripts/pinned",'
        ' "sizeBytes": ${digest!.sizeBytes},'
        ' "sha256": "${digest.sha256}"}'
        ']}';
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: catalog,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, _) async {
      if (arguments.first == 'clone') {
        // Upstream content drifts from the pin.
        final target = arguments.last;
        Directory(target).createSync(recursive: true);
        File('$target/main.lua').writeAsStringSync('tampered\n');
        return const PluginGitResult(exitCode: 0, started: true);
      }
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0, standardOutput: 'head0123456789\n', started: true);
      }
      return const PluginGitResult(exitCode: 0, started: true);
    };
    var ok = true;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };

    await manager.install('pinned');
    expect(ok, isFalse);
    // hash 不符拒绝: the refusal names the integrity failure.
    expect(message, contains('content integrity check failed'));
    // The unverified clone is removed — no half-installed plugin lingers.
    expect(Directory('${f.pluginsRoot}/pinned').existsSync(), isFalse);
    final entry = pluginEntry(manager, 'pinned');
    expect(entry['installed'], isFalse);
    expect(entry['enabled'], isFalse);
  });

  test('replaceUpdateVerifiesStagedContentBeforeSwap', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final seed = await Directory.systemTemp.createTemp('emoplay-pin-');
    addTearDown(() {
      try {
        seed.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${seed.path}/main.lua').writeAsStringSync('fake\n');
    final digest = await PluginContentIntegrity.compute(seed.path);

    final catalog = '{"sources": ['
        '{"name": "pinned_replace",'
        ' "url": "https://git.example/pinned_replace.git",'
        ' "source": ".",'
        ' "destination": "shaders/pinned_replace", "mode": "replace",'
        ' "sizeBytes": ${digest!.sizeBytes},'
        ' "sha256": "${digest.sha256}"}'
        ']}';
    final git = FakeGitRunner();
    final manager = PluginManager(
      appDataDir: f.path,
      catalogJson: catalog,
      catalogPath: f.catalogPath,
      gitRunner: git,
    );
    git.handler = (arguments, workingDirectory) async {
      if (arguments.first == 'clone') {
        final result = fakeClone(arguments);
        if (arguments.last.contains('.staging-')) {
          // Upstream drift: the staged content no longer matches the pin.
          File('${arguments.last}/main.lua').writeAsStringSync('drifted\n');
        }
        return result;
      }
      if (arguments.first == 'rev-parse') {
        final head =
            workingDirectory.contains('.staging-') ? 'newhead' : 'oldhead';
        return PluginGitResult(
            exitCode: 0, standardOutput: '$head\n', started: true);
      }
      if (arguments.first == 'status') {
        return const PluginGitResult(exitCode: 0, started: true);
      }
      return const PluginGitResult(exitCode: 0, started: true);
    };
    var ok = false;
    String? message;
    manager.onOperationFinished =
        (name, action, success, finishedMessage) {
      ok = success;
      message = finishedMessage;
    };

    await manager.install('pinned_replace');
    expect(ok, isTrue); // the install matches the pin

    await manager.update('pinned_replace');
    // The drifted staging content is refused BEFORE the swap: the old
    // install stays untouched, no backup was made, no staging remains.
    expect(ok, isFalse);
    expect(message, contains('content integrity check failed'));
    expect(
        File('${f.pluginsRoot}/pinned_replace/main.lua').readAsStringSync(),
        'fake\n');
    expect(pluginEntry(manager, 'pinned_replace')['head'], 'oldhead');
    expect(
        Directory('${f.pluginsRoot}/.backup-pinned_replace').existsSync(),
        isFalse);
    expect(
        Directory('${f.pluginsRoot}/.staging-pinned_replace').existsSync(),
        isFalse);
  });

  // ---- M6-T3: attack-surface reduction fuzz (roadmap §五 M6-T3) -------------
  //
  // Every manifest destination crosses exactly one funnel: PluginManifest
  // .parse → isSafeRelativePath (plugin_manifest.dart). Both the builtin
  // catalog and RemoteManifestSource ingest manifests only through
  // PluginManifest.parseList, so a destination rejected at parse can never
  // reach a manager. The fuzz batches pin that end to end:
  //   1. the hostile corpus is rejected at parse (traversal/absolute/
  //      backslash/'..' mixes),
  //   2. a hostile destination never enters a manager — the catalog fails
  //      closed, the plugin is unknown, zero git calls happen,
  //   3. a destination that DOES pass parse (look-alike segments) can only
  //      ever produce entry paths inside the content root,
  //   4. symlink classes: an install target that is a symlink to outside the
  //      plugins root is refused untouched, and symlinks inside cloned
  //      content never contribute to the integrity digest.

  group('M6-T3 destination anti-traversal fuzz', () {
    test('fuzzHostileDestinationsRejectedAtParse', () {
      // The corpus itself is the contract: batch coverage, ≥10 cases.
      expect(kHostileDestinations.length, greaterThanOrEqualTo(10));
      for (final (destination, why) in kHostileDestinations) {
        final manifest = PluginManifest.parse(<String, Object?>{
          'name': 'evil',
          'url': 'https://git.example/evil.git',
          'destination': destination,
        });
        expect(manifest.valid, isFalse,
            reason: '[$why] "$destination" must be rejected at parse');
        expect(manifest.error, contains('unsafe destination path'),
            reason: '[$why] "$destination"');
        // The rejected manifest carries no usable fields: nothing may leak
        // past the gate half-initialised.
        expect(manifest.name, isEmpty, reason: '[$why] "$destination"');
        // The gate helper agrees with parse, checked on the same corpus.
        expect(PluginManifest.isSafeRelativePath(destination), isFalse,
            reason: '[$why] "$destination"');
      }
    });

    test('fuzzHostileDestinationNeverReachesTheManager', () async {
      final f = Fixture();
      addTearDown(f.dispose);
      final git = FakeGitRunner();
      final errors = <String>[];

      for (final (destination, why) in kHostileDestinations) {
        // jsonEncode keeps the hostile bytes exact (backslashes included).
        final catalog = jsonEncode(<String, Object?>{
          'sources': <Object?>[
            <String, Object?>{
              'name': 'evil',
              'url': 'https://git.example/evil.git',
              'destination': destination,
            },
          ],
        });
        final manager = PluginManager(
          appDataDir: f.path,
          catalogJson: catalog,
          catalogPath: f.catalogPath,
          gitRunner: git,
          onError: errors.add,
        );

        // Fail closed: the whole catalog is dropped, nothing is ingested.
        expect(manager.allManifests(), isEmpty,
            reason: '[$why] "$destination" must not enter the manager');
        expect(errors.last, contains('cannot read plugin catalog'),
            reason: '[$why] "$destination"');
        expect(manager.planOperation('evil', 'install')['error'],
            'unknown plugin "evil"',
            reason: '[$why] "$destination"');
        expect(manager.isInstalled('evil'), isFalse,
            reason: '[$why] "$destination"');
        expect(Directory('${f.pluginsRoot}/evil').existsSync(), isFalse,
            reason: '[$why] "$destination"');
      }
      // Not a single git command ran for the whole hostile corpus.
      expect(git.calls, isEmpty);
    });

    test('fuzzLookalikeDestinationsStayInsideContentRoot', () {
      const root = '/appdata/plugins';
      const pluginDir = '$root/lookalike';
      for (final destination in kLookalikeDestinations) {
        final manifest = PluginManifest.parse(<String, Object?>{
          'name': 'lookalike',
          'url': 'https://git.example/ok.git',
          'destination': destination,
        });
        expect(manifest.valid, isTrue,
            reason: '"$destination" is not a traversal and passes the gate');
        final entries = PluginManager.scriptEntryPaths(manifest, root);
        expect(entries, isNotEmpty, reason: '"$destination"');
        for (final entry in entries) {
          // Segment-wise containment: no '..'/'.' escape segment, no
          // backslash — '..%2f' is a literal name, not a separator.
          for (final segment in entry.split('/')) {
            expect(segment, isNot('..'),
                reason: '"$destination" → "$entry" must not contain ".."');
            expect(segment, isNot('.'),
                reason: '"$destination" → "$entry" must not contain "."');
            expect(segment.contains('\\'), isFalse,
                reason: '"$destination" → "$entry" must not contain "\\"');
          }
          // And the entry never leaves the content root: either it IS the
          // content root (directory destination) or a child of it.
          final contentRoot = manifest.contentRoot(pluginDir);
          expect(
              entry == contentRoot || entry.startsWith('$contentRoot/'),
              isTrue,
              reason:
                  '"$destination" → "$entry" escapes content root $contentRoot');
        }
      }
    });

    test('fuzzSymlinkedInstallTargetRefusedAndUntouched', () async {
      final f = Fixture();
      addTearDown(f.dispose);
      // The victim lives OUTSIDE the plugins root; a symlink is planted
      // exactly where 'uosc_danmaku' would clone. Cloning through the link
      // would write outside the plugins root — the install must refuse.
      final victim = Directory('${f.path}/victim-outside');
      victim.createSync();
      File('${victim.path}/keepme.lua').writeAsStringSync('victim\n');
      final link = Link('${f.pluginsRoot}/uosc_danmaku');
      try {
        link.createSync(victim.path);
      } catch (_) {
        // Filesystem without symlink support: this class cannot be
        // exercised here; the remaining fuzz classes still ran.
        return;
      }

      final git = FakeGitRunner();
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: git,
      );
      var ok = true;
      String? message;
      manager.onOperationFinished = (name, action, success, finishedMessage) {
        ok = success;
        message = finishedMessage;
      };

      await manager.install('uosc_danmaku');

      // Refused BEFORE any git call: the planted symlink counts as an
      // existing install, so nothing is cloned through it.
      expect(ok, isFalse);
      expect(message, contains('already installed'));
      expect(git.calls, isEmpty);
      // The outside victim is untouched and the link itself was not consumed.
      expect(File('${victim.path}/keepme.lua').readAsStringSync(), 'victim\n');
      expect(link.existsSync(), isTrue);
    });

    test('fuzzIntegrityDigestIgnoresSymlinksPointingOutside', () async {
      // Tree A: plain content. Tree B: identical content plus a symlink that
      // points OUTSIDE its tree. The M6-T1 digest must be identical — links
      // are skipped, not followed — so a shipped symlink can neither smuggle
      // bytes into the pin nor make the pin depend on outside targets.
      final base =
          await Directory.systemTemp.createTemp('emoplay-fuzz-links-');
      addTearDown(() {
        try {
          base.deleteSync(recursive: true);
        } catch (_) {}
      });
      final treeA = Directory('${base.path}/a')..createSync();
      final treeB = Directory('${base.path}/b')..createSync();
      File('${treeA.path}/main.lua').writeAsStringSync('fake\n');
      File('${treeB.path}/main.lua').writeAsStringSync('fake\n');
      final outside = File('${base.path}/outside-secret.txt');
      outside.writeAsStringSync('big outside payload\n');
      final link = Link('${treeB.path}/link');
      try {
        link.createSync(outside.path);
      } catch (_) {
        return; // no symlink support on this filesystem
      }

      final plain = await PluginContentIntegrity.compute(treeA.path);
      final withLink = await PluginContentIntegrity.compute(treeB.path);
      expect(plain, isNotNull);
      expect(withLink, isNotNull);
      expect(withLink!.sha256, plain!.sha256,
          reason: 'an outside-pointing symlink must not change the digest');
      expect(withLink.sizeBytes, plain.sizeBytes,
          reason: 'an outside-pointing symlink must not change the size');
      // The link target itself was never read into the digest input.
      expect(outside.readAsStringSync(), 'big outside payload\n');
    });

    test('operationsWhitelistExplicitAndDefaultDeny', () {
      final f = Fixture();
      addTearDown(f.dispose);
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: FakeGitRunner(),
      );

      // The allow-list is a constant, exactly the four operations the
      // executor methods implement.
      expect(PluginManager.allowedOperations,
          unorderedEquals(<String>['install', 'uninstall', 'update', 'check']));
      for (final action in PluginManager.allowedOperations) {
        expect(PluginManager.isAllowedOperation(action), isTrue);
        expect(
            manager.planOperation('uosc_danmaku', action).containsKey('error'),
            isFalse,
            reason: 'whitelisted "$action" must plan cleanly');
      }

      // Default-deny: anything outside the list is refused — casing and
      // whitespace variants included — with the stable unknown-action error.
      const hostileActions = <String>[
        'nuke',
        'INSTALL',
        'Install',
        ' install',
        'install ',
        '',
        'uninstallall',
        'delete',
        'rm -rf /',
      ];
      for (final action in hostileActions) {
        expect(PluginManager.isAllowedOperation(action), isFalse,
            reason: '"$action" must be denied by default');
        final plan = manager.planOperation('uosc_danmaku', action);
        expect(plan['error'], 'unknown action "$action"',
            reason: '"$action"');
        expect(plan.containsKey('details'), isFalse,
            reason: '"$action" must not produce a change list');
      }
    });
  });
}
