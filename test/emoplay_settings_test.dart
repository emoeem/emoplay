import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/music/music_queue.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

/// Headless tests for the persisted import decision + quality/behavior/music
/// sections (settings.json). The file path is injected per test; the
/// default-path case redirects the application-support resolution the same
/// way QStandardPaths test mode did in 1.x.
///
/// Case-for-case port of mpv-emo tests/test_app_settings.cpp; assertion
/// values are the behavioural contract and are copied verbatim.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-settings-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String file(String name) => '${tempDir.path}/$name';

  test('defaultPathIsSettingsJsonInAppData', () async {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() => PathProviderPlatform.instance = previous);

    final path = await EmoPlaySettings.defaultFilePath();
    expect(File(path).isAbsolute, isTrue);
    expect(path, endsWith('settings.json'));
    // Test mode redirects the app-support location away from the user's
    // real data (1.x asserted the ".qttest" marker).
    expect(path, contains(tempDir.path));
  });

  test('startsUndecided', () {
    final settings = EmoPlaySettings(file('undecided.json'));
    final loaded = settings.load();
    expect(loaded, isFalse); // nothing persisted yet
    expect(settings.importDecision, '');
    expect(settings.dontAskAgain, isFalse);
    expect(settings.selectedFiles, isEmpty);
  });

  test('decisionRoundTripsAcrossInstances', () {
    final path = file('decision.json');
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('full');
      expect(settings.save(), isTrue);
    }
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.importDecision, 'full');
      expect(settings.importedAt, isNotEmpty);
    }
    {
      // A second decision overwrites the first.
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      settings.setImportDecision('standalone');
      settings.dontAskAgain = true;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.importDecision, 'standalone');
    expect(settings.dontAskAgain, isTrue);
  });

  test('selectiveFileListRoundTrips', () async {
    final path = file('selective.json');
    final summary = <String, Object?>{
      'sourceDir': '/home/user/.config/mpv',
      'scriptCount': 2,
    };
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('selective');
      settings.selectedFiles = ['mpv.conf', 'scripts/a.lua'];
      settings.lastImportSummary = summary;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.importDecision, 'selective');
    expect(settings.selectedFiles, ['mpv.conf', 'scripts/a.lua']);
    expect(settings.lastImportSummary['scriptCount'], 2);
    expect(
        settings.lastImportSummary['sourceDir'], '/home/user/.config/mpv');
  });

  test('corruptFileResetsToDefaults', () async {
    final path = file('corrupt.json');
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('full');
      expect(settings.save(), isTrue);
    }
    expect(File(path).lengthSync() > 0, isTrue);
    await File(path).writeAsString('{ not valid json');

    final settings = EmoPlaySettings(path);
    expect(settings.load(), isFalse);
    expect(settings.importDecision, '');
    // Saving after corruption rewrites a valid document.
    settings.setImportDecision('skip');
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.importDecision, 'skip');
  });

  test('missingDirectoryIsCreatedOnSave', () {
    final path = file('nested/deeper/settings.json');
    final settings = EmoPlaySettings(path);
    settings.setImportDecision('full');
    expect(settings.save(), isTrue);
    expect(File(path).existsSync(), isTrue);
  });

  test('importDecisionTimestamped', () {
    final path = file('timestamp.json');
    final settings = EmoPlaySettings(path);
    expect(settings.importedAt, '');
    settings.setImportDecision('skip');
    expect(settings.importedAt, isNotEmpty);
    final parsed = DateTime.tryParse(settings.importedAt);
    expect(parsed, isNotNull);
    // Same decision again does not refresh the timestamp.
    final first = settings.importedAt;
    settings.setImportDecision('skip');
    expect(settings.importedAt, first);
  });

  test('qualityDefaultsWhenMissing', () {
    // A file written before P5 (no quality section) loads with defaults.
    final path = file('pre-quality.json');
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('full');
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.qualityContentMode, 'auto');
    expect(settings.qualityTier, 'off');
    expect(settings.qualityToneMapping, 'auto');
    expect(settings.qualityScaleOverride, '');
    expect(settings.qualityDebandMode, 'auto');
    expect(settings.manualShaderList, isEmpty);
  });

  test('qualitySectionRoundTrips', () {
    final path = file('quality.json');
    {
      final settings = EmoPlaySettings(path);
      settings.qualityContentMode = 'anime';
      settings.qualityTier = 'high';
      settings.qualityToneMapping = 'bt.2390';
      settings.qualityScaleOverride = 'bilinear';
      settings.qualityDebandMode = 'no';
      settings.manualShaderList = [
        '/mpv/shaders/Anime4K/Anime4K_Restore_CNN_M.glsl'
      ];
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.qualityContentMode, 'anime');
    expect(settings.qualityTier, 'high');
    expect(settings.qualityToneMapping, 'bt.2390');
    expect(settings.qualityScaleOverride, 'bilinear');
    expect(settings.qualityDebandMode, 'no');
    expect(settings.manualShaderList,
        ['/mpv/shaders/Anime4K/Anime4K_Restore_CNN_M.glsl']);

    // Change a value and verify it round-trips over the previous state.
    settings.qualityTier = 'off';
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.qualityTier, 'off');
    expect(reloaded.qualityContentMode, 'anime');
  });

  test('qualityCoexistsWithImportDecision', () {
    // The P4 import decision and the P5 quality section live in one
    // document; saving one must not lose the other.
    final path = file('combined.json');
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('selective');
      expect(settings.save(), isTrue);
    }
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      settings.qualityTier = 'medium';
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.importDecision, 'selective');
    expect(settings.qualityTier, 'medium');
    expect(settings.importedAt, isNotEmpty);
  });

  test('interpolationAndIccDefaultWhenMissing', () {
    // A quality section written before P5 v2 loads the new objects with
    // defaults.
    final path = file('pre-v2.json');
    {
      final settings = EmoPlaySettings(path);
      settings.qualityTier = 'low';
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.qualityInterpolationEnabled, isFalse);
    expect(settings.qualityInterpolationPreset, 'MEMC_RIFE_STD');
    expect(settings.qualityIccEnabled, isFalse);
    expect(settings.qualityIccProfilePath, '');
  });

  test('interpolationAndIccRoundTrip', () {
    final path = file('v2.json');
    {
      final settings = EmoPlaySettings(path);
      settings.qualityInterpolationEnabled = true;
      settings.qualityInterpolationPreset = 'MEMC_SVP_PRO';
      settings.qualityIccEnabled = true;
      settings.qualityIccProfilePath = '/home/user/icc/display.icc';
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.qualityInterpolationEnabled, isTrue);
    expect(settings.qualityInterpolationPreset, 'MEMC_SVP_PRO');
    expect(settings.qualityIccEnabled, isTrue);
    expect(settings.qualityIccProfilePath, '/home/user/icc/display.icc');

    // v1 quality fields and the P4 decision coexist in the same document.
    settings.qualityTier = 'medium';
    settings.setImportDecision('standalone');
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.qualityTier, 'medium');
    expect(reloaded.importDecision, 'standalone');
    expect(reloaded.qualityInterpolationPreset, 'MEMC_SVP_PRO');
    expect(reloaded.qualityIccProfilePath, '/home/user/icc/display.icc');
  });

  test('interpolationAndIccSurviveWrongTypes', () async {
    // Hand-edited files with wrong value types fall back to the defaults
    // instead of crashing or feeding garbage to the controllers.
    final path = file('wrong-types.json');
    await File(path).writeAsString('''
{
    "quality": {
        "interpolation": {"enabled": "yes-please", "preset": 42},
        "icc": {"enabled": [], "profilePath": {"a": 1}}
    }
}
''');
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.qualityInterpolationEnabled, isFalse);
    expect(settings.qualityInterpolationPreset, 'MEMC_RIFE_STD');
    expect(settings.qualityIccEnabled, isFalse);
    expect(settings.qualityIccProfilePath, '');
  });

  test('musicDefaultsWhenMissing', () {
    // A file written before P7 (no music section) loads with defaults.
    final path = file('pre-music.json');
    {
      final settings = EmoPlaySettings(path);
      settings.setImportDecision('full');
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.musicEqualizerEnabled, isFalse);
    expect(settings.musicEqualizerPreset, 'flat');
    expect(settings.musicEqualizerGains, isEmpty);
    expect(settings.importDecision, 'full');
  });

  test('musicSectionRoundTrips', () {
    final path = file('music.json');
    {
      final settings = EmoPlaySettings(path);
      settings.musicEqualizerEnabled = true;
      settings.musicEqualizerPreset = 'custom';
      settings.musicEqualizerGains = [1, 2, 3, 0, 0, -1, -2, 0, 4, 5];
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.musicEqualizerEnabled, isTrue);
    expect(settings.musicEqualizerPreset, 'custom');
    expect(settings.musicEqualizerGains, [1, 2, 3, 0, 0, -1, -2, 0, 4, 5]);

    // The music section coexists with the quality/import sections: change
    // one, verify the others survive the save/reload cycle.
    settings.qualityTier = 'high';
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.qualityTier, 'high');
    expect(reloaded.musicEqualizerPreset, 'custom');
    expect(reloaded.musicEqualizerEnabled, isTrue);
  });

  test('playlistModeDefaultsWhenMissing', () {
    // M5-T1 键追加契约（roadmap §四红线）：behavior 段写于 M5-T1 之前的
    // 文件（无 playlistMode 键）按默认 none 加载，且既有 behavior 字段
    // 不受影响。默认 none = 1.x/Kazumi 现状（原 PlaylistMode.none 硬编码）。
    final path = file('pre-m5t1.json');
    {
      final settings = EmoPlaySettings(path);
      settings.resumeOnReopen = false;
      settings.libraryMaxDepth = 3;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.playlistMode, QueueLoopMode.none);
    expect(settings.resumeOnReopen, isFalse);
    expect(settings.libraryMaxDepth, 3);
  });

  test('playlistModeRoundTrips', () {
    // 新键追加的往返用例：none → single → playlist 跨实例往返，并与
    // behavior 段既有字段在同一文档中共存。
    final path = file('playlist-mode.json');
    {
      final settings = EmoPlaySettings(path);
      expect(settings.playlistMode, QueueLoopMode.none); // 默认值
      settings.playlistMode = QueueLoopMode.single;
      expect(settings.save(), isTrue);
    }
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.playlistMode, QueueLoopMode.single);
      settings.playlistMode = QueueLoopMode.playlist;
      settings.librarySkipHidden = false;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.playlistMode, QueueLoopMode.playlist);
    expect(settings.librarySkipHidden, isFalse);
    // 再改回 none，确认三态都可写入并可读回。
    settings.playlistMode = QueueLoopMode.none;
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.playlistMode, QueueLoopMode.none);
  });

  test('playlistModeSurvivesWrongTypes', () async {
    // 手改文件：未知值与错误类型一律回落默认 none（QueueLoopMode
    // .fromStorageValue 契约），不崩溃、不喂垃圾给播放器。
    final path = file('playlist-mode-wrong-types.json');
    await File(path).writeAsString('''
{
    "behavior": {
        "resumeOnReopen": true,
        "playlistMode": 42
    }
}
''');
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.playlistMode, QueueLoopMode.none);

    await File(path).writeAsString('''
{
    "behavior": {"playlistMode": "bogus-mode"}
}
''');
    final settings2 = EmoPlaySettings(path);
    expect(settings2.load(), isTrue);
    expect(settings2.playlistMode, QueueLoopMode.none);
  });

  test('restoreDefaultsResetsPlaylistMode', () {
    // 恢复默认（behavior 段范围，施工件 B 扩展同款）也覆盖新键。
    final path = file('restore-playlist-mode.json');
    final settings = EmoPlaySettings(path);
    settings.playlistMode = QueueLoopMode.single;
    settings.restoreDefaults();
    expect(settings.playlistMode, QueueLoopMode.none);
  });

  test('audioReplaygainDefaultsWhenMissing', () {
    // M5-T2 键追加契约（roadmap §四红线）：audio 段写于 M5-T2 之前的文件
    // （无 audio 键）按默认 off 加载，且既有 music/behavior 字段不受影
    // 响。默认 off = 1.x 现状（1.x 从未写过 mpv replaygain 属性，grep
    // mpv-emo src/qml/mpv.md 零命中）。
    final path = file('pre-m5t2.json');
    {
      final settings = EmoPlaySettings(path);
      settings.musicEqualizerEnabled = true;
      settings.libraryMaxDepth = 4;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainOff);
    expect(settings.musicEqualizerEnabled, isTrue);
    expect(settings.libraryMaxDepth, 4);
  });

  test('audioSectionRoundTrips', () {
    // M5-T2 新段（settings.json `audio`）的往返用例：off → track → album
    // 跨实例往返，并与 music/behavior 段在同一文档中共存。
    final path = file('audio.json');
    {
      final settings = EmoPlaySettings(path);
      expect(
          settings.audioReplaygain, MpvPlayerProperties.replaygainOff); // 默认
      settings.audioReplaygain = MpvPlayerProperties.replaygainTrack;
      expect(settings.save(), isTrue);
    }
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.audioReplaygain, MpvPlayerProperties.replaygainTrack);
      settings.audioReplaygain = MpvPlayerProperties.replaygainAlbum;
      settings.librarySkipHidden = false;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainAlbum);
    expect(settings.librarySkipHidden, isFalse);
    // 再改回 off，确认三态都可写入并可读回。
    settings.audioReplaygain = MpvPlayerProperties.replaygainOff;
    expect(settings.save(), isTrue);
    final reloaded = EmoPlaySettings(path);
    expect(reloaded.load(), isTrue);
    expect(reloaded.audioReplaygain, MpvPlayerProperties.replaygainOff);
  });

  test('audioReplaygainSurvivesWrongTypes', () async {
    // 手改文件：未知值与错误类型一律回落默认 off（MpvPlayerProperties
    // .replaygainValues 白名单契约，与 QueueLoopMode.fromStorageValue 同
    // 型），不崩溃、绝不臆测一个增益档喂给播放器。
    final path = file('audio-wrong-types.json');
    await File(path).writeAsString('''
{
    "audio": {
        "replaygain": 42
    }
}
''');
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainOff);

    await File(path).writeAsString('''
{
    "audio": {"replaygain": "bogus-gain"}
}
''');
    final settings2 = EmoPlaySettings(path);
    expect(settings2.load(), isTrue);
    expect(settings2.audioReplaygain, MpvPlayerProperties.replaygainOff);

    // 守卫 setter 同契约：未知值不进内存、维持现值。
    settings2.audioReplaygain = 'bogus-gain';
    expect(settings2.audioReplaygain, MpvPlayerProperties.replaygainOff);
  });

  test('restoreDefaultsResetsAudioReplaygain', () {
    // 恢复默认（quality/behavior/music/audio 全段范围，施工件 B 扩展同款）
    // 也覆盖 M5-T2 新键。
    final path = file('restore-audio-replaygain.json');
    final settings = EmoPlaySettings(path);
    settings.audioReplaygain = MpvPlayerProperties.replaygainAlbum;
    settings.restoreDefaults();
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainOff);
  });

  test('behaviorSectionRoundTrips', () {
    final path = file('settings.json');
    {
      final settings = EmoPlaySettings(path);
      expect(settings.resumeOnReopen, isTrue);
      expect(settings.libraryMaxDepth, 2);
      expect(settings.librarySkipHidden, isTrue);

      settings.resumeOnReopen = false;
      settings.libraryMaxDepth = 3;
      settings.librarySkipHidden = false;
      expect(settings.save(), isTrue);
    }

    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.resumeOnReopen, isFalse);
      expect(settings.libraryMaxDepth, 3);
      expect(settings.librarySkipHidden, isFalse);

      // 0 means "unlimited"; negatives clamp instead of reaching the scan.
      settings.libraryMaxDepth = -5;
      expect(settings.libraryMaxDepth, 0);
    }

    // The behavior section must not disturb the existing sections.
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.importDecision, '');
      expect(settings.qualityTier, 'off');
    }
  });
}

/// QStandardPaths::setTestModeEnabled equivalent: redirects the
/// application-support resolution used by EmoPlaySettings.defaultFilePath().
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
