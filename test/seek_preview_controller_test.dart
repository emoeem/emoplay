// M3-T1 进度条帧预览：SeekPreviewController 的门禁/消抖/生命周期用例
// （引擎经 SeekPreviewEngineFactory 注入可数 fake —— 测试缝与
// performance_guards_test.dart 的实例数守卫共用同一缝）。
//
// 激活门禁的 isVideo 半边用真实空文件驱动（MediaClassifier.classify 按
// statSync 后缀判定，fake 路径永远 missing）：clip.mp4 → video、song.mp3 →
// audio。libmpv 本体行为不在本文件（ask 的六个用例全是 fake 级）；Haruna
// 属性集以表断言锁住（seekPreviewMpvProperties）。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/pages/player/controller/seek_preview_controller.dart';
import 'package:emoplay/services/storage/storage.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeEngine implements SeekPreviewEngine {
  final List<Duration> seeks = <Duration>[];
  int pauses = 0;
  bool disposed = false;

  @override
  VideoController? get videoController => null;

  @override
  double get aspectRatio => 2.0;

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

SeekPreviewController _buildController({
  required String url,
  bool enabled = true,
  bool isLocalFile = true,
  bool isStopped = false,
  required List<_FakeEngine> created,
  Duration debounce = const Duration(milliseconds: 20),
  Future<void> Function(_FakeEngine)? onCreated,
}) {
  return SeekPreviewController(
    enabled: () => enabled,
    url: () => url,
    isLocalFile: () => isLocalFile,
    isStopped: () => isStopped,
    hwdec: () => 'auto-safe',
    previewWidth: () => 200,
    debounce: debounce,
    engineFactory: (config) async {
      final engine = _FakeEngine();
      created.add(engine);
      await onCreated?.call(engine);
      return engine;
    },
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late Directory tempDir;
  late String videoPath;
  late String audioPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-seek-preview-');
    // MediaClassifier 按 statSync + 后缀判定（lib/media/media_classifier.dart），
    // 空内容即可；引擎 fake 不真的 open。
    videoPath = '${tempDir.path}/clip.mp4';
    audioPath = '${tempDir.path}/song.mp3';
    await File(videoPath).writeAsString('');
    await File(audioPath).writeAsString('');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('seek preview controller', () {
    test('activationGateMatchesHarunaConditions', () async {
      // Haruna HProgressBar.qml:150-157：开关 && file!=="" && 非停止 &&
      // isLocalFile && isVideo。逐条件破缺验证。
      final baseline = <_FakeEngine>[];
      final baselineController = _buildController(
        url: videoPath,
        created: baseline,
      );
      baselineController.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => baseline.isNotEmpty);
      expect(baselineController.engine, same(baseline.single));
      baselineController.dispose();

      // 远端（isLocalFile=false）：不建实例。
      final remote = <_FakeEngine>[];
      final remoteController = _buildController(
        url: videoPath,
        isLocalFile: false,
        created: remote,
      );
      remoteController.previewAt(const Duration(seconds: 1));
      expect(remoteController.shouldActivate, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(remote, isEmpty);
      remoteController.dispose();

      // 音频文件（isVideo=false，经 classify 后缀表）：不建实例。
      final audio = <_FakeEngine>[];
      final audioController = _buildController(
        url: audioPath,
        created: audio,
      );
      audioController.previewAt(const Duration(seconds: 1));
      expect(audioController.shouldActivate, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(audio, isEmpty);
      audioController.dispose();

      // 停止态（无媒体，duration=0）：不建实例。
      final stopped = <_FakeEngine>[];
      final stoppedController = _buildController(
        url: videoPath,
        isStopped: true,
        created: stopped,
      );
      stoppedController.previewAt(const Duration(seconds: 1));
      expect(stoppedController.shouldActivate, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stopped, isEmpty);
      stoppedController.dispose();

      // 空文件地址：不建实例。
      final empty = <_FakeEngine>[];
      final emptyController = _buildController(url: '', created: empty);
      emptyController.previewAt(const Duration(seconds: 1));
      expect(emptyController.shouldActivate, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(empty, isEmpty);
      emptyController.dispose();
    });

    test('debouncedSeekUsesLatestPositionOnly', () async {
      final created = <_FakeEngine>[];
      final controller = _buildController(url: videoPath, created: created);
      addTearDown(controller.dispose);

      controller.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => created.isNotEmpty);
      await _pumpUntil(() => created.single.seeks.isNotEmpty);
      expect(created.single.seeks.single, const Duration(seconds: 1));

      // 消抖窗口内连续两次拖动/悬停：只发尾随位置的一次 seek。
      controller.previewAt(const Duration(seconds: 2));
      controller.previewAt(const Duration(seconds: 3));
      await _pumpUntil(() => created.single.seeks.length >= 2);
      expect(created.single.seeks, hasLength(2));
      expect(created.single.seeks.last, const Duration(seconds: 3));
    });

    test('hiddenPausesInstanceAndDropsPendingSeek', () async {
      final created = <_FakeEngine>[];
      final controller = _buildController(url: videoPath, created: created);
      addTearDown(controller.dispose);

      controller.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => created.single.seeks.isNotEmpty);
      controller.onHidden();
      await _pumpUntil(() => created.single.pauses > 0);
      expect(created.single.pauses, 1);

      // 隐藏后紧跟的 previewAt 挂起请求被丢弃：不 seek，且再次暂停。
      controller.previewAt(const Duration(seconds: 5));
      controller.onHidden();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(created.single.seeks, hasLength(1));
      expect(created.single.pauses, 2);
    });

    test('disabledSettingNeverCreatesInstance', () async {
      final created = <_FakeEngine>[];
      var enabled = false;

      // 直接以关闭态构造：previewAt 不建实例（性能守卫的另一半）。
      final offController = SeekPreviewController(
        enabled: () => enabled,
        url: () => videoPath,
        isLocalFile: () => true,
        isStopped: () => false,
        hwdec: () => 'auto-safe',
        previewWidth: () => 200,
        debounce: const Duration(milliseconds: 20),
        engineFactory: (config) async {
          final engine = _FakeEngine();
          created.add(engine);
          return engine;
        },
      );
      addTearDown(offController.dispose);
      offController.previewAt(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(created, isEmpty);
      expect(offController.engine, isNull);

      // 运行中关闭：先建实例，再经 handleSettingsChanged 拆掉。
      enabled = true;
      offController.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => created.isNotEmpty);
      final engine = created.single;
      expect(offController.engine, same(engine));
      enabled = false;
      offController.handleSettingsChanged();
      await _pumpUntil(() => engine.disposed);
      expect(offController.engine, isNull);
      // 关闭态再 hover：不新建实例。
      offController.previewAt(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(created, hasLength(1));
    });

    test('disposeChainReleasesEngineAndIgnoresLaterCalls', () async {
      final created = <_FakeEngine>[];
      final controller = _buildController(url: videoPath, created: created);

      controller.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => created.isNotEmpty);
      final engine = created.single;

      controller.dispose();
      await _pumpUntil(() => engine.disposed);
      expect(controller.engine, isNull);

      // dispose 之后再 hover：不建实例、不 seek、不抛（notifyListeners 守卫）。
      controller.previewAt(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(created, hasLength(1));
      expect(engine.seeks, isEmpty);
    });

    test('fileChangeResetDisposesAndRecreatesWithNewUrl', () async {
      final created = <_FakeEngine>[];
      var url = videoPath;
      final controller = SeekPreviewController(
        enabled: () => true,
        url: () => url,
        isLocalFile: () => true,
        isStopped: () => false,
        hwdec: () => 'auto-safe',
        previewWidth: () => 200,
        debounce: const Duration(milliseconds: 20),
        engineFactory: (config) async {
          final engine = _FakeEngine();
          created.add(engine);
          return engine;
        },
      );
      addTearDown(controller.dispose);

      controller.previewAt(const Duration(seconds: 1));
      await _pumpUntil(() => created.isNotEmpty);
      expect(created.single.disposed, isFalse);

      // 换文件：_releasePlaybackResources → reset 拆旧实例。
      await controller.reset();
      expect(created.single.disposed, isTrue);
      expect(controller.engine, isNull);

      // 新文件 hover：按新 URL 重建（配置带新地址）。
      url = '${tempDir.path}/next.mp4';
      await File(url).writeAsString('');
      controller.previewAt(const Duration(seconds: 2));
      await _pumpUntil(() => created.length >= 2);
      expect(created, hasLength(2));
      expect(created[1].disposed, isFalse);
    });

    test('gateBreakingMidCreationDisposesStaleEngine', () async {
      final created = <_FakeEngine>[];
      final gate = Completer<void>();
      final controller = _buildController(
        url: videoPath,
        created: created,
        onCreated: (_) => gate.future,
      );
      addTearDown(controller.dispose);

      controller.previewAt(const Duration(seconds: 1));
      // 工厂还挂着（onCreated 未完成）：创建中。
      await _pumpUntil(() => created.isNotEmpty);
      expect(controller.engine, isNull);

      // 创建期间 reset（换文件/设置关闭）：完成后补拆，绝不留悬空实例。
      await controller.reset();
      gate.complete();
      await _pumpUntil(() => created.single.disposed);
      expect(controller.engine, isNull);
    });

    test('harunaPropertySetCoversMpvPreviewTable', () {
      // Haruna mpvpreview.cpp:21-38 → mpv 属性名（mpvproperties.h 解析）。
      const required = <String, String>{
        'mute': 'yes',
        'pause': 'yes',
        'aid': 'no',
        'sid': 'no',
        'sub-auto': 'no',
        'osd-level': '0',
        'audio-display': 'no',
        // Haruna 原表同样携带的两项。
        'audio-file-auto': 'no',
        'audio-pitch-correction': 'no',
      };
      for (final entry in required.entries) {
        expect(
          seekPreviewMpvProperties[entry.key],
          entry.value,
          reason: 'seekPreviewMpvProperties[${entry.key}]',
        );
      }
      // hr-seek 有意缺席（跟随主实例 seek 通道，见控制器文件头）。
      expect(seekPreviewMpvProperties.containsKey('hr-seek'), isFalse);
    });
  });

  group('seek preview settings keys', () {
    setUpAll(() async {
      // audio_properties_settings_test.dart 的 Hive bootstrap 同款：
      // GStorage 落进临时根，绝不碰用户数据。
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final hiveRoot =
          await Directory.systemTemp.createTemp('emoplay-seek-preview-hive-');
      addTearDown(() {
        try {
          hiveRoot.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(hiveRoot.path);
      await binding.runAsync(() async {
        await Hive.initFlutter('${hiveRoot.path}/hive');
        await GStorage.init();
      });
    });

    test('defaultsAreOffAnd200px', () {
      expect(GStorage.getSetting<bool>(SettingsKeys.seekPreview), isFalse);
      expect(GStorage.getSetting<int>(SettingsKeys.seekPreviewWidth), 200);
    });

    test('keysRoundTripThroughStorage', () async {
      await GStorage.putSetting<bool>(SettingsKeys.seekPreview, true);
      await GStorage.putSetting<int>(SettingsKeys.seekPreviewWidth, 333);
      expect(GStorage.getSetting<bool>(SettingsKeys.seekPreview), isTrue);
      expect(GStorage.getSetting<int>(SettingsKeys.seekPreviewWidth), 333);

      // 恢复默认走 resetPlayerSettings（按键注册进 SettingsKeys.all）。
      await GStorage.resetPlayerSettings();
      expect(GStorage.getSetting<bool>(SettingsKeys.seekPreview), isFalse);
      expect(GStorage.getSetting<int>(SettingsKeys.seekPreviewWidth), 200);
    });
  });
}
