import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/services/player/external_playback_launcher.dart';
import 'package:emoplay/pages/player/controller/ab_loop_model.dart';
import 'package:emoplay/pages/player/controller/player_ab_loop_controller.dart';
import 'package:emoplay/pages/player/controller/player_chapters_controller.dart';
import 'package:emoplay/pages/player/controller/player_debug_controller.dart';
import 'package:emoplay/pages/player/controller/player_frame_step_controller.dart';
import 'package:emoplay/pages/player/controller/player_models.dart';
import 'package:emoplay/pages/player/controller/player_seek_controller.dart';
import 'package:emoplay/pages/player/controller/seek_preview_controller.dart';
import 'package:emoplay/pages/player/controller/player_subtitles_controller.dart';
import 'package:emoplay/pages/player/controller/player_aspect_ratio.dart';
import 'package:emoplay/pages/player/controller/player_panel_controller.dart';
import 'package:emoplay/pages/player/controller/player_playback_controller.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/pages/player/controller/player_screenshot_controller.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/shaders/shader_asset_service.dart';
import 'package:emoplay/services/player/audio_controller.dart';
import 'package:emoplay/utils/async_session.dart';
import 'package:emoplay/utils/device.dart';

export 'package:emoplay/pages/player/controller/player_models.dart';

class PlayerController implements Disposable {
  PlayerController(
    this.shaderAssetService,
    this.audioController,
  );

  final ShaderAssetService shaderAssetService;
  final AudioController audioController;
  final AsyncSessionOwner _initializations = AsyncSessionOwner();
  Future<void>? _shutdownFuture;
  final PlayerPanelController panel = PlayerPanelController();
  final PlayerScreenshotController screenshots = PlayerScreenshotController();
  final PlayerDebugController debug = PlayerDebugController();

  late final PlayerPlaybackController playback = PlayerPlaybackController(
    shaderAssetService: shaderAssetService,
    debug: debug,
    videoUrl: () => videoUrl,
    isLocalPlayback: () => isLocalPlayback,
  );
  late final PlayerSeekController seeking = PlayerSeekController(
    playback: playback,
    pause: pause,
    play: play,
    onSeekCompleted: _onSeekCompleted,
  );

  /// M3-T2 章节导航：mpv chapter-list/chapter 属性观察与章节跳转状态。
  late final PlayerChaptersController chapters = PlayerChaptersController(
    seek: seek,
    position: () => playback.currentPosition,
  );

  /// M3 字幕管理：track-list/sid 观察、外挂字幕 sub-add 命令面与 sub-delay
  /// 步进状态。
  late final PlayerSubtitlesController subtitles = PlayerSubtitlesController();

  /// M3 施工件 C「A-B 循环」：ab-loop-a/b 属性观察与设 A→设 B→清除三态命令面
  /// （位置取 playerPosition 的实时读取，秒）。
  late final PlayerAbLoopController abLoop = PlayerAbLoopController(
    position: () => playback.playerPosition.inMilliseconds / 1000.0,
  );

  /// M3 施工件 C「逐帧」：frame-step / frame-back-step 命令面。
  late final PlayerFrameStepController frameSteps = PlayerFrameStepController(
    platform: _nativePlatform,
  );

  /// M3-T1 进度条帧预览：第二 media_kit 解码实例的门禁/生命周期/消抖 seek
  /// 收口（Haruna 属性集等价，见 seek_preview_controller.dart 文件头）。
  /// 激活门禁的四个外部条件在此以 getter 注入：设置开关、isLocalPlayback、
  /// 「非停止」（duration>0 = 媒体已加载）、硬解跟随主实例同款表达式
  /// （player_playback_controller.dart VideoControllerConfiguration.hwdec）。
  late final SeekPreviewController seekPreview = SeekPreviewController(
    enabled: () => GStorage.getSetting(SettingsKeys.seekPreview),
    url: () => videoUrl,
    isLocalFile: () => isLocalPlayback,
    isStopped: () => playback.duration <= Duration.zero,
    hwdec: () {
      final hA = GStorage.getSetting(SettingsKeys.hAenable);
      return hA ? GStorage.getSetting(SettingsKeys.hardwareDecoder) : 'no';
    },
    previewWidth: () => GStorage.getSetting(SettingsKeys.seekPreviewWidth),
  );

