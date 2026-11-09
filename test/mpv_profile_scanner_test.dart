// Dart port of mpv-emo tests/test_compat_scanner.cpp — headless unit tests
// for the compat scanner. The 1.x committed fixture tree (tests/fixtures/
// mpv-conf) is rebuilt in a temporary directory before the tests run (same
// file contents, same counts); location probing uses injected base
// directories so the real HOME is never read or written.
//
// Fixture file contents byte-identical to the 1.x fixture:
//   mpv.conf       : "# sample user mpv.conf (fixture)" + 3 top-level
//                    options + [hq] section with 2 options
//   input.conf     : "# sample user input.conf (fixture)" + 3 bindings
//   profiles.conf  : [game]/[movie] sections with 3 option entries
//   platform.conf  : "ao=pipewire"
//   script-opts/foo.conf : "enabled=yes"
//   scripts/{a.lua,lib/b.js} 18 bytes each, scripts/data.bin 16 bytes,
//   shaders/x.glsl 23 bytes, fonts/Fake.ttf 8 bytes.
import 'dart:convert';
import 'dart:io';

import 'package:emoplay/mpv/compat/mpv_profile_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

late Directory fixtureDir;

Future<void> _write(String relativePath, String text) async {
  final file = File(p.join(fixtureDir.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(utf8.encode(text));
}

void main() {
  setUpAll(() async {
    fixtureDir =
        await Directory.systemTemp.createTemp('emoplay_mpv_conf_fixture_');
    // Content mirrors tests/fixtures/mpv-conf (counts assert in
    // entryCountsComeFromParser).
    await _write('mpv.conf', '# sample user mpv.conf (fixture)\n'
        'vo=gpu-next\n'
        'volume=80\n'
        'keep-open=yes\n'
        '\n'
        '[hq]\n'
        'scale=ewa_lanczossharp\n'
        'deband=yes\n');
    await _write('input.conf', '# sample user input.conf (fixture)\n'
        'SPACE cycle pause\n'
        'RIGHT seek 30\n'
        'ctrl+s screenshot #menu: Screenshot\n');
    await _write('profiles.conf', '[game]\n'
        'profile-desc=low latency\n'
        'interpolation=no\n'
        '\n'
        '[movie]\n'
        'interpolation=yes\n');
    await _write('platform.conf', 'ao=pipewire\n');
    await _write('script-opts/foo.conf', 'enabled=yes\n');
    // Non-config files: sizes match the 1.x fixture (18/18/16/23/8 bytes);
    // content is irrelevant to the assertions, only size > 0 is checked.
    await _write('scripts/a.lua', '-- probe script a\n'.padRight(18));
    await _write('scripts/lib/b.js', '// probe script b\n'.padRight(18));
    await _write('scripts/data.bin', '.' * 16);
    await _write('shaders/x.glsl', '//!HOOK LUMA\n'.padRight(23));
    await _write('fonts/Fake.ttf', '.' * 8);
  });

  tearDownAll(() async {
    await fixtureDir.delete(recursive: true);
  });

  test('scanFindsAllKindsAndCounts', () {
    final summary = MpvProfileScanner.scan(fixtureDir.path);

    expect(summary.isValid, isTrue);
    expect(summary.scriptCount, 2); // scripts/a.lua + scripts/lib/b.js
    expect(summary.scriptOptCount, 1); // script-opts/foo.conf
    expect(summary.shaderCount, 1); // shaders/x.glsl
    expect(summary.fontCount, 1); // fonts/Fake.ttf
    // 4 conf files + 1 script-opt + 3 files under scripts/ + 1 shader + 1
    // font.
    expect(summary.files, hasLength(10));

    var sawDataBin = false;
    for (final file in summary.files) {
      expect(
          FileSystemEntity.isFileSync(
              p.join(summary.sourceDir, file.relativePath)),
          isTrue);
      expect(file.sizeBytes, greaterThan(0));
      if (file.relativePath == 'scripts/data.bin') {
        sawDataBin = true;
        expect(file.kind, 'other');
      }
    }
    expect(sawDataBin, isTrue);
    expect(
        summary.totalBytes,
        summary.files.fold<int>(0, (sum, f) => sum + f.sizeBytes));
  });

  test('scanMissingDirectoryIsInvalid', () {
    final summary =
        MpvProfileScanner.scan('/definitely/not/a/real/dir');
    expect(summary.isValid, isFalse);
    expect(summary.files, isEmpty);
  });

  test('scanEmptyDirectoryIsValidButContentless', () async {
    final dir = await Directory.systemTemp.createTemp('emoplay_empty_mpv_');
    try {
      final summary = MpvProfileScanner.scan(dir.path);

      expect(summary.isValid, isTrue);
      expect(summary.hasContent, isFalse);
      expect(summary.files, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('entryCountsComeFromParser', () {
    final summary = MpvProfileScanner.scan(fixtureDir.path);

    ImportFileSummary? findFile(String relPath) {
      for (final file in summary.files) {
        if (file.relativePath == relPath) {
          return file;
        }
      }
      return null;
    }

    // mpv.conf: 3 top-level options + 1 profile header + 2 profile options;
    // the profile section entries are counted too (they parse).
    expect(findFile('mpv.conf')!.kind, 'mpv-conf');
    expect(findFile('mpv.conf')!.entryCount, 6);
    // input.conf: 3 bindings.
    expect(findFile('input.conf')!.kind, 'input-conf');
    expect(findFile('input.conf')!.entryCount, 3);
    // profiles.conf: 2 headers + 3 option entries.
    expect(findFile('profiles.conf')!.kind, 'profiles-conf');
    expect(findFile('profiles.conf')!.entryCount, 5);
    expect(findFile('platform.conf')!.entryCount, 1);
    expect(findFile('script-opts/foo.conf')!.kind, 'script-opt');
    expect(findFile('script-opts/foo.conf')!.entryCount, 1);
    // Non-config files are counted but not parsed.
    expect(findFile('scripts/a.lua')!.kind, 'script');
    expect(findFile('scripts/a.lua')!.entryCount, 0);
    expect(findFile('fonts/Fake.ttf')!.kind, 'font');
  });

  test('locateXdgConfigHomeIsExclusiveWhenSet', () async {
    final home = await Directory.systemTemp.createTemp('emoplay_home_');
    final xdg = await Directory.systemTemp.createTemp('emoplay_xdg_');
    try {
      await Directory(p.join(home.path, '.config', 'mpv')).create(recursive: true);
      await Directory(p.join(xdg.path, 'mpv')).create(recursive: true);

      // mpv semantics (osdep/path-unix.c): when XDG_CONFIG_HOME is set it is
      // used EXCLUSIVELY -- ~/.config/mpv is never consulted, even when it
      // exists.
      expect(
          MpvProfileScanner.locateConfigDirIn(home.path, xdg.path, ''),
          p.join(xdg.path, 'mpv'));

      // XDG set but its mpv dir missing, and no legacy ~/.mpv: the home
      // candidate must NOT be returned (mpv would ignore it too).
      final xdgMissing =
          await Directory.systemTemp.createTemp('emoplay_xdg_missing_');
      try {
        expect(
            MpvProfileScanner.locateConfigDirIn(home.path, xdgMissing.path, ''),
            '');
      } finally {
        await xdgMissing.delete(recursive: true);
      }
    } finally {
      await home.delete(recursive: true);
      await xdg.delete(recursive: true);
    }
  });

  test('locateLegacyMpvUsedOnlyWhenPrimaryMissing', () async {
    final home = await Directory.systemTemp.createTemp('emoplay_home_');
    try {
      // No XDG, no ~/.config/mpv: the legacy ~/.mpv directory is the
      // fallback.
      await Directory(p.join(home.path, '.mpv')).create(recursive: true);
      expect(MpvProfileScanner.locateConfigDirIn(home.path, '', ''),
          p.join(home.path, '.mpv'));

      // mpv path-unix.c: legacy ~/.mpv only wins when the XDG dir does NOT
      // exist; with the XDG dir present the legacy directory is ignored.
      final xdg = await Directory.systemTemp.createTemp('emoplay_xdg_');
      try {
        await Directory(p.join(xdg.path, 'mpv')).create(recursive: true);
        expect(MpvProfileScanner.locateConfigDirIn(home.path, xdg.path, ''),
            p.join(xdg.path, 'mpv'));
      } finally {
        await xdg.delete(recursive: true);
      }
    } finally {
      await home.delete(recursive: true);
    }
  });

  test('locateReturnsEmptyWhenNothingExists', () async {
    final home = await Directory.systemTemp.createTemp('emoplay_home_');
    try {
      expect(MpvProfileScanner.locateConfigDirIn(home.path, '', ''), '');
    } finally {
      await home.delete(recursive: true);
    }
  });

  test('locateOnWindowsUsesAppData',
      skip: defaultTargetPlatform == TargetPlatform.windows
          ? false
          : 'Windows-only probe (1.x QSKIP contract)',
      () async {
    final appData = await Directory.systemTemp.createTemp('emoplay_appdata_');
    try {
      await Directory(p.join(appData.path, 'mpv')).create(recursive: true);
      expect(
          MpvProfileScanner.locateConfigDirIn('', '', appData.path),
          p.join(appData.path, 'mpv'));
    } finally {
      await appData.delete(recursive: true);
    }
  });

  test('summaryJsonRoundTrip', () {
    final original = MpvProfileScanner.scan(fixtureDir.path);
    expect(original.isValid, isTrue);

    final restored =
        ImportSummary.fromJsonMap(original.toJsonMap());

    expect(restored.sourceDir, original.sourceDir);
    expect(restored.scriptCount, original.scriptCount);
    expect(restored.scriptOptCount, original.scriptOptCount);
    expect(restored.shaderCount, original.shaderCount);
    expect(restored.fontCount, original.fontCount);
    expect(restored.totalBytes, original.totalBytes);
    expect(restored.files.length, original.files.length);
    for (var i = 0; i < original.files.length; i++) {
      expect(restored.files[i].kind, original.files[i].kind);
      expect(restored.files[i].relativePath, original.files[i].relativePath);
      expect(restored.files[i].sizeBytes, original.files[i].sizeBytes);
      expect(restored.files[i].entryCount, original.files[i].entryCount);
    }
  });
}
