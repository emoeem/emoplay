// M3-T1 进度条帧预览：第二 media_kit 解码实例（Haruna MpvPreview 语义移植）。
//
// 参考证据（read-only，2026-11-13 拉取）：
//   * Haruna src/mpv/mpvpreview.cpp:21-38 —— 预览实例属性集：vo=libmpv、
//     mute/pause、really-quiet、hwdec 跟随、hr-seek 跟随设置、aid=no、
//     audio-file-auto=no、sid=no、sub-auto=no、osd-level=0、
//     audio-pitch-correction=no、use-text-osd=no、audio-display=no。
//   * Haruna src/qml/HProgressBar.qml:48-61,144-170,226-252 —— 激活条件
//     （showPreviewThumbnail && file!=="" && playbackState!==Stopped &&
//     isLocalFile && isVideo）、hover 写 position、拖动中双 seek
//     （主实例 + 预览实例 commandAsync(["seek", value, "absolute"])）、
//     气泡文本「时间 - 章节标题」（titleAtPosition）。
//   * EmoPlay 落点的 mpv 通道考证沿用 lib/mpv/config/mpv_player_properties.dart
//     文件头（post-init setProperty 惯性、fork 预置 vid=no 等）。
//
// 与 Haruna 的差异及理由：
//   * vo=libmpv 不是手写的属性：Predidit fork（83b7ca6）的
//     NativeVideoController.create 在 attach 时写 vo=libmpv + vid=auto
//     （real.dart:150-156），而 fork 的 NativePlayer._create 预置 vid=no
//     （"prevent redundant video decoding"）——所以预览实例必须 attach 一个
//     VideoController 才有画面，Video widget 直接吃它的纹理（帧图）。
//   * really-quiet 转译为 PlayerConfiguration(logLevel: MPVLogLevel.error)：
//     fork 的 MPVLogLevel 枚举没有 none（最低 error），且 libmpv 无终端，
//     really-quiet 的「静默终端输出」意图即关日志事件。
//   * use-text-osd 不设：那是 Haruna 经 mpv render API 自绘 OSD 的开关，
//     EmoPlay 预览走 Video widget 纹理路径，无 OSD 渲染层可关。
//   * hr-seek 跟随 = 不单独设 hr-seek：主实例与预览实例的 seek 都走
//     media_kit 的 `seek <t> absolute`（real.dart Player.seek），bundled
//     libmpv 空闲核回读 hr-seek=yes（2026-11-13 实测 probe，绝对 seek 精确），
//     两侧零配置即一致。Haruna 的 accuratePreviewThumbnail 是独立 kcfg 项
//     （默认 false → hr-seek=no），EmoPlay 无对应设置键，按 ask 只落
//     「开关 + 预览宽度」两键，hr-seek 保持跟随主通道。
//   * demuxer-cache-dir 重定向到应用临时目录：fork 默认值在非 Linux 下
//     损坏（player_playback_controller.dart:345-351 同款注释），flutter_test
//     下亦不可写（chapters_live_test.dart 文件头）。
//
// 生效性实测（2026-11-13，临时 probe 跑毕即删）：bundled libmpv 空闲核上
// seekPreviewMpvProperties 全部被接受且回读逐项一致（mute=yes, pause=yes,
// aid=no, audio-file-auto=no, sid=no, sub-auto=no, osd-level=0,
// audio-pitch-correction=no, audio-display=no）；fork 预置 vid=no 与
// hr-seek=yes 亦同场确认（后者见下）。VideoController 纹理路径依赖
// VideoOutputManager 平台通道，flutter_test 无原生端，只能随 linux 构建的
// GUI 验收（SPEC §9「显示待人工验收」）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/utils/media.dart';

/// Haruna MpvPreview 属性集等价表（mpvpreview.cpp:21-38 → mpv 属性名，
/// 名称经 mpvproperties.h 解析）。单一代码通道：生产创建与测试断言共用。
///
/// pause/mute 关声画输出；aid/sid/sub-auto/audio-file-auto/audio-display
/// 关全部音轨字幕选择（预览只要帧）；osd-level=0 + audio-pitch-correction=no
/// 按 Haruna 原文；hwdec 与 hr-seek 不在此表（hwdec 走
/// VideoControllerConfiguration，hr-seek 跟随主通道，见文件头）。
const Map<String, String> seekPreviewMpvProperties = <String, String>{
  'mute': 'yes',
  'pause': 'yes',
  'aid': 'no',
  'audio-file-auto': 'no',
  'sid': 'no',
  'sub-auto': 'no',
  'osd-level': '0',
  'audio-pitch-correction': 'no',
  'audio-display': 'no',
};

/// 第二解码实例的一次构建参数。
class SeekPreviewEngineConfig {
  const SeekPreviewEngineConfig({
    required this.url,
    required this.hwdec,
  });

  /// 当前媒体地址（本地文件路径；激活门禁保证 isLocalFile）。
  final String url;

  /// 硬解跟随（主实例同款：hAenable ? hardwareDecoder : 'no'）。
  final String hwdec;
}

