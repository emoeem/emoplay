// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/pending_resume_seek.dart';
import 'package:emoplay/pages/player/controller/player_debug_controller.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/services/shaders/shader_asset_service.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/network/proxy_utils.dart';
import 'package:emoplay/services/network/system_proxy_service.dart';
import 'package:emoplay/services/player/playback_cache_policy.dart';
import 'package:emoplay/services/player/player_error_mapper.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/music/music_controller.dart' show kPlaybackAfBaseline;
import 'package:emoplay/music/music_queue.dart';
import 'package:emoplay/utils/device.dart';
import 'package:emoplay/utils/media.dart';
import 'package:emoplay/services/platform/platform_environment_service.dart';

part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player);

  final Player player;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      EmoLogger().e(
        'PlayerPlaybackController: failed to dispose media player',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await player.stop();
      } catch (_) {}
    }
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
    required this.isLocalPlayback,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;
  final bool Function() isLocalPlayback;
  late final PlaybackCachePolicy cachePolicy = PlaybackCachePolicy(
    isLocalPlayback: isLocalPlayback,
    currentPlayer: () => mediaPlayer,
  );

  _OwnedPlayer? _ownedPlayer;
  Player? get mediaPlayer => _ownedPlayer?.player;
  VideoController? videoController;

  final AsyncSerialQueue _prefetchWrites = AsyncSerialQueue();
  bool _prefetchSuspendWanted = false;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool autoPlay = true;
  bool playerDebugMode = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  /// 历史记录传入的 offset
  int startOffset = 0;

  /// Deferred resume seek (SPEC §4.4): armed on open, consumed once by the
  /// first file-loaded signal. See [PendingResumeSeek] for the 1.x semantics.
  final PendingResumeSeek _resumeSeek = PendingResumeSeek();

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {}
  }

  @action
  void resetForInit() {
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    startOffset = 0;
    _resumeSeek.clear();
  }

  /// 本次会话是否从距结尾 [nearEndWatchedThreshold] 以内的位置起播。
  /// 这样的"播放完成"并非真正看完，应从头重播而非切下一集
  bool get resumedNearEnd {
    if (startOffset <= 0 || duration <= Duration.zero) {
      return false;
    }
    return Duration(seconds: startOffset) >= duration - nearEndWatchedThreshold;
  }

  /// 从头重播当前视频。[startOffset] 在重播落地后才归零，
  /// 避免自动连播在此期间抢先触发
  Future<void> restartFromBeginning() async {
    final player = mediaPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (!isCurrentPlayer(player)) {
        return;
      }
      await player.play();
      startOffset = 0;
    } catch (e) {
      EmoLogger()
          .w('PlayerController: failed to restart from beginning', error: e);
    }
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  /// Android blocks network access for backgrounded apps; a prefetching
  /// demuxer then burns through ffmpeg's reconnect/segment retries and marks
  /// the stream EOF, leaving playback permanently stuck once foregrounded.
  /// Suspending zeroes the readahead window so no new requests are issued
  /// while buffered data stays available; restore values are mpv defaults,
  /// which media_kit leaves untouched. Writes are serialized and apply the
  /// latest requested state, so rapid lifecycle flips cannot reorder.
  Future<void> setPrefetchSuspended(bool suspended) async {
    if (!Platform.isAndroid) {
      return;
    }
    _prefetchSuspendWanted = suspended;
    await _prefetchWrites.run(() async {
      final wanted = _prefetchSuspendWanted;
      final player = mediaPlayer;
      if (player == null) {
        return;
      }
      try {
        final pp = player.platform as NativePlayer;
        await pp.setProperty('cache-secs', wanted ? '0' : '36000');
        if (!isCurrentPlayer(player)) {
          return;
        }
        await pp.setProperty('demuxer-readahead-secs', wanted ? '0' : '1');
      } catch (e) {
        EmoLogger().w(
          'PlayerController: failed to ${wanted ? 'suspend' : 'resume'} demuxer prefetch',
          error: e,
        );
      }
    });
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders, {
    required bool Function() canInstall,
    double startAt = 0.0,
  }) async {
    // mpv-emo openAt(path, seconds): the resume position is recorded here and
    // seeked to once the file is loaded, never passed with the load command.
    startOffset = startAt.round();
    _resumeSeek.arm(startAt);
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES =
        GStorage.getSetting(SettingsKeys.androidEnableOpenSLES);
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = GStorage.getSetting(SettingsKeys.autoPlay);
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: cachePolicy.bufferSize,
          osc: false,
          logLevel: MPVLogLevel.values[debug.playerLogLevel],
        ),
      ),
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;
    cachePolicy.startWatching();

    try {
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      var pp = player.platform as NativePlayer;
      // M5 mpv 兼容层：在播放器专属细化之前应用预置属性（1.x 顺序：引擎
      // 内置默认 → compat 选项；下方播放器细化对同名键保持优先，例如
      // demuxer-cache-dir 指向 EmoPlay 自有的播放缓存目录，同样不写用户
      // mpv 目录）。预置在 MediaStores.init 组装一次：compat 选项 →
      // 插件 scripts 追加 → 播放器初始化；M5-T2 起音频属性（replaygain/
      // gapless-audio）随设置切换经 MediaStores.rebuildStartupMpvProperties
      // 重排，后续每个 Player 在此处拿到当前值。
      await MpvPlayerProperties.apply(
        pp,
        MediaStores.isReady
            ? MediaStores.instance.startupMpvProperties
            : const {},
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await cachePolicy.apply();
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      // 速度变速保音高基线（M7 音乐层共享常量：EQ 启用时按“基线 + 均衡器
      // 链”合成写入，见 music_controller.dart）。
      await pp.setProperty("af", kPlaybackAfBaseline);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles");
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
      if (proxyEnable) {
        final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
        final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
        if (formattedProxy != null) {
          await pp.setProperty("http-proxy", formattedProxy);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          EmoLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
        }
      } else if (SystemProxyService.isActive) {
        final proxy = SystemProxyService.proxyFor('https');
        if (proxy != null) {
          await pp.setProperty("http-proxy", 'http://${proxy.$1}:${proxy.$2}');
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          EmoLogger().i('Player: 跟随系统代理 http://${proxy.$1}:${proxy.$2}');
        }
      }

      await player.setAudioTrack(
        AudioTrack.auto(),
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer =
            GStorage.getSetting(SettingsKeys.androidVideoRenderer);

        if (androidVideoRenderer == 'auto') {
          // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
          // GPU-NEXT 需要 Vulkan 1.2 支持
          // 避免 Android 13 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
          final int androidSdkVersion =
              await PlatformEnvironmentService.getAndroidSdkVersion();
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          if (androidSdkVersion >= 34) {
            videoRenderer = 'gpu-next';
          } else {
            videoRenderer = 'gpu';
          }
        } else {
          videoRenderer = androidVideoRenderer;
        }
      }

      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          enableAndroidSurfaceProducer: false,
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      // M5-T1 循环模式：settings.json behavior.playlistMode（默认 none，即
      // 1.x 硬编码行为）驱动 media_kit PlaylistMode 原生通道。映射与「列表
      // 循环为何在应用层回卷」的考证见 [_playlistModeFor] 与
      // lib/music/music_queue.dart 文件头。
      await applyPlaylistMode(player: player);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      bool showPlayerError = GStorage.getSetting(SettingsKeys.showPlayerError);
      player.stream.error.listen((event) {
        if (isCurrentPlayer(player)) {
          final actionableMessage = PlayerErrorMapper.toActionableMessage(
            event,
            isBuffering: playerBuffering,
          );
          if (actionableMessage != null) {
            EmoDialog.showToast(
                message: actionableMessage, showActionButton: true);
          } else if (showPlayerError) {
            EmoDialog.showToast(
                message: '播放器内部错误 ${event.toString()} ${videoUrl()}',
                duration: const Duration(seconds: 5),
                showActionButton: true);
          }
        }
        EmoLogger().e('PlayerController: Player intent error ${videoUrl()}',
            error: event);
      });

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      // M6 画质引擎：把画质档位/插帧/ICC 三个控制器挂到本播放器上（1.x
      // 引擎常驻且 boot 时 startup()；2.0 每文件一个 player，首个 player
      // 触发一次性 startup()，见 quality_stores.dart）。挂接先于 open：
      // playlist 事件随后触发 fileLoaded 语义的重算。失败只记日志，绝不
      // 阻塞起播。注意 glsl-shaders 归属：一旦画质引擎挂接（含手动着色
      // 器表），change-list clr+append 由它接管；上方的 Kazumi 超分辨率
      // 仅在画质引擎 off 且未触碰着色器表时保持有效（1.x inert-at-off
      // 规则）。
      if (MediaStores.isReady) {
        await MediaStores.instance.quality.attachPlayer(player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        // M7 音乐层：音频模式检测 / .lrc 歌词 / EQ 挂到本播放器上，随后
        // 一次性 startup()（EQ 启用时在此挂链，先于 open）。失败只记日志，
        // 绝不阻塞起播。
        MediaStores.instance.diagnosticsPlayer = player;
        await MediaStores.instance.music.attachPlayer(player);
        await MediaStores.instance.music.startup();
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      // SPEC §4.4: no `start` on the media — the resume seek is issued after
      // the file is loaded (a seek sent earlier is dropped by mpv), consumed
      // exactly once by [_armResumeSeek].
      await player.open(
        Media(videoUrl(), httpHeaders: httpHeaders),
        play: autoPlay,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await _armResumeSeek(player);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      if (cachePolicy.networkAutomatic) {
        EmoDialog.showToast(message: '移动数据下已自动开启低内存模式，可在播放设置中改为始终关闭');
      }

      return player;
    } catch (error, stackTrace) {
      if (identical(_ownedPlayer, candidate)) {
        cachePolicy.stopWatching();
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Consumes the deferred resume seek on the first playback-time report.
  ///
  /// media_kit does not expose mpv's file-loaded event, so the closest
  /// post-file-loaded signal is used instead: mpv makes the `playback-time`
  /// property available only once a file is loaded and playback time exists,
  /// and observing it delivers the first value right at that point. The
  /// observer removes itself immediately after firing — a later file in the
  /// playlist must start from the beginning (one-shot, mpv-emo
  /// PlaybackController.cpp L264-268). Property values that are not available
  /// yet read back as null and never reach the listener
  /// (media_kit real.dart only dispatches when `readNativeString` != null).
  Future<void> _armResumeSeek(Player player) async {
    if (!_resumeSeek.hasPending) {
      return;
    }
    final NativePlayer? platform = player.platform is NativePlayer
        ? player.platform as NativePlayer
        : null;
    if (platform == null) {
      _resumeSeek.clear();
      return;
    }
    final pp = platform;
    try {
      await pp.observeProperty(
        'playback-time',
        (value) async {
          final target = _resumeSeek.consume();
          if (target == null) {
            return;
          }
          try {
            await pp.unobserveProperty(
              'playback-time',
              waitForInitialization: false,
            );
          } catch (_) {}
          if (!isCurrentPlayer(player)) {
            return;
          }
          try {
            await player.seek(Duration(milliseconds: (target * 1000).round()));
          } catch (e) {
            EmoLogger().w(
              'PlayerPlaybackController: resume seek failed',
              error: e,
            );
          }
        },
        waitForInitialization: false,
      );
    } catch (e) {
      EmoLogger().w(
        'PlayerPlaybackController: failed to arm resume seek',
        error: e,
      );
    }
  }

  /// M5-T1 循环模式：把持久化的 [QueueLoopMode] 经 media_kit 原生
  /// setPlaylistMode 通道下发到目标播放器。
  ///
  /// 两个调用点：[createVideoController]（每个 Player 创建时，原
  /// `PlaylistMode.none` 硬编码位）与播放面板/设置页的切换动线（对存活
  /// 的当前 Player 即时生效）。MediaStores 未就绪（测试/极早启动窗口）时
  /// 读到默认 none，行为与 1.x 硬编码一致。
  Future<void> applyPlaylistMode({Player? player}) async {
    final target = player ?? mediaPlayer;
    if (target == null) {
      return;
    }
    try {
      await target.setPlaylistMode(_playlistModeFor(currentLoopMode()));
    } catch (e) {
      EmoLogger().w('PlayerController: failed to set playlist mode', error: e);
    }
  }

  /// 当前持久化的循环模式（每次调用实时读设置，面板切换即时生效）。
  QueueLoopMode currentLoopMode() {
    if (MediaStores.isReady) {
      return MediaStores.instance.settings.playlistMode;
    }
    return QueueLoopMode.none;
  }

  /// QueueLoopMode → media_kit PlaylistMode 映射。
  ///
  ///  * none → [PlaylistMode.none]：loop-file/loop-playlist 均关，EOF 到达
  ///    应用层，队列按 autoPlayNext 推进、到队尾停止（1.x 行为）。
  ///  * single → [PlaylistMode.single]：引擎原生 loop-file=yes，文件由 mpv
  ///    自行重复，completed 永不触发、队列不前进（media_kit real.dart
  ///    setPlaylistMode 的属性映射，原样利用）。
  ///  * playlist → [PlaylistMode.none]（刻意不开 [PlaylistMode.loop]）：
  ///    media_kit `open(Media)` 只向 mpv 装载一个 entry 的内部 playlist
  ///    （real.dart open(): `playlist.add(playable)` → loadlist 临时文件），
  ///    `loop-playlist=yes` 会让 mpv 在文件结尾回卷到这唯一 entry、文件
  ///    自身无限循环，completed/eof 永远到不了应用层，队列无法续播。列表
  ///    循环的回卷由应用层实现：队列的 source of truth 是 PlaybackSession
  ///    （roadmap §四统一模型），每文件一个 Player 实例
  ///    （player_page.dart _loadCurrent），推进走
  ///    PlayerProgressPipeline → resolveQueueNextIndex（music_queue.dart）。
  PlaylistMode _playlistModeFor(QueueLoopMode mode) {
    return switch (mode) {
      QueueLoopMode.none => PlaylistMode.none,
      QueueLoopMode.single => PlaylistMode.single,
      QueueLoopMode.playlist => PlaylistMode.none,
    };
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      var pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      switch (mode) {
        case SuperResolutionMode.efficiency:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShadersLite,
            ),
          ]);
          break;
        case SuperResolutionMode.quality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShaders,
            ),
          ]);
          break;
        case SuperResolutionMode.off:
          await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
          break;
      }
      superResolutionMode = mode;
    } catch (e) {
      EmoLogger().w('PlayerController: failed to set shader', error: e);
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      EmoLogger()
          .e('PlayerController: failed to set playback speed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {}
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    if (currentPosition != state.position) {
      currentPosition = state.position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    if (completed != state.completed) {
      completed = state.completed;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    cachePolicy.stopWatching();
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    await Future.wait([
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]);
    // M6 画质引擎：本播放器已销毁，摘掉画质监听（设置与持久化状态保留，
    // 下一个播放器 attach 时恢复事件流）。M7 音乐层同样摘挂（音频模式/
    // 歌词/EQ 会话状态随引擎释放；EQ 持久化设置不动），诊断页也失去
    // mpv 属性来源。
    if (MediaStores.isReady) {
      MediaStores.instance.quality.detachPlayer();
      await MediaStores.instance.music.detachPlayer();
      MediaStores.instance.diagnosticsPlayer = null;
    }
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    // Encode the captured frame natively; PlayerState dimensions may be stale.
    return player.safeScreenshot(format: 'image/png');
  }
}