  late final ExternalPlaybackLauncher externalPlayback =
      ExternalPlaybackLauncher(
    videoUrl: () => videoUrl,
  );

  Timer? _abLoopHudTimer;

  NativePlayer? _nativePlatform() {
    final player = playback.mediaPlayer;
    if (player == null) {
      return null;
    }
    final platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  late String referer = '';
  String? coverUrl;
  String videoUrl = '';
  String _episodeTitle = '';
  bool isLocalPlayback = false;
  Timer? hideVolumeUITimer;
  Timer? _volumeGestureSyncTimer;
  double? _pendingGestureVolume;

  bool muted = false;
  double _preMuteVolume = 100;

  Future<void> toggleMute() async {
    if (!muted && playback.volume > 0) {
      _preMuteVolume = playback.volume;
      muted = true;
      _persistMuteState();
      await setVolume(0);
    } else {
      muted = false;
      _persistMuteState();
      await setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  void _persistMuteState() {
    if (!isDesktop()) {
      return;
    }
    unawaited(GStorage.putSetting<bool>(SettingsKeys.playerMuted, muted));
  }

  /// 在音量被主动调高（手势 / 按键 / 滚轮）时退出静音状态。
  void _clearMuteIfNeeded(double value) {
    if (muted && value > 0) {
      muted = false;
      _persistMuteState();
    }
  }

  void setVolumeDuringGesture(double value) {
    _pendingGestureVolume = value.clamp(0.0, 100.0);
    playback.updateVolume(_pendingGestureVolume!);
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = Timer(const Duration(milliseconds: 80), () {
      final vol = _pendingGestureVolume;
      if (vol == null) {
        return;
      }
      unawaited(playback.syncVolumeToDevice(vol));
    });
  }

  Future<void> finishVolumeGesture() async {
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = null;
    final vol = _pendingGestureVolume;
    _pendingGestureVolume = null;
    if (vol != null) {
      playback.volume = vol;
    }
    playback.invalidatePreciseVolume();
    await playback.syncVolumeToDevice(vol);
    final resolved = vol ?? playback.volume;
    _clearMuteIfNeeded(resolved);
    _persistDesktopVolume(resolved);
  }

  void _persistDesktopVolume(double value) {
    if (!isDesktop()) {
      return;
    }
    if (muted) {
      return;
    }
    final clamped = value.clamp(0.0, 100.0);
    final stored = GStorage.getSetting(SettingsKeys.defaultVolume);
    if (stored.round() == clamped.round()) {
      return;
    }
    unawaited(GStorage.putSetting<double>(SettingsKeys.defaultVolume, clamped));
  }

  /// Human readable title of the currently loaded media.
  String get mediaTitle => _episodeTitle;

  Future<bool> init(PlaybackInitParams params) async {
    if (_initializations.isClosed) {
      return false;
    }
    final initialization = _initializations.begin();

    videoUrl = params.videoUrl;
    _episodeTitle = params.episodeTitle.trim();
    isLocalPlayback = params.isLocalPlayback;

    EmoLogger().i(
        'PlayerController: ${params.isLocalPlayback ? "local" : "online"} playback, url: ${params.videoUrl}');

    playback.resetForInit();
    debug.playerLogLevel = GStorage.getSetting(SettingsKeys.playerLogLevel);
    playback.playerSpeed = GStorage.getSetting(SettingsKeys.defaultPlaySpeed);
    panel.aspectRatioMode = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultAspectRatioType),
    );

    playback.buttonSkipTime = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    playback.arrowKeySkipTime =
        GStorage.getSetting(SettingsKeys.arrowKeySkipTime);
    try {
      await _releasePlaybackResources();
    } catch (_) {}
    if (initialization.isStale) {
      return false;
    }

    final Player? player;
    try {
      player = await playback.createVideoController(
        params.httpHeaders,
        canInstall: () => initialization.isActive,
        startAt: params.startAt,
      );
    } catch (e) {
      if (initialization.isStale) {
        return false;
      }
      playback.loading = false;
      EmoLogger()
          .e('PlayerController: failed to initialize video', error: e);
      return false;
    }
    if (player == null || !_ownsInitialization(initialization, player)) {
      return false;
    }

    // M3-T2 章节导航：挂上 chapter-list/chapter 观察（attach 自带幂等与
    // 失败降级；open 之后挂仍会收到 mpv 的初始观察事件）。
    await chapters.attach(player);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    // M3 字幕管理：挂 track-list 订阅与 sid/sub-delay 读取（同样 open 之后，
    // attach 内的 state 快照覆盖此前已派发的事件）。
    await subtitles.attach(player);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    // M3 施工件 C：挂 ab-loop-a/b 属性观察（换文件后循环区间不延续，mpv 在
    // 新文件的初始观察事件里报回 no，本地 marks 随之复位）。
    await abLoop.attach(player);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }

    if (isDesktop()) {
      final freshStart = playback.volume == -1;
      if (freshStart) {
        muted = GStorage.getSetting(SettingsKeys.playerMuted);
        final remembered = GStorage.getSetting(SettingsKeys.defaultVolume);
        _preMuteVolume = remembered > 0 ? remembered : 100;
        playback.volume = muted ? 0 : remembered;
      }
      await setVolume(playback.volume);
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    } else {
      await FlutterVolumeController.getVolume().then((value) {
        playback.volume = (value ?? 0.0) * 100;
      });
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }

      await FlutterVolumeController.updateShowSystemUI(false);
      if (!_ownsInitialization(initialization, player)) {
        await FlutterVolumeController.updateShowSystemUI(true);
        return false;
      }

      FlutterVolumeController.addListener((volume) {
        if (player == null || !_ownsInitialization(initialization, player)) {
          return;
        }
        if (panel.volumeSeeking) {
          return;
        }
        playback.applyExternalVolume(volume * 100);
        if (!Platform.isAndroid && !panel.volumeSeeking) {
          panel.showVolume = true;
          hideVolumeUITimer?.cancel();
          hideVolumeUITimer = Timer(const Duration(seconds: 1), () {
            panel.showVolume = false;
            hideVolumeUITimer = null;
          });
        }
      }, category: AudioSessionCategory.playback, emitOnStart: false);
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    }
    await setPlaybackSpeed(playback.playerSpeed);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    EmoLogger().i('PlayerController: video initialized');
    playback.loading = false;