/// 预览实例的最小接口（测试缝）：生产实现是 media_kit
/// Player + VideoController 对；测试注入可数 fake（seek_preview_controller
/// 测试与 performance_guards 的「Player 实例数」守卫都经 [engineFactory]）。
abstract class SeekPreviewEngine {
  /// 气泡帧图的渲染面（Video widget 的 controller）；实例未就绪为 null。
  VideoController? get videoController;

  /// 帧宽高比（w/h），未报告前回落 2.0（Haruna HProgressBar.qml:148 的
  /// `property double aspectRatio: 2` 同款兜底）。
  double get aspectRatio;

  /// 绝对 seek（media_kit `seek <t> absolute`，即 Haruna onMoved 的命令）。
  Future<void> seek(Duration position);

  /// 隐藏即暂停（气泡收起后不再解码渲染）。
  Future<void> pause();

  Future<void> dispose();
}

/// 生产实现：真实 media_kit 第二实例。
class MediaKitSeekPreviewEngine implements SeekPreviewEngine {
  MediaKitSeekPreviewEngine._(this._player, this._videoController) {
    _widthSub = _player.stream.width.listen((value) => _width = value);
    _heightSub = _player.stream.height.listen((value) => _height = value);
    _errorSub = _player.stream.error.listen((event) {
      EmoLogger().w('SeekPreview: preview instance error', error: event);
    });
  }

  final Player _player;
  final VideoController _videoController;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  StreamSubscription<String>? _errorSub;
  int? _width;
  int? _height;

  @override
  VideoController? get videoController => _videoController;

  @override
  double get aspectRatio {
    final width = _width;
    final height = _height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 2.0;
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _errorSub?.cancel();
    try {
      await _player.dispose();
    } catch (e) {
      EmoLogger().w('SeekPreview: preview player dispose failed', error: e);
      try {
        await _player.stop();
      } catch (_) {}
    }
  }

  /// 创建第二实例：Player（Haruna 属性集 + 静默日志 + 缓存目录重定向）→
  /// VideoController（vo=libmpv + vid=auto + hwdec 跟随）→ open(play:false)
  /// （fork 的 open 恒先进 pause 态，play:false 不出暂停）。
  static Future<SeekPreviewEngine> create(SeekPreviewEngineConfig config) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        osc: false,
        logLevel: MPVLogLevel.error,
      ),
    );
    VideoController? controller;
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) {
        throw StateError('SeekPreview: native player required');
      }
      for (final entry in seekPreviewMpvProperties.entries) {
        await platform.setProperty(entry.key, entry.value);
      }
      await platform.setProperty('demuxer-cache-dir', await getPlayerTempPath());
      controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: config.hwdec != 'no',
          hwdec: config.hwdec,
        ),
      );
      await player.open(Media(config.url), play: false);
      return MediaKitSeekPreviewEngine._(player, controller);
    } catch (e) {
      EmoLogger().w('SeekPreview: failed to create preview instance', error: e);
      try {
        await player.dispose();
      } catch (_) {}
      rethrow;
    }
  }
}

/// 引擎工厂类型：生产 = [MediaKitSeekPreviewEngine.create]；测试注入 fake
/// 并计数（performance_guards_test.dart 的实例数守卫走这里）。
typedef SeekPreviewEngineFactory = Future<SeekPreviewEngine> Function(
    SeekPreviewEngineConfig config);

/// 帧预览控制器：激活门禁 + 实例生命周期 + 消抖 seek。
///
/// 激活门禁（Haruna HProgressBar.qml:150-157 的五条件等价）：
/// 设置开 && 文件非空 && isLocalFile && isVideo && 非停止。
/// 门禁惰性求值（每次 [previewAt]），设置关闭/门禁破缺时不再 seek；设置
/// 关闭额外立刻拆实例（handleSettingsChanged）。
///
/// 实例生命周期：首次门禁通过的 hover/拖动才建实例（懒创建，非 hover 不花
/// 一字节解码开销）；隐藏只 pause 不拆（Haruna Loader 的 active 语义）；
/// 换文件走 PlayerController._releasePlaybackResources → [reset]；dispose
/// 链见 [dispose]。
class SeekPreviewController extends ChangeNotifier {
  SeekPreviewController({
    required bool Function() enabled,
    required String Function() url,
    required bool Function() isLocalFile,
    required bool Function() isStopped,
    required String Function() hwdec,
    required int Function() previewWidth,
    SeekPreviewEngineFactory engineFactory = MediaKitSeekPreviewEngine.create,
    this.debounce = const Duration(milliseconds: 100),
  })  : _enabled = enabled,
        _url = url,
        _isLocalFile = isLocalFile,
        _isStopped = isStopped,
        _hwdec = hwdec,
        _previewWidth = previewWidth,
        _engineFactory = engineFactory;

  final bool Function() _enabled;
  final String Function() _url;
  final bool Function() _isLocalFile;
  final bool Function() _isStopped;
  final String Function() _hwdec;
  final int Function() _previewWidth;
  final SeekPreviewEngineFactory _engineFactory;

