import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/history_store.dart';
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
///  * restoreDefaultsKeepsMediaAndHistory → NEW here (this file). The 2.0
///    restoreDefaults control now exists (施工件 B): EmoPlaySettings
///    restores the quality/behavior/music sections (the 1.x facade only
///    reset the behavior fields; the 2.0 scope extension is the ask), the
///    UI slot is the general page's「恢复默认设置」tile with an EmoDialog
///    danger confirm (general_settings.dart _confirmRestoreDefaults), and
///    the import decision stays untouched — the 1.x assertion that
///    qualityTier survives is superseded by that scope (noted in the test).
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

  test('restoreDefaultsKeepsMediaAndHistory', () async {
    // 1.x case (test_settings_service.cpp:102-122): seed the sections with
    // non-default values, restore, and prove the behavior section reset.
    // The 2.0 scope (施工件 B) extends the reset to the quality and music
    // sections; what must survive is the import decision (the recorded
    // mpv-config choice, a separate deliberate user choice — the 1.x
    // header comment "never touches ... the user's mpv config") and both
    // media-data files.
    final settingsPath = '${tempDir.path}/settings.json';
    final settings = EmoPlaySettings(settingsPath);
    settings.setImportDecision('full');
    final importedAtBefore = settings.importedAt;
    settings.qualityContentMode = 'anime';
    settings.qualityTier = 'high';
    settings.qualityToneMapping = 'bt.2390';
    settings.qualityScaleOverride = 'ewa_lanczossharp';
    settings.qualityDebandMode = 'yes';
    settings.manualShaderList = ['/tmp/anime4k/a.glsl'];
    settings.qualityInterpolationEnabled = true;
    settings.qualityInterpolationPreset = 'MEMC_01';
    settings.qualityIccEnabled = true;
    settings.qualityIccProfilePath = '/tmp/screen.icc';
    settings.musicEqualizerEnabled = true;
    settings.musicEqualizerPreset = 'bass';
    settings.musicEqualizerGains = List<double>.filled(10, -3.0);
    settings.resumeOnReopen = false;
    settings.libraryMaxDepth = 5;
    settings.librarySkipHidden = false;
    expect(settings.save(), isTrue);

    // A real library.json (one scanned entry) and history.json (one
    // record): restoreDefaults must leave both files byte-identical —
    // the facade owns no reference to either store (that wiring lives in
    // the page), so nothing can even reach them.
    final media = Directory('${tempDir.path}/media');
    media.createSync();
    File('${media.path}/a.mkv').writeAsStringSync('x');
    final library = LibraryStore('${tempDir.path}/library.json');
    addTearDown(library.dispose);
    expect(library.addDirectory(media.path), isTrue);
    await pumpUntil(() => !library.isScanning);
    expect(library.entryList, hasLength(1));
    final history = HistoryStore(null, '${tempDir.path}/history.json');
    addTearDown(history.dispose);
    history.recordPlayback('${media.path}/a.mkv', 'a', 12.5, 90.0);
    expect(history.entries, hasLength(1));
    final libraryJsonBefore =
        File('${tempDir.path}/library.json').readAsStringSync();
    final historyJsonBefore =
        File('${tempDir.path}/history.json').readAsStringSync();
    expect(libraryJsonBefore, isNotEmpty);
    expect(historyJsonBefore, isNotEmpty);

    settings.restoreDefaults();

    // Behavior section back to defaults (the three C++ QCOMPAREs).
    expect(settings.resumeOnReopen, isTrue);
    expect(settings.libraryMaxDepth, 2);
    expect(settings.librarySkipHidden, isTrue);
    // Quality section back to defaults (2.0 scope; supersedes the C++
    // assertion that qualityTier survives — the ask resets the section).
    expect(settings.qualityContentMode, 'auto');
    expect(settings.qualityTier, 'off');
    expect(settings.qualityToneMapping, 'auto');
    expect(settings.qualityScaleOverride, '');
    expect(settings.qualityDebandMode, 'auto');
    expect(settings.manualShaderList, isEmpty);
    expect(settings.qualityInterpolationEnabled, isFalse);
    expect(settings.qualityInterpolationPreset, 'MEMC_RIFE_STD');
    expect(settings.qualityIccEnabled, isFalse);
    expect(settings.qualityIccProfilePath, '');
    // Music section back to defaults.
    expect(settings.musicEqualizerEnabled, isFalse);
    expect(settings.musicEqualizerPreset, 'flat');
    expect(settings.musicEqualizerGains, isEmpty);
    // The import decision survives untouched.
    expect(settings.importDecision, 'full');
    expect(settings.importedAt, importedAtBefore);

    // The page contract: the caller persists and a fresh instance reads
    // the defaults back off disk.
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(settingsPath);
    expect(reloaded.load(), isTrue);
    expect(reloaded.resumeOnReopen, isTrue);
    expect(reloaded.libraryMaxDepth, 2);
    expect(reloaded.librarySkipHidden, isTrue);
    expect(reloaded.qualityTier, 'off');
    expect(reloaded.qualityDebandMode, 'auto');
    expect(reloaded.musicEqualizerEnabled, isFalse);
    expect(reloaded.musicEqualizerPreset, 'flat');
    expect(reloaded.importDecision, 'full');
    expect(reloaded.importedAt, importedAtBefore);

    // Media and history files untouched, byte for byte.
    expect(
      File('${tempDir.path}/library.json').readAsStringSync(),
      libraryJsonBefore,
    );
    expect(
      File('${tempDir.path}/history.json').readAsStringSync(),
      historyJsonBefore,
    );
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
