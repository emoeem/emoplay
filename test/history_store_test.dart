import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/history_store.dart';

/// Headless unit tests for the persisted playback history. The storage file
/// path is injected per test (temp directory) and the engine is a stub — the
/// 1.x tests used the real libmpv core where needed (initialize works
/// without media), which is unavailable to a pure Dart test; a stub engine
/// reporting "idle, no path" reproduces exactly the property state the C++
/// cases exercised.
///
/// Case-for-case port of mpv-emo tests/test_history_store.cpp; assertion
/// values are the behavioural contract and are copied verbatim. The two
/// engine-driven cases (fileLoadedWithoutMediaRecordsNothing /
/// timerTickWithoutMediaIsNoop) call the handlers directly like the C++
/// QMetaObject::invokeMethod did.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-history-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String filePath([String name = 'history.json']) =>
      '${tempDir.path}/$name';

  test('defaultPathIsHistoryJsonInAppData', () async {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() => PathProviderPlatform.instance = previous);

    final path = await HistoryStore.defaultFilePath();
    expect(File(path).isAbsolute, isTrue);
    expect(path, endsWith('history.json'));
    // Test mode redirects the app-support location away from the user's
    // real data (1.x asserted the ".qttest" marker).
    expect(path, contains(tempDir.path));
  });

  test('recordsAndPersistsAcrossInstances', () async {
    final file = filePath();
    {
      final store = HistoryStore(null, file);
      addTearDown(store.dispose);
      store.recordPlayback('/a/first.mkv', 'First', 0.0, 100.0);
      store.recordPlayback('/b/second.mkv', 'Second', 12.5, 200.0);

      expect(store.entries, hasLength(2));
      final top = store.entries[0];
      expect(top.path, '/b/second.mkv');
      expect(top.title, 'Second');
      expect(top.position, 12.5);
      expect(top.duration, 200.0);
      expect(DateTime.tryParse(top.lastPlayedAt), isNotNull);
    }

    // A fresh instance over the same file sees the persisted entries.
    final reloaded = HistoryStore(null, file);
    addTearDown(reloaded.dispose);
    expect(reloaded.entries, hasLength(2));
    expect(reloaded.entries[0].path, '/b/second.mkv');
    expect(reloaded.entries[1].path, '/a/first.mkv');
  });

  test('dedupesByPathAndCapsAt50', () async {
    final store = HistoryStore(null, filePath());
    addTearDown(store.dispose);

    for (var i = 0; i < 60; i++) {
      store.recordPlayback('/m/$i.mkv', 'T$i', 0.0, i.toDouble());
    }

    expect(store.entries, hasLength(50));
    expect(store.entries[0].path, '/m/59.mkv');

    // Re-playing an older entry moves it to the top instead of duplicating.
    store.recordPlayback('/m/10.mkv', 'T10 again', 5.0, 10.0);
    expect(store.entries, hasLength(50));
    expect(store.entries[0].path, '/m/10.mkv');

    final occurrences = store
        .entries
        .where((entry) => entry.path == '/m/10.mkv')
        .length;
    expect(occurrences, 1);

    // The oldest entry fell off the bottom when the cap was reached.
    for (final entry in store.entries) {
      expect(entry.path, isNot('/m/0.mkv'));
    }
  });

  test('positionUpdateKeepsOrderAndTimestamp', () async {
    final store = HistoryStore(null, filePath());
    addTearDown(store.dispose);

    store.recordPlayback('/a/first.mkv', 'First', 0.0, 100.0);
    store.recordPlayback('/b/second.mkv', 'Second', 0.0, 200.0);
    final stampBefore = store.entries[0].lastPlayedAt;

    store.updateEntryPosition('/b/second.mkv', 77.5);

    expect(store.entries, hasLength(2)); // no re-order, no duplicate
    final top = store.entries[0];
    expect(top.path, '/b/second.mkv');
    expect(top.position, 77.5);
    expect(top.lastPlayedAt, stampBefore);
  });

  test('positionUpdateOfUnknownPathIsNoop', () async {
    final store = HistoryStore(null, filePath());
    addTearDown(store.dispose);
    store.recordPlayback('/a/first.mkv', 'First', 1.0, 10.0);

    store.updateEntryPosition('/unknown.mkv', 42.0);

    expect(store.entries, hasLength(1));
    expect(store.entries[0].position, 1.0);
  });

  test('corruptFileRecoversToEmpty', () async {
    final file = filePath();
    await File(file).writeAsString('this is not json {{{');

    final store = HistoryStore(null, file);
    addTearDown(store.dispose);
    expect(store.entries, isEmpty);

    // Recording must overwrite the broken file with valid JSON again.
    store.recordPlayback('/a/first.mkv', 'First', 0.0, 10.0);
    final reloaded = HistoryStore(null, file);
    addTearDown(reloaded.dispose);
    expect(reloaded.entries, hasLength(1));
  });

  test('emptyPathIsIgnored', () async {
    final store = HistoryStore(null, filePath());
    addTearDown(store.dispose);

    store.recordPlayback('', 'No path', 0.0, 0.0);
    store.updateEntryPosition('', 5.0);

    expect(store.entries, isEmpty);
  });

  test('fileLoadedWithoutMediaRecordsNothing', () async {
    // No media was loaded, so the handler finds no "path" property and must
    // ignore the event instead of recording an empty entry.
    final store = HistoryStore(_StubEngine.idle(), filePath());
    addTearDown(store.dispose);

    store.onFileLoaded();

    expect(store.entries, isEmpty);
  });

  test('timerTickWithoutMediaIsNoop', () async {
    final store = HistoryStore(_StubEngine.idle(), filePath());
    addTearDown(store.dispose);
    store.recordPlayback('/x/a.mkv', 'A', 0.0, 10.0);

    // Engine is idle (no media): the 5s tick must not touch the entries.
    store.onTimerTick();

    expect(store.entries, hasLength(1));
    expect(store.entries[0].position, 0.0);
  });

  test('timerTickWithLiveMediaUpdatesPosition', () async {
    // Complements the C++ engine cases with the live path: not idle, valid
    // path and time-pos -> the tick writes the position of the live file.
    final store =
        HistoryStore(_StubEngine.playing('/x/a.mkv', 33.0), filePath());
    addTearDown(store.dispose);
    store.recordPlayback('/x/a.mkv', 'A', 0.0, 10.0);

    store.onTimerTick();

    expect(store.entries, hasLength(1));
    expect(store.entries[0].position, 33.0);
  });

  test('removesSingleEntry', () async {
    final file = filePath();
    final store = HistoryStore(null, file);
    addTearDown(store.dispose);
    store.recordPlayback('/a/one.mkv', 'One', 0.0, 10.0);
    store.recordPlayback('/a/two.mkv', 'Two', 0.0, 10.0);

    store.removeEntry('/a/one.mkv');
    expect(store.entries, hasLength(1));
    expect(store.entries[0].path, '/a/two.mkv');

    // Unknown paths are a no-op: no signal, no state change.
    store.removeEntry('/a/never-played.mkv');
    expect(store.entries, hasLength(1));

    // The removal is persisted, not only applied in memory.
    final reloaded = HistoryStore(null, file);
    addTearDown(reloaded.dispose);
    expect(reloaded.entries, hasLength(1));
    expect(reloaded.entries[0].path, '/a/two.mkv');
  });

  test('clearsAllEntries', () async {
    final file = filePath();
    final store = HistoryStore(null, file);
    addTearDown(store.dispose);
    store.recordPlayback('/a/one.mkv', 'One', 0.0, 10.0);
    store.recordPlayback('/a/two.mkv', 'Two', 0.0, 10.0);

    store.clear();
    expect(store.entries, isEmpty);

    // Clearing an already empty history must stay silent.
    store.clear();
    expect(store.entries, isEmpty);

    final reloaded = HistoryStore(null, file);
    addTearDown(reloaded.dispose);
    expect(reloaded.entries, isEmpty);
  });
}

/// Minimal HistoryEngine double standing in for 1.x's real MpvEngine
/// (libmpv cannot be embedded in a Dart VM test).
class _StubEngine implements HistoryEngine {
  _StubEngine._(this.idleActive, this.path, this.timePos);

  factory _StubEngine.idle() => _StubEngine._(true, '', null);

  factory _StubEngine.playing(String path, double position) =>
      _StubEngine._(false, path, position);

  final bool idleActive;

  final String path;
  final double? timePos;

  @override
  Object? getProperty(String name) => switch (name) {
        'idle-active' => idleActive,
        'path' => path.isEmpty ? null : path,
        'time-pos' => timePos,
        _ => null,
      };

  @override
  Stream<void> get fileLoaded => const Stream<void>.empty();

  @override
  Stream<bool> get idleActiveChanged => const Stream<bool>.empty();
}

/// QStandardPaths::setTestModeEnabled equivalent: redirects the
/// application-support resolution used by HistoryStore.defaultFilePath().
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