  /// 消抖窗口（测试注入短窗）；Haruna 对 position 写只有 qFuzzyCompare 去
  /// 重（mpvpreview.cpp:65-71），这里加尾随消抖是因为 media_kit 的 player
  /// 内部锁会串行化每次 seek，逐指针事件下发会在拖动中堆积。
  final Duration debounce;

  Timer? _seekTimer;
  Duration? _pendingPosition;
  SeekPreviewEngine? _engine;
  bool _creating = false;
  int _generation = 0;
  bool _disposed = false;

  /// 是否已按当前 URL 判定过 isVideo（classify 是 statSync，按 URL 缓存）。
  String? _classifiedUrl;
  bool _classifiedUrlIsVideo = false;

  /// 就绪的第二实例（气泡帧图的数据源）；未创建/创建中为 null。
  SeekPreviewEngine? get engine => _engine;

  /// 预览气泡宽度（逻辑像素，每次读取实时取——设置页改动即时生效）。
  int get bubbleWidth => _previewWidth();

  /// Haruna 五条件激活门禁。
  bool get shouldActivate =>
      !_disposed &&
      _enabled() &&
      _url().isNotEmpty &&
      _isLocalFile() &&
      _isVideo() &&
      !_isStopped();

  bool _isVideo() {
    final url = _url();
    if (url != _classifiedUrl) {
      _classifiedUrl = url;
      _classifiedUrlIsVideo =
          MediaClassifier.classify(url).kind == MediaKind.video;
    }
    return _classifiedUrlIsVideo;
  }

  /// hover / 拖动的预览位置请求：懒建实例 + 消抖 seek（尾随，取最后一次）。
  void previewAt(Duration position) {
    if (!shouldActivate) {
      return;
    }
    final engine = _engine;
    if (engine != null) {
      _pendingPosition = position;
      _scheduleSeek(engine);
      return;
    }
    _pendingPosition = position;
    _ensureInstance();
  }

  /// 气泡隐藏：取消挂起的 seek 并暂停实例（ask 契约「隐藏即 pause」）。
  void onHidden() {
    if (_disposed) {
      return;
    }
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingPosition = null;
    _engine?.pause().catchError((Object e) {
      EmoLogger().w('SeekPreview: pause on hide failed', error: e);
    });
  }

  /// 设置变更推送（PlayerItem 经 GStorage.watchSettings 转发）：开关关闭
  /// 立刻拆实例；其余（宽度变更）只触发气泡重建。
  void handleSettingsChanged() {
    if (_disposed) {
      return;
    }
    if (!_enabled()) {
      unawaited(reset());
      return;
    }
    notifyListeners();
  }

  /// 拆实例（换文件 / 设置关闭 / 释放）。幂等；创建中的实例由代计数守卫，
  /// 完成后立刻补拆。
  Future<void> reset() async {
    if (_disposed) {
      return;
    }
    _generation++;
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingPosition = null;
    _creating = false;
    final engine = _engine;
    _engine = null;
    _classifiedUrl = null;
    if (engine != null) {
      notifyListeners();
      await engine.dispose();
    }
  }

  /// dispose 链末端：reset + ChangeNotifier 释放。异步清理不阻塞调用方
  /// （与 PlayerController.beginShutdown 的不阻塞导航同风格）。
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingPosition = null;
    final engine = _engine;
    _engine = null;
    _creating = false;
    if (engine != null) {
      unawaited(engine.dispose().catchError((Object e) {
        EmoLogger().w('SeekPreview: engine dispose failed', error: e);
      }));
    }
    super.dispose();
  }

  void _scheduleSeek(SeekPreviewEngine engine) {
    _seekTimer?.cancel();
    _seekTimer = Timer(debounce, () {
      _seekTimer = null;
      final position = _pendingPosition;
      _pendingPosition = null;
      if (position == null || _engine != engine) {
        return;
      }
      engine.seek(position).catchError((Object e) {
        EmoLogger().w('SeekPreview: preview seek failed', error: e);
      });
    });
  }

  void _ensureInstance() {
    if (_creating || _engine != null || _disposed || !shouldActivate) {
      return;
    }
    _creating = true;
    final generation = _generation;
    final config = SeekPreviewEngineConfig(url: _url(), hwdec: _hwdec());
    unawaited(_engineFactory(config).then<void>((engine) {
      _creating = false;
      if (_disposed || generation != _generation) {
        // 创建期间被 reset/dispose 抢先：补拆，绝不留悬空实例。
        unawaited(engine.dispose().catchError((Object e) {
          EmoLogger().w('SeekPreview: stale engine dispose failed', error: e);
        }));
        return;
      }
      _engine = engine;
      notifyListeners();
      final pending = _pendingPosition;
      if (pending != null && shouldActivate) {
        _scheduleSeek(engine);
      }
    }).catchError((Object e) {
      _creating = false;
    }));
  }
}
