import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/plugins/plugin_git_runner.dart';
import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/plugin_manifest.dart';
import 'package:emoplay/plugins/remote_manifest_source.dart';

// Headless RemoteManifestSource tests. All fetches go through a synchronous
// fake (PluginRemoteFetcher seam) — no network, no real HTTP. The
// PluginManager interaction uses the PluginGitRunner fake from the P8 v1
// tests — no git. Paths live in temporary directories; the real HOME is
// never touched.
//
// Covered here: the default source URL, remote JSON parsing of the fixture
// (a manager.json-style document), the pure local+remote merge, cross-source
// name dedupe (first source wins), the AppData/plugin-sources cache round
// trip (offline instances serve the cached list), graceful degradation on
// fetch failure and malformed bodies, custom-source persistence, and the
// PluginManager integration (remote manifests install/update/enable like
// builtin ones and land in appendScriptOptions).
//
// Case-for-case port of mpv-emo tests/test_remote_manifest_source.cpp;
// assertion values are the behavioural contract and are copied verbatim.

class FakeFetcher implements PluginRemoteFetcher {
  final List<Uri> requested = <Uri>[];
  final List<Uri> _pending = <Uri>[];

  @override
  void Function(Uri url, PluginRemoteFetchResult result)? onFinished;

  @override
  void fetch(Uri url) {
    requested.add(url);
    _pending.add(url);
  }

  // Test drives completion: answers the oldest outstanding fetch.
  void completeNext(bool success, {String body = '', String error = ''}) {
    final url = _pending.removeAt(0);
    onFinished!(
      url,
      PluginRemoteFetchResult(
        success: success,
        body: body,
        error: error,
        httpStatus: success ? 200 : 0,
      ),
    );
  }
}

class FakeGitRunner implements PluginGitRunner {
  Future<PluginGitResult> Function(List<String>, String)? handler;

  @override
  Future<PluginGitResult> run(
      List<String> arguments, String workingDirectory) async {
    if (handler != null) {
      return handler!(arguments, workingDirectory);
    }
    return const PluginGitResult(exitCode: 0, started: true);
  }
}

const String kLocalCatalogJson = '{"sources": ['
    '{"name": "uosc",'
    ' "url": "https://git.example/uosc.git",'
    ' "branch": "main", "source": ".",'
    ' "destination": "scripts/uosc",'
    ' "mode": "check", "baseline": "5.13.0"}'
    ']}';

const String kSecondSourceJson = '{"sources": ['
    '{"name": "mpv360",'
    ' "url": "https://other.example/mpv360.git",'
    ' "branch": "main", "source": ".",'
    ' "destination": "scripts/mpv360", "mode": "check"},'
    '{"name": "extra",'
    ' "url": "https://other.example/extra.git",'
    ' "branch": "main", "source": ".",'
    ' "destination": "scripts/extra", "mode": "check"}'
    ']}';

String fixtureBytes() =>
    File('test/fixtures/remote_manager.json').readAsStringSync();

Map<String, Object?> sourceRowNamed(
    List<Map<String, Object?>> rows, String url) {
  for (final row in rows) {
    if (row['url'] == url) {
      return row;
    }
  }
  return <String, Object?>{};
}

Map<String, Object?> pluginEntry(PluginManager manager, String name) {
  for (final value in manager.plugins()) {
    if (value['name'] == name) {
      return value;
    }
  }
  return <String, Object?>{};
}

class TempTree {
  TempTree() {
    dir = Directory.systemTemp.createTempSync('emoplay-plugin-sources-');
  }

  late final Directory dir;

  String get path => dir.path;

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  test('defaultSourceIsTheUpstreamManagerJson', () {
    expect(RemoteManifestSource.defaultSourceUrl(),
        'https://raw.githubusercontent.com/emoeem/mpv/main/manager.json');
  });

  test('parsesRemoteFixtureIntoEntries', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);

    // Exactly one source out of the box: the default upstream manifest.
    expect(source.sources.length, 1);
    final defaultRow = source.sources.first;
    expect(defaultRow['isDefault'], isTrue);
    expect(defaultRow['url'], RemoteManifestSource.defaultSourceUrl());
    expect(defaultRow['lastRefreshMs'], 0);
    expect(source.refreshing, isFalse);

