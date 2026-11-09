import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
