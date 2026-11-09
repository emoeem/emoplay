import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

/// Port of the two mpv-emo tests/test_settings_service.cpp slots that had no
/// Dart counterpart when 1.x was reconciled (WORK_REPORT 2026-11-10 §3.1
/// "❌ 未一对一落地" / §6.4 "顺带补 test_settings_service 的语义断言").
///
/// Slot map for the whole C++ file (the 2.0 equivalent of the QML-facing
/// SettingsService facade is the EmoPlaySettings behavior section plus the
/// two call sites that push it into the scanner — the settings page's
/// _persistBehavior, lib/pages/settings/general_settings.dart:58-70, and the
/// startup wiring, lib/media/media_stores.dart:174-178):
///  * defaultsMatchAppSettings → behaviorSectionRoundTrips prelude
///    (test/emoplay_settings_test.dart) + asserted again below as the
///    precondition of libraryOptionsReachTheScanner.
///  * settersPersistImmediately → behaviorSectionRoundTrips; the disk-carry
///    assertion is repeated inside libraryOptionsReachTheScanner.
///  * libraryOptionsReachTheScanner → NEW here (this file).
///  * restoreDefaultsKeepsMediaAndHistory → the surviving invariant
///    (behavior writes must not disturb importDecision/qualityTier) is
///    locked by behaviorSectionRoundTrips; a 2.0 restoreDefaults control
///    itself does not exist yet (no UI) — deliberately not faked here.
///  * failedWriteSurfacesLastError → NEW here, adapted: the Dart facade
///    reports failure as save() returning false (the page shows a toast,
///    general_settings.dart:62-64) instead of a lastError signal, and
///    LibraryStore keeps its QSaveFile silent-failure contract
///    (library_store.dart:785-788).
///
/// The scanner tests run through the real worker isolate, like the
/// library_store_test.dart "cancellation through the real worker isolate"
/// group; QTRY_* polling becomes pumpUntil().
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-settings-svc-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('libraryOptionsReachTheScanner', () async {
    // 1.x tree: four files at depth 0..3 under one root.
    final media = Directory('${tempDir.path}/media');
    for (final relative in <String>[
      'top.mkv',
      'one/mid.mkv',
      'one/two/deep.mkv',
      'one/two/three/deepest.mkv',
    ]) {
      final file = File('${media.path}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString('x');
    }

    final settings = EmoPlaySettings('${tempDir.path}/settings.json');
    // defaultsMatchAppSettings: the behavior defaults the scanner would pick
    // up on first launch.
    expect(settings.resumeOnReopen, isTrue);
    expect(settings.libraryMaxDepth, 2);
    expect(settings.librarySkipHidden, isTrue);

    // Startup wiring (media_stores.dart:174-178): the recorded settings
    // reach LibraryStore.setScanOptions before any scan.
    final library = LibraryStore('${tempDir.path}/library.json');
    addTearDown(library.dispose);
    library.setScanOptions(ScanOptions(
      maxDepth: settings.libraryMaxDepth,
      skipHidden: settings.librarySkipHidden,
    ));

    expect(library.addDirectory(media.path), isTrue);
    await pumpUntil(() => !library.isScanning);
    expect(library.entryList, hasLength(3)); // default depth 2
    expect(
      library.entryList.map((entry) => entry.title),
      containsAll(<String>['top', 'mid', 'deep']),
    );
    expect(
      library.entryList.map((entry) => entry.title),
      isNot(contains('deepest')),
    );

    // The settings page contract (_persistBehavior, general_settings.dart:
    // 58-70): setters persist immediately and the scan options reach the
    // store right away — the next scan finds the deeper file without a
    // restart (1.x test_settings_service.cpp:72-100).
    settings.libraryMaxDepth = 0;
    expect(settings.save(), isTrue);
    library.setScanOptions(ScanOptions(
      maxDepth: settings.libraryMaxDepth,
      skipHidden: settings.librarySkipHidden,
    ));

    // The persisted file already carries it (settersPersistImmediately).
    final reloaded = EmoPlaySettings('${tempDir.path}/settings.json');
    expect(reloaded.load(), isTrue);
    expect(reloaded.libraryMaxDepth, 0);

    // Page-side changes do not auto-rescan; the folder rescan the page
    // triggers elsewhere (or the user's manual rescan) picks the new
    // options up.
    library.requestScan();
    await pumpUntil(
      () => !library.isScanning && library.entryList.length == 4,
    );
    expect(
      library.entryList.map((entry) => entry.title),
      contains('deepest'),
    );
    expect(library.lastScanCancelled, isFalse);
  });

  test('failedWriteIsReportedInsteadOfSilentlyLost', () async {
    // A regular file where the settings/library directory should be: the
    // write cannot succeed (1.x made the directory under a file blocker).
    final blocker = File('${tempDir.path}/blocker');
    blocker.writeAsStringSync('not a directory');

    // Dart facade contract: save() reports the failure as false instead of
    // throwing, and the in-memory state stays authoritative (the caller —
    // the settings page — surfaces it as a toast).
    final settings = EmoPlaySettings('${blocker.path}/settings.json');
    settings.libraryMaxDepth = 4;
    expect(settings.save(), isFalse);
    expect(File('${blocker.path}/settings.json').existsSync(), isFalse);

    // LibraryStore keeps QSaveFile::commit() semantics (silent failure, the
    // in-memory state stays authoritative, library_store.dart:772-789): the
    // scan of the folder works, the persist fails without a throw and no
    // stray file appears.
    final library = LibraryStore('${blocker.path}/library.json');
    addTearDown(library.dispose);
    final media = Directory('${tempDir.path}/media');
    media.createSync();
    File('${media.path}/a.mkv').writeAsStringSync('x');

    expect(library.addDirectory(media.path), isTrue); // no throw
    expect(library.directories, <String>[media.path]);
    // Let the auto-scan (spawned by addDirectory) run to completion: its
    // result lands through _applyScanResults → _save(), which must swallow
    // the failed persist the same way (no throw, no stray file).
    await pumpUntil(() => !library.isScanning);
    expect(library.entryList, hasLength(1));
    expect(File('${blocker.path}/library.json').existsSync(), isFalse);
  });
}