    source.refreshAll();
    expect(source.refreshing, isTrue);
    expect(fetcher.requested.length, 1);
    expect(fetcher.requested.first, Uri.parse(RemoteManifestSource.defaultSourceUrl()));
    fetcher.completeNext(true, body: fixtureBytes());

    expect(source.refreshing, isFalse);
    expect(source.entries.length, 3);

    final first = source.entries.first;
    expect(first['name'], 'uosc');
    expect(first['url'], 'https://git.example/uosc_danmaku.git');
    expect(first['branch'], 'main');
    expect(first['destination'], 'scripts/uosc_danmaku');
    expect(first['mode'], 'check');
    expect(first['baseline'], 'd8c1cd8');
    expect(first['isScript'], isTrue);
    // Merged against no local state: everything shows "not installed".
    expect(first['installed'], isFalse);
    expect(first['enabled'], isFalse);

    final shader = source.entries[2];
    expect(shader['name'], 'remote_shader_pack');
    expect(shader['isScript'], isFalse);
    expect(shader['mode'], 'replace');

    final row = source.sources.first;
    expect(row['lastRefreshMs'] as int > 0, isTrue);
  });

  test('mergeCatalogCopiesLocalState', () {
    final manifests = PluginManifest.parseList(fixtureBytes());
    expect(manifests.length, 3);

    final local = <Map<String, Object?>>[
      <String, Object?>{
        'name': 'uosc',
        'installed': true,
        'enabled': true,
        'head': 'deadbeef0001',
        'updateAvailable': true,
        'locallyModified': false,
      },
    ];

    final merged = RemoteManifestSource.mergeCatalog(manifests, local);
    expect(merged.length, 3);

    // Local state copied onto the remote entry; the manifest fields keep
    // their REMOTE values (the drawer shows where an update would come from).
    final mergedUosc = merged[0];
    expect(mergedUosc['installed'], isTrue);
    expect(mergedUosc['enabled'], isTrue);
    expect(mergedUosc['head'], 'deadbeef0001');
    expect(mergedUosc['updateAvailable'], isTrue);
    expect(mergedUosc['url'], 'https://git.example/uosc_danmaku.git');

    final shader = merged[2];
    expect(shader['installed'], isFalse);
    expect(shader['enabled'], isFalse);
    expect(shader['head'], '');
  });

  test('mergeCatalogDedupesByNameFirstWins', () {
    final manifests = PluginManifest.parseList(fixtureBytes());
    // A second occurrence of the same name (as two sources can carry one):
    // the first occurrence must win.
    final duplicate = PluginManifest(
      name: manifests.first.name,
      url: 'https://other.example/uosc.git',
      branch: manifests.first.branch,
      source: manifests.first.source,
      destination: manifests.first.destination,
      mode: manifests.first.mode,
      baseline: manifests.first.baseline,
      valid: true,
    );
    manifests.add(duplicate);

    final merged = RemoteManifestSource.mergeCatalog(manifests, const []);
    expect(merged.length, 3);
    expect(merged[0]['url'], 'https://git.example/uosc_danmaku.git');
  });

  test('mergeUsesLivePluginManagerState', () async {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final catalogPath = '${tree.path}/catalog.json';
    File(catalogPath).writeAsStringSync(kLocalCatalogJson);

    final git = FakeGitRunner();
    git.handler = (arguments, _) async {
      if (arguments.first == 'clone') {
        // Create the target directory with an entry marker, like a real
        // successful clone of a script plugin.
        final target = arguments.last;
        Directory(target).createSync(recursive: true);
        File('$target/main.lua').writeAsStringSync('fake\n');
      }
      if (arguments.first == 'rev-parse') {
        return const PluginGitResult(
            exitCode: 0,
            standardOutput: 'deadbeef00000000000000000000000000000001',
            started: true);
      }
      return const PluginGitResult(exitCode: 0, started: true);
    };
    final manager = PluginManager(
      appDataDir: tree.path,
      catalogJson: kLocalCatalogJson,
      catalogPath: catalogPath,
      gitRunner: git,
    );
    var ok = false;
    manager.onOperationFinished = (name, action, success, message) => ok = success;

    // A builtin install before any fetch: the merge must see it live.
    await manager.install('uosc');
    expect(ok, isTrue);

    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(
      appDataDir: tree.path,
      manager: manager,
      fetcher: fetcher,
    );
    source.refreshAll();
    fetcher.completeNext(true, body: fixtureBytes());

    // plugins() now shows the builtin AND the remote catalog, builtin first;
    // the "uosc" name collision resolves to the builtin entry.
    expect(manager.plugins().length, 3);
    expect(pluginEntry(manager, 'uosc')['url'], 'https://git.example/uosc.git');
    expect(pluginEntry(manager, 'mpv360'), isNotEmpty);
    expect(pluginEntry(manager, 'remote_shader_pack'), isNotEmpty);

    // The merged remote rows mirror the live local state.
    final remoteUosc = source.entries[0];
    expect(remoteUosc['installed'], isTrue);
    expect(remoteUosc['enabled'], isTrue);
    expect(remoteUosc['head'],
        'deadbeef00000000000000000000000000000001');

    // A remote manifest is plannable and installable through the manager.
    final plan = manager.planOperation('remote_shader_pack', 'install');
    expect(plan.containsKey('error'), isFalse);
    ok = false;
    await manager.install('mpv360');
    expect(ok, isTrue);
    expect(source.entries[1]['installed'], isTrue);

    // Enabled+installed remote script plugins join the startup scripts
    // option (append-only behind the user's own value).
    final options = <String, String>{'scripts': '/user/own.lua'};
    manager.appendScriptOptions(options);
    final scripts = options['scripts']!;
    expect(scripts, startsWith('/user/own.lua'));
    expect(scripts, contains('plugins/uosc'));
    expect(scripts, contains('plugins/mpv360/mpv360.lua'));
  });

  test('fetchFailureDegradesToCachedEntries', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);

    source.refreshAll();
    fetcher.completeNext(true, body: fixtureBytes());
    expect(source.entries.length, 3);
    final lastRefresh = source.sources.first['lastRefreshMs'] as int;

    source.refreshAll();
    fetcher.completeNext(false, error: 'network unreachable');

    expect(source.lastError, isNotEmpty);
    expect(source.lastError, contains('network unreachable'));
    // Graceful degradation: the cached list stays, the refresh time does not
    // move, and the cycle finishes cleanly.
    expect(source.entries.length, 3);
    expect(source.sources.first['lastRefreshMs'], lastRefresh);
    expect(source.refreshing, isFalse);
  });

  test('malformedRemoteBodyKeepsThePreviousCache', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);

    source.refreshAll();
    fetcher.completeNext(true, body: fixtureBytes());
    expect(source.entries.length, 3);

    // A malformed refresh must not destroy the last good copy (fail closed).
    source.refreshAll();
    fetcher.completeNext(true, body: '{ this is not json');
    expect(source.lastError, isNotEmpty);
    expect(source.entries.length, 3);

    // The previous good cache survives on disk: a fresh instance serves it
    // without any fetch.
    final secondFetcher = FakeFetcher();
    final second =
        RemoteManifestSource(appDataDir: tree.path, fetcher: secondFetcher);
    expect(secondFetcher.requested.length, 0);
    expect(second.entries.length, 3);
  });

  test('cachePersistsAcrossInstances', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    {
      final firstFetcher = FakeFetcher();
      final first =
          RemoteManifestSource(appDataDir: tree.path, fetcher: firstFetcher);
      first.refreshAll();
      firstFetcher.completeNext(true, body: fixtureBytes());
    }

    // The cache directory holds exactly the per-source cache file (the
    // source list itself is only written when a custom source is added).
    final cacheDir = Directory('${tree.path}/plugin-sources');
    expect(cacheDir.listSync().whereType<File>().length, 1);

    // A new instance (e.g. next start, or offline) serves the cached list
    // without any network activity.
    final secondFetcher = FakeFetcher();
    final second =
        RemoteManifestSource(appDataDir: tree.path, fetcher: secondFetcher);
    expect(secondFetcher.requested.length, 0);
    expect(second.entries.length, 3);
    expect((second.sources.first['lastRefreshMs'] as int) > 0, isTrue);
  });

  test('customSourcesAddRemovePersist', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);

    expect(source.addSource(Uri.parse('https://example.org/manager.json')),
        isTrue);
    expect(source.sources.length, 2);

    // Duplicates, bad schemes and the default itself are rejected.
    expect(source.addSource(Uri.parse('https://example.org/manager.json')),
        isFalse);
    expect(source.addSource(Uri.parse('ftp://example.org/manager.json')),
        isFalse);
    expect(
        source.addSource(Uri.parse(
            'https://raw.githubusercontent.com/emoeem/mpv/main/manager.json')),
        isFalse);
    expect(source.sources.length, 2);

    // The default cannot be removed; a custom one can.
    expect(source.removeSource(Uri.parse(RemoteManifestSource.defaultSourceUrl())),
        isFalse);
    expect(source.removeSource(Uri.parse('https://example.org/manager.json')),
        isTrue);
    expect(source.sources.length, 1);
    expect(source.sources.first['isDefault'], isTrue);

    // Custom sources persist across instances (default first, then in
    // insertion order).
    expect(source.addSource(Uri.parse('https://a.example/one.json')), isTrue);
    expect(source.addSource(Uri.parse('https://b.example/two.json')), isTrue);
    final secondFetcher = FakeFetcher();
    final second =
        RemoteManifestSource(appDataDir: tree.path, fetcher: secondFetcher);
    expect(second.sources.length, 3);
    expect(second.sources[0]['isDefault'], isTrue);
    expect(second.sources[1]['url'], 'https://a.example/one.json');
    expect(second.sources[2]['url'], 'https://b.example/two.json');
  });

  test('duplicateCustomUrlsLoadOnce', () {
    // saveSourceList never writes duplicates, but a hand-edited sources.json
    // can carry one: it must still load as a single source row.
    final tree = TempTree();
    addTearDown(tree.dispose);
    final listPath = '${tree.path}/plugin-sources/sources.json';
    Directory('${tree.path}/plugin-sources').createSync(recursive: true);
    File(listPath).writeAsStringSync('{"sources": ['
        '"https://a.example/one.json", '
        '"https://a.example/one.json", '
        '"https://b.example/two.json"]}');

    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);
    expect(source.sources.length, 3); // default + 2 deduped custom rows
    expect(
        sourceRowNamed(source.sources, 'https://a.example/one.json'), isNotEmpty);
    expect(
        sourceRowNamed(source.sources, 'https://b.example/two.json'), isNotEmpty);

    // And the deduped list persists without the duplicate.
    expect(source.addSource(Uri.parse('https://c.example/three.json')), isTrue);
    final secondFetcher = FakeFetcher();
    final second =
        RemoteManifestSource(appDataDir: tree.path, fetcher: secondFetcher);
    expect(second.sources.length, 4);
    var oneCount = 0;
    for (final value in second.sources) {
      if (value['url'] == 'https://a.example/one.json') {
        ++oneCount;
      }
    }
    expect(oneCount, 1);
  });

  test('crossSourceNameCollisionFirstSourceWins', () {
    final tree = TempTree();
    addTearDown(tree.dispose);
    final fetcher = FakeFetcher();
    final source = RemoteManifestSource(appDataDir: tree.path, fetcher: fetcher);

    source.refreshAll();
    fetcher.completeNext(true, body: fixtureBytes());
    expect(source.entries.length, 3);

    // A second source re-declaring "mpv360": the first source (default) wins.
    expect(source.addSource(Uri.parse('https://example.org/other.json')), isTrue);
    fetcher.completeNext(true, body: kSecondSourceJson);
    expect(source.lastError, isEmpty);
    expect(source.entries.length, 4);

    Map<String, Object?> mpv360 = <String, Object?>{};
    for (final value in source.entries) {
      if (value['name'] == 'mpv360') {
        mpv360 = value;
      }
    }
    expect(mpv360['url'], 'https://git.example/mpv360.git');
    expect(
        sourceRowNamed(source.sources, 'https://example.org/other.json'),
        isNotEmpty);
    // The new source contributed its unique entry.
    final hasExtra = source.entries.any((value) => value['name'] == 'extra');
    expect(hasExtra, isTrue);
  });
}