    coverUrl = params.coverUrl;
    return true;
  }

  bool _ownsInitialization(AsyncSession initialization, Player player) {
    return initialization.isActive && playback.isCurrentPlayer(player);
  }

  /// Loads an external subtitle (srt/ass/ssa/vtt/sub) into the current media.
  ///
  /// Ported from mpv-emo `PlaybackController::addSubtitle`
  /// (src/mpv/PlaybackController.cpp:233). M3 字幕管理把命令面挪到了
  /// [PlayerSubtitlesController.loadExternal]（select/auto 标志、显式 title）；
  /// 本方法保持 1.x 语义（select，加载即启用）作为既有调用点
  /// （播放页选择器 / 拖放 planDrop）的稳定入口。
  Future<void> addSubtitle(String path) async {
    if (path.isEmpty) {
      return;
    }
    await subtitles.loadExternal(path);
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    await playback.setShader(
      mode,
      player: player,
    );
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    await playback.setPlaybackSpeed(playerSpeed);
  }

  Future<void> setVolume(double value) async {
    await playback.setVolume(value);
    _clearMuteIfNeeded(value);
    _persistDesktopVolume(value);
  }

  void syncPlaybackState() {
    playback.syncPlaybackState();
  }

  Future<void> playOrPause() async {
    await playback.playOrPause(pause: pause, play: play);
  }

  /// M3 施工件 C「A-B 循环」：跑一步三态循环（none→设 A→设 B→清除），并在
  /// 播放器顶部弹 HUD（PlayerAbLoopHud，1 秒自动隐藏，与其余调节浮层互斥）。
  ///
  /// 快捷键 L 与「更多选项」菜单入口共用本方法；无播放器时是安全空操作。
  Future<void> cycleAbLoop() async {
    final outcome = await abLoop.cycleAbLoop();
    if (outcome == null) {
      return;
    }
    _showAbLoopHud(outcome);
  }

  /// M3 施工件 C「A-B 循环」：显式清除（任意状态），同样走 HUD 反馈。
  Future<void> clearAbLoop() async {
    final outcome = await abLoop.clearAbLoop();
    if (outcome == null) {
      return;
    }
    _showAbLoopHud(outcome);
  }

  void _showAbLoopHud(AbLoopCycleOutcome outcome) {
    _abLoopHudTimer?.cancel();
    panel
      ..showVolume = false
      ..showBrightness = false
      ..showPlaySpeed = false
      ..showSubDelay = false
      ..abLoopHudText = outcome.message
      ..showAbLoop = true;
    _abLoopHudTimer = Timer(const Duration(seconds: 1), () {
      panel.showAbLoop = false;
      _abLoopHudTimer = null;
    });
  }

  /// M3 施工件 C「逐帧」：步进一帧（[direction] +1 前进 / -1 后退）。
  ///
  /// 播放中先暂停（mpv 的 frame-step 本身也会先暂停，先停可以保证本地
  /// playing 观察值与引擎一致，底部栏的逐帧按钮随之保持可见）；步进后立即
  /// 同步一次状态，让进度条与画面同步。无播放器时安全空操作。
  Future<void> frameStep(int direction) async {
    if (playback.playerPlaying) {
      await pause();
    }
    final issued = await frameSteps.stepBy(direction);
    if (!issued) {
      return;
    }
    playback.playing = false;
    syncPlaybackState();
  }

  Future<void> seek(Duration duration, {bool enableSync = true}) =>
      seeking.seekTo(duration, enableSync: enableSync);

  Future<void> seekBy(Duration offset, {bool enableSync = true}) =>
      seeking.seekBy(offset, enableSync: enableSync);

  Future<void> _onSeekCompleted(bool enableSync) async {}

  Future<void> pause({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    try {
      await player.pause();
    } catch (_) {
      return;
    }
    playback.playing = false;
  }

  Future<void> play({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    try {
      await player.play();
    } catch (_) {
      return;
    }
    playback.playing = true;
  }

  @override
  void dispose() {
    beginShutdown();
  }

  /// Starts the idempotent player shutdown without blocking route navigation.
  ///
  /// Native media and audio-session cleanup may finish after the route is
  /// removed. Immediate ownership detachment happens synchronously before this
  /// method returns.
  void beginShutdown() {
    _initializations.close();
    if (_shutdownFuture != null) {
      return;
    }
    screenshots.dispose();
    final shutdown = _shutdownResources();
    _shutdownFuture = shutdown;
    unawaited(
      shutdown.catchError((Object error, StackTrace stackTrace) {
        EmoLogger().e(
          'PlayerController: failed to dispose asynchronously',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  Future<void> _shutdownResources() async {
    await _releasePlaybackResources();
  }

  Future<void> _releasePlaybackResources() async {
    hideVolumeUITimer?.cancel();
    _volumeGestureSyncTimer?.cancel();
    _abLoopHudTimer?.cancel();
    _abLoopHudTimer = null;
    FlutterVolumeController.removeListener();
    // M3-T2：摘掉章节观察并清空章节状态（下一个文件 init 时重新挂）。
    await chapters.detach();
    // M3 字幕管理：同样摘掉 track-list/sid 订阅与 sub-delay 状态。
    await subtitles.detach();
    // M3 施工件 C：摘掉 ab-loop 观察并复位 marks（循环区间不跨文件）。
    await abLoop.detach();
    // M3-T1：帧预览第二实例随文件释放/收尾拆掉（换文件重开时按需重建）。
    await seekPreview.reset();
    await Future.wait([
      audioController.deactivate(),
      playback.stop(),
      _restoreSystemVolumeUi(),
    ]);
  }

  Future<void> _restoreSystemVolumeUi() async {
    try {
      await FlutterVolumeController.updateShowSystemUI(true);
    } catch (error, stackTrace) {
      EmoLogger().w(
        'PlayerController: failed to restore the system volume UI',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> stop() async {
    _initializations.cancel();
    await _releasePlaybackResources();
  }

  Future<Uint8List?> screenshotPng() => playback.screenshotPng();

  void setButtonForwardTime(int time) {
    playback.buttonSkipTime = time;
    GStorage.putSetting(SettingsKeys.buttonSkipTime, time);
  }

  void setArrowKeyForwardTime(int time) {
    playback.arrowKeySkipTime = time;
    GStorage.putSetting(SettingsKeys.arrowKeySkipTime, time);
  }

  Future<void> launchExternalPlayer() async {
    await externalPlayback.launch();
  }
}
