import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/plugins/plugin_git_runner.dart';
import 'package:emoplay/plugins/plugin_manifest.dart';

// Pure-logic tests for the manager.json-compatible manifest parser
// (docs/nativeization-plan.md §4.1): valid entries, missing/typed fields,
// invalid modes, path-traversal rejection and the shipped builtin catalog.
//
// Case-for-case port of mpv-emo tests/test_plugin_manifest.cpp; assertion
// values are the behavioural contract and are copied verbatim.
void main() {
  Map<String, Object?> entryWithDefaults() => <String, Object?>{
        'name': 'uosc_danmaku',
        'url': 'https://github.com/Tony15246/uosc_danmaku.git',
        'destination': 'scripts/uosc_danmaku',
      };

  test('validEntryParses', () {
    final entry = entryWithDefaults()
      ..['branch'] = 'main'
      ..['source'] = 'src/uosc'
      ..['mode'] = 'check'
      ..['baseline'] = '5.13.0';

    final manifest = PluginManifest.parse(entry);
    expect(manifest.valid, isTrue);
    expect(manifest.name, 'uosc_danmaku');
    expect(manifest.url, 'https://github.com/Tony15246/uosc_danmaku.git');
    expect(manifest.branch, 'main');
    expect(manifest.source, 'src/uosc');
    expect(manifest.destination, 'scripts/uosc_danmaku');
    expect(manifest.mode, 'check');
    expect(manifest.baseline, '5.13.0');
    expect(manifest.isReplace, isFalse);
  });

  test('defaultsFillOptionalFields', () {
    final manifest = PluginManifest.parse(entryWithDefaults());
    expect(manifest.valid, isTrue);
    // Defaults per nativeization-plan §4.1/§4.2: branch main, source "."
    // (whole repo), mode check (never destructive by default), no baseline.
    expect(manifest.branch, 'main');
    expect(manifest.source, '.');
    expect(manifest.mode, 'check');
    expect(manifest.baseline, '');
  });

  test('missingRequiredFieldsRejected', () {
    final noName = entryWithDefaults()..remove('name');
    expect(PluginManifest.parse(noName).valid, isFalse);

    final noUrl = entryWithDefaults()..remove('url');
    expect(PluginManifest.parse(noUrl).valid, isFalse);

    final noDestination = entryWithDefaults()..remove('destination');
    expect(PluginManifest.parse(noDestination).valid, isFalse);
  });

  test('invalidModeRejected', () {
    // A typo in mode must never silently pick the destructive semantics.
    final entry = entryWithDefaults()..['mode'] = 'repalce';
    final manifest = PluginManifest.parse(entry);
    expect(manifest.valid, isFalse);
    expect(manifest.error, contains('mode'));
  });

  test('typeConfusionRejected', () {
    final entry = entryWithDefaults()..['branch'] = 3;
    expect(PluginManifest.parse(entry).valid, isFalse);

    final nameIsNumber = entryWithDefaults()..['name'] = 42;
    expect(PluginManifest.parse(nameIsNumber).valid, isFalse);
  });

  test('pluginNameCharsetEnforced', () {
    // The name becomes a directory name under <AppData>/plugins/ — no
    // separators, no dots, no emptiness.
    final slash = entryWithDefaults()..['name'] = '../evil';
    expect(PluginManifest.parse(slash).valid, isFalse);

    final hidden = entryWithDefaults()..['name'] = '.git';
    expect(PluginManifest.parse(hidden).valid, isFalse);

    final uppercase = entryWithDefaults()..['name'] = 'Anime4K_Pack';
    expect(PluginManifest.parse(uppercase).valid, isTrue); // charset allows A-Z
  });

  test('unsafePathsRejected', () {
    final traversal = entryWithDefaults()
      ..['destination'] = 'shaders/../../etc';
    expect(PluginManifest.parse(traversal).valid, isFalse);

    final absolute = entryWithDefaults()..['source'] = '/etc/mpv';
    expect(PluginManifest.parse(absolute).valid, isFalse);

    final dotdotSource = entryWithDefaults()..['source'] = '..';
    expect(PluginManifest.parse(dotdotSource).valid, isFalse);
  });

  test('managerJsonFormAccepted', () {
    // mpv-Emo manager.json wraps the entries in a "sources" array.
    final root = <String, Object?>{
      'sources': [entryWithDefaults()],
    };
    final error = StringBuffer();
    final manifests =
        PluginManifest.parseList(jsonEncode(root), errorOut: error);
    expect(error.toString(), isEmpty);
    expect(manifests.length, 1);
    expect(manifests.first.valid, isTrue);
  });

  test('bareArrayFormAccepted', () {
    final error = StringBuffer();
    final manifests = PluginManifest.parseList(
        jsonEncode([entryWithDefaults()]),
        errorOut: error);
    expect(error.toString(), isEmpty);
    expect(manifests.length, 1);
  });

  test('duplicateNamesRejected', () {
    // Plugin ids are unique: the second entry must not shadow the first.
    final error = StringBuffer();
    final manifests = PluginManifest.parseList(
        jsonEncode([entryWithDefaults(), entryWithDefaults()]),
        errorOut: error);
    expect(manifests, isEmpty);
    expect(error.toString(), contains('duplicate'));
  });

  test('malformedJsonRejected', () {
    final error = StringBuffer();
    expect(
      PluginManifest.parseList('{not json', errorOut: error),
      isEmpty,
    );
    expect(error.toString(), isNotEmpty);

    error.clear();
    expect(PluginManifest.parseList('42', errorOut: error), isEmpty);
    expect(error.toString(), isNotEmpty);
  });

  test('scriptPluginDetection', () {
    // scripts/ destinations feed mpv's --scripts option; shaders/ do not.
    final script = entryWithDefaults()..['destination'] = 'scripts/uosc_danmaku';
    expect(PluginManifest.parse(script).isScriptPlugin, isTrue);

    final singleFile = entryWithDefaults()
      ..['destination'] = 'scripts/mpv360.lua';
    expect(PluginManifest.parse(singleFile).isScriptPlugin, isTrue);

    final shader = entryWithDefaults()
      ..['destination'] = 'shaders/Anime4K/glsl';
    expect(PluginManifest.parse(shader).isScriptPlugin, isFalse);
  });

  test('contentRootHonorsSourceSubtree', () {
    final whole = PluginManifest.parse(entryWithDefaults());
    expect(whole.valid, isTrue);
    expect(whole.contentRoot('/plugins/x'), '/plugins/x');

    final subtree = entryWithDefaults()..['source'] = 'src/uosc';
    final manifest = PluginManifest.parse(subtree);
    expect(manifest.valid, isTrue);
    expect(manifest.contentRoot('/plugins/uosc'), '/plugins/uosc/src/uosc');
  });

  test('builtinCatalogParsesWithSixUpstreamSources', () {
    // The catalog shipped with the app is transcribed from the user
    // repository emoeem/mpv manager.json (commit 70d6eb4). It must always
    // parse and keep exactly these six upstream sources.
    final file = File('assets/plugins/builtin_sources.json');
    expect(file.existsSync(), isTrue,
        reason: 'builtin catalog not found at the asset path');
    final error = StringBuffer();
    final manifests =
        PluginManifest.parseList(file.readAsStringSync(), errorOut: error);
    if (error.isNotEmpty) {
      fail(error.toString());
    }
    expect(manifests.length, 6);

    final names = [for (final manifest in manifests) manifest.name]..sort();
    expect(names.join(','),
        'anime4k,file_browser,hdr-toys,trakt_scrobble,uosc,uosc_danmaku');

    // Spot-check the transcribed fields against manager.json (70d6eb4).
    PluginManifest find(String name) =>
        manifests.firstWhere((manifest) => manifest.name == name);

    final uosc = find('uosc');
    expect(uosc.valid, isTrue);
    expect(uosc.url, 'https://github.com/tomasklaen/uosc.git');
    expect(uosc.branch, 'main');
    expect(uosc.source, 'src/uosc');
    expect(uosc.destination, 'scripts/uosc');
    expect(uosc.mode, 'check');
    expect(uosc.baseline, '5.13.0');

    final danmaku = find('uosc_danmaku');
    expect(danmaku.valid, isTrue);
    expect(danmaku.mode, 'check');
    expect(danmaku.baseline, 'd8c1cd8b4786c286a19079caef3f9ac9fa64933d');

    final anime4k = find('anime4k');
    expect(anime4k.valid, isTrue);
    expect(anime4k.mode, 'replace');
    expect(anime4k.branch, 'master');
    expect(anime4k.source, 'glsl');
    expect(anime4k.destination, 'shaders/Anime4K/glsl');
    expect(anime4k.isScriptPlugin, isFalse);

    final fileBrowser = find('file_browser');
    expect(fileBrowser.valid, isTrue);
    expect(fileBrowser.mode, 'replace');
    expect(fileBrowser.destination, 'scripts/file-browser');
    expect(fileBrowser.isScriptPlugin, isTrue);

    final hdrToys = find('hdr-toys');
    expect(hdrToys.valid, isTrue);
    expect(hdrToys.mode, 'check');
    expect(hdrToys.baseline, 'b43e4575bdd655f4c7536f704219798b07d9a300');
    expect(hdrToys.isScriptPlugin, isFalse);

    final trakt = find('trakt_scrobble');
    expect(trakt.valid, isTrue);
    expect(trakt.mode, 'check');
    expect(trakt.baseline, isEmpty);
  });

  // ---- M6-T1 asset integrity (size+hash pair, roadmap §五 M6-T1) ------------

  // A well-formed 64-hex digest used as a manifest fixture value.
  const String kFixtureSha256 =
      'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';

  test('integrityPairIncompleteRefusedForInstall', () {
    // 缺一拒装: pinning only ONE of sizeBytes/sha256 refuses the install.
    // Parse itself stays accepting so one half-pinned entry cannot nuke a
    // whole catalog — the install gate is the refusal point.
    final noHash = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sizeBytes': 1234,
    });
    expect(noHash.valid, isTrue);
    expect(noHash.hasIntegrityFields, isTrue);
    expect(noHash.isIntegrityPinned, isFalse);
    expect(noHash.integrityGateError(), contains('without sha256'));

    // 缺 hash 拒绝.
    final noSize = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sha256': kFixtureSha256,
    });
    expect(noSize.valid, isTrue);
    expect(noSize.isIntegrityPinned, isFalse);
    expect(noSize.integrityGateError(), contains('without sizeBytes'));

    // Neither field: the 1.x manager.json form stays installable as before.
    final legacy = PluginManifest.parse(entryWithDefaults());
    expect(legacy.valid, isTrue);
    expect(legacy.hasIntegrityFields, isFalse);
    expect(legacy.integrityGateError(), isEmpty);

    // The complete pair passes the gate.
    final pinned = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sizeBytes': 1234,
      'sha256': kFixtureSha256,
    });
    expect(pinned.isIntegrityPinned, isTrue);
    expect(pinned.integrityGateError(), isEmpty);
  });

  test('malformedIntegrityFieldsRejectedAtParse', () {
    // A declared sha256 must be a full 64-hex digest.
    final shortHash = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sha256': 'deadbeef',
    });
    expect(shortHash.valid, isFalse);
    expect(shortHash.error, contains('sha256'));

    // Uppercase hex is a valid digest shape (verification is case-insensitive).
    final upperHash = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sha256': kFixtureSha256.toUpperCase(),
    });
    expect(upperHash.valid, isTrue);

    // sizeBytes must be a JSON integer — no silent coercion.
    final sizeAsString = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sizeBytes': '1234',
    });
    expect(sizeAsString.valid, isFalse);
    expect(sizeAsString.error, contains('sizeBytes'));

    final sizeAsDouble = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sizeBytes': 1234.5,
    });
    expect(sizeAsDouble.valid, isFalse);

    final negativeSize = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'sizeBytes': -1,
    });
    expect(negativeSize.valid, isFalse);
    expect(negativeSize.error, contains('sizeBytes'));
  });

  test('integrityFieldsRoundtrip', () {
    // 字段往返: parse(toMap()) preserves every field, integrity pair included.
    final pinned = PluginManifest.parse(<String, Object?>{
      ...entryWithDefaults(),
      'branch': 'main',
      'source': 'src/uosc',
      'mode': 'check',
      'baseline': '5.13.0',
      'sizeBytes': 4096,
      'sha256': kFixtureSha256,
    });
    expect(pinned.valid, isTrue);
    final round = PluginManifest.parse(pinned.toMap());
    expect(round.valid, isTrue);
    expect(round.name, pinned.name);
    expect(round.url, pinned.url);
    expect(round.branch, pinned.branch);
    expect(round.source, pinned.source);
    expect(round.destination, pinned.destination);
    expect(round.mode, pinned.mode);
    expect(round.baseline, pinned.baseline);
    expect(round.sizeBytes, 4096);
    expect(round.sha256, kFixtureSha256);
    expect(round.isIntegrityPinned, isTrue);
    expect(round.integrityGateError(), isEmpty);

    // Unpinned entries keep the exact 1.x field shape: no integrity keys.
    final legacy = PluginManifest.parse(entryWithDefaults());
    expect(legacy.toMap().containsKey('sha256'), isFalse);
    expect(legacy.toMap().containsKey('sizeBytes'), isFalse);
    final legacyRound = PluginManifest.parse(legacy.toMap());
    expect(legacyRound.valid, isTrue);
    expect(legacyRound.sizeBytes, isNull);
    expect(legacyRound.sha256, isEmpty);
  });

  test('replaySameHashPasses', () async {
    // 重放同 hash 通过: the digest is deterministic — the same content tree
    // digests identically every time and verification passes on replay.
    final dir = await Directory.systemTemp.createTemp('emoplay-manifest-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${dir.path}/main.lua').writeAsStringSync('fake\n');
    Directory('${dir.path}/lib').createSync();
    File('${dir.path}/lib/util.lua').writeAsStringSync('-- util\n');
    // Clone metadata must be invisible to the digest: a .git directory with
    // arbitrary content must not change the result.
    Directory('${dir.path}/.git').createSync();
    File('${dir.path}/.git/HEAD').writeAsStringSync('ref: junk\n');

    final first = await PluginContentIntegrity.compute(dir.path);
    final second = await PluginContentIntegrity.compute(dir.path);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.sha256, first!.sha256);
    expect(second.sizeBytes, first.sizeBytes);
    expect(PluginContentIntegrity.isValidSha256(first.sha256), isTrue);

    // Replay: same tree → verification passes, twice in a row.
    for (var i = 0; i < 2; ++i) {
      final reason = await PluginContentIntegrity.verify(
        contentRoot: dir.path,
        expectedSha256: first.sha256,
        expectedSize: first.sizeBytes,
      );
      expect(reason, isNull);
    }

    // Recreating the identical tree elsewhere yields the same digest.
    final twin = await Directory.systemTemp.createTemp('emoplay-manifest-');
    addTearDown(() {
      try {
        twin.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${twin.path}/main.lua').writeAsStringSync('fake\n');
    Directory('${twin.path}/lib').createSync();
    File('${twin.path}/lib/util.lua').writeAsStringSync('-- util\n');
    final twinDigest = await PluginContentIntegrity.compute(twin.path);
    expect(twinDigest!.sha256, first.sha256);
    expect(twinDigest.sizeBytes, first.sizeBytes);
  });

  test('contentHashMismatchRejected', () async {
    // hash 不符拒绝: any byte flip must be caught, with the failure naming
    // what diverged.
    final dir = await Directory.systemTemp.createTemp('emoplay-manifest-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    File('${dir.path}/main.lua').writeAsStringSync('fake\n');
    final good = await PluginContentIntegrity.compute(dir.path);
    expect(good, isNotNull);

    // Tampered tree: the size check trips first (both diverge here).
    File('${dir.path}/main.lua').writeAsStringSync('faked\n');
    final sizeReason = await PluginContentIntegrity.verify(
      contentRoot: dir.path,
      expectedSha256: good!.sha256,
      expectedSize: good.sizeBytes,
    );
    expect(sizeReason, isNotNull);
    expect(sizeReason, contains('size mismatch'));

    // Pure hash mismatch: correct size, wrong digest.
    final tampered = await PluginContentIntegrity.compute(dir.path);
    final hashReason = await PluginContentIntegrity.verify(
      contentRoot: dir.path,
      expectedSha256: kFixtureSha256,
      expectedSize: tampered!.sizeBytes,
    );
    expect(hashReason, isNotNull);
    expect(hashReason, contains('sha256 mismatch'));

    // Case-insensitive comparison: an uppercase expected digest still matches.
    final ok = await PluginContentIntegrity.verify(
      contentRoot: dir.path,
      expectedSha256: tampered.sha256.toUpperCase(),
      expectedSize: tampered.sizeBytes,
    );
    expect(ok, isNull);

    // A missing content directory is a refusal, not a crash.
    final missing = await PluginContentIntegrity.verify(
      contentRoot: '${dir.path}/absent',
      expectedSha256: kFixtureSha256,
      expectedSize: 0,
    );
    expect(missing, isNotNull);
    expect(missing, contains('missing'));
  });
}
