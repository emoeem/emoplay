import 'dart:async';
import 'dart:io';
import 'package:emoplay/pages/player/player_item_panel.dart';
import 'package:emoplay/pages/player/player_keyboard_shortcuts.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/pages/player/player_adjustment_hud.dart';
import 'package:emoplay/pages/player/music_lyrics_page.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:emoplay/pages/player/player_pointer_interaction.dart';
import 'package:emoplay/pages/player/player_gesture_detector.dart';
import 'package:emoplay/pages/player/player_seek_indicator.dart';
import 'package:emoplay/pages/player/player_screenshot_feedback_overlay.dart';
import 'package:emoplay/pages/player/player_screenshot_sheet.dart';
import 'package:emoplay/pages/player/controller/player_screenshot_controller.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/player/pip_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/video_details_sheet.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/pages/player/player_item_surface.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:emoplay/services/player/audio_controller.dart';
import 'package:emoplay/services/player/timed_shutdown_service.dart';
import 'package:emoplay/utils/device.dart';
import 'package:emoplay/services/platform/player_menu_service.dart';

/// The player surface: video, gestures, keyboard shortcuts, screenshots and
/// the control panel.
///
/// EmoPlay M1: the Kazumi danmaku/syncplay/bangumi-history integrations were
/// removed with the bangumi business layer (docs/STRIP-LIST.md §2); playback
/// state lives in [PlayerController], playlist and fullscreen flags in
/// [PlayerPageController].
class PlayerItem extends StatefulWidget {
  const PlayerItem({
    super.key,
    required this.playerController,
    required this.playerPageController,
    required this.fillsWindow,
    this.onToggleSidePanel,
    required this.onSelectItem,
    required this.onBackPressed,
    this.onLoadSubtitle,
    required this.keyboardFocus,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
  });

  final PlayerController playerController;
  final PlayerPageController playerPageController;
  final bool fillsWindow;
  final VoidCallback? onToggleSidePanel;

  /// Switches the player to the playlist entry at [index].
  final Future<void> Function(int index) onSelectItem;
  final VoidCallback onBackPressed;

  /// Opens the external-subtitle picker for the current media (M3 sub-add
  /// side-load; null hides the panel entry).
  final VoidCallback? onLoadSubtitle;
  final FocusNode keyboardFocus;
  final bool disableAnimations;
  final VoidCallback pauseForTimedShutdown;

  @override
  State<PlayerItem> createState() => _PlayerItemState();
}

class _PlayerItemState extends State<PlayerItem>
    with
        WindowListener,
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        EmoDialogOwner {
  late final PlayerController playerController;
  late final PlayerPageController playerPageController =
      widget.playerPageController;
  AudioController get _audioController => playerController.audioController;
  late final Map<String, PlayerShortcutAction> keyboardActions;
  late final Map<String, PlayerLongPressShortcutActions>
      keyboardLongPressActions;

  final _videoSurfaceKey = GlobalKey();

  late bool autoPlayNext;
  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;

  // Auto-hide delay in milliseconds.
  late int playerControllerLayerDisappearTime;

  Timer? hideTimer;
  Timer? playerTimer;
  Timer? mouseScrollerTimer;
  Timer? _adjustmentHudHideTimer;
  final Set<PlayerPanelHold> _playerPanelHolds = <PlayerPanelHold>{};
  int _openPlayerMenuCount = 0;
  PlayerPanelHold? _progressBarDragHold;
  PointerDeviceKind? _lastTapPointerKind;
  PointerDeviceKind? _lastDoubleTapPointerKind;
  double _lastDoubleTapDx = 0;

  /// True while a long press has switched to the temporary speed and the
  /// matching end/cancel must restore it (PiliPlus setLongPressStatus).
  bool _longPressSpeedEngaged = false;

  late final AnimationController _panelVisibilityController;
  late final AnimationController _screenshotFeedbackController;
  late final Animation<double> _screenshotFeedbackAnimation;
  late final PlayerScreenshotController _screenshots =
      playerController.screenshots;
  bool _screenshotSheetOpen = false;

  double lastPlayerSpeed = 1.0;
  late double longPressPlaySpeed;
  bool? _lastPipPlaying;
  Rect? _lastPipSourceRect;
  bool _pipSourceRectSyncScheduled = false;
  bool _pipEnterRequested = false;
  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleAndroidPIPSourceRectSync();
    _syncOrientationFullscreen();
  }

  /// PiliPlus auto-rotate fullscreen (controller.dart _onOrientationChanged):
  /// physically rotating a phone while playing enters fullscreen, rotating
  /// back leaves it. Idempotent against the programmatic rotation from
  /// [PlayerPageController.setFullscreen] — the flag flip and the metrics
  /// event settle in either order without re-triggering.
  void _syncOrientationFullscreen() {
    if (!mounted || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    if (playerPageController.isPip || playerController.panel.lockPanel) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || playerPageController.isPip) {
        return;
      }
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      if (landscape && !playerPageController.isFullscreen) {
        unawaited(playerPageController.setFullscreen(true));
      } else if (!landscape && playerPageController.isFullscreen) {
        unawaited(playerPageController.setFullscreen(false));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused && !backgroundPlayback) {
      // Suspend before awaiting pause so a later resume wins; pause alone keeps prefetching.
      final suspend = playerController.playback.setPrefetchSuspended(true);
      if (playerController.playback.mediaPlayer != null &&
          playerController.playback.playerPlaying) {
        try {
          await playerController.pause(enableSync: false);
        } catch (_) {}
      }
      await suspend;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      await playerController.playback.setPrefetchSuspended(false);
    }
  }

  Future<void> _syncAndroidAutoEnterPIPSetting() async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool autoEnterPIPEnabled =
        GStorage.getSetting(SettingsKeys.androidAutoEnterPIP);
    try {
      await PipUtils.setAndroidAutoEnterPIPEnabled(autoEnterPIPEnabled);
    } catch (e) {
      EmoLogger().w(
        'PlayerItem: failed to sync android auto enter pip setting',
        error: e,
      );
    }
  }

  Future<void> _syncAndroidPIPPlayerPageState(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await PipUtils.setAndroidPIPInPlayerPage(inPlayerPage);
    } catch (e) {
      EmoLogger().w(
        'PlayerItem: failed to sync android pip player page state',
        error: e,
      );
    }
  }

  Future<void> _updateAndroidPIPActions({bool force = false}) async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool playing = playerController.playback.playing;
    // In picture in picture the measured rect is the small window itself.
    final Rect? sourceRect = playerPageController.isPip
        ? _lastPipSourceRect
        : _androidPIPSourceRect();
    if (!force &&
        _lastPipPlaying == playing &&
        _lastPipSourceRect == sourceRect) {
      return;
    }

    _lastPipPlaying = playing;
    _lastPipSourceRect = sourceRect;
    await PipUtils.updateAndroidPIPActions(
      playing: playing,
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
      sourceRect: sourceRect,
    );
  }

  // Android PiP expects the letterboxed video bounds in physical pixels.
  Rect? _androidPIPSourceRect() {
    if (!mounted) {
      return null;
    }
    final renderObject = _videoSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final Size size = renderObject.size;
    if (size.isEmpty) {
      return null;
    }
    Rect rect = Offset.zero & size;
    final int videoWidth = playerController.debug.playerWidth;
    final int videoHeight = playerController.debug.playerHeight;
    if (videoWidth > 0 && videoHeight > 0) {
      final double scale =
          (rect.width / videoWidth) < (rect.height / videoHeight)
              ? rect.width / videoWidth
              : rect.height / videoHeight;
      rect = Rect.fromCenter(
        center: rect.center,
        width: videoWidth * scale,
        height: videoHeight * scale,
      );
    }
    // Convert the fitted video rectangle to window coordinates for native PiP.
    rect = MatrixUtils.transformRect(renderObject.getTransformTo(null), rect);
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return Rect.fromLTRB(
      rect.left * ratio,
      rect.top * ratio,
      rect.right * ratio,
      rect.bottom * ratio,
    );
  }

  // Remove controls before PiP entry to avoid rebuilding during the resize animation.
  Future<void> enterAndroidPictureInPicture() async {
    if (!Platform.isAndroid || !mounted) {
      return;
    }
    final bool supported = await PipUtils.isAndroidPIPSupported();
    if (!mounted) {
      return;
    }
    if (!supported) {
      EmoDialog.showToast(message: '当前设备不支持画中画');
      return;
    }
    setState(() {
      _pipEnterRequested = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    await _updateAndroidPIPActions(force: true);
    final bool entered = await PipUtils.enterAndroidPIPWindow(
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
    );
    if (entered || !mounted) {
      return;
    }
    EmoDialog.showToast(message: '进入画中画失败');
    setState(() {
      _pipEnterRequested = false;
    });
  }

  void _handleAndroidPIPModeChanged(bool inPipMode) {
    if (!mounted || playerPageController.isPip == inPipMode) {
      return;
    }
    setState(() {
      playerPageController.setPip(inPipMode);
    });
    if (!inPipMode) {
      _pipEnterRequested = false;
      _scheduleAndroidPIPSourceRectSync();
    }
  }

  void _scheduleAndroidPIPSourceRectSync() {
    if (!Platform.isAndroid || _pipSourceRectSyncScheduled) {
      return;
    }
    _pipSourceRectSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pipSourceRectSyncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(_updateAndroidPIPActions());
    });
  }

  Future<void> _syncPIPAspectWhenVideoSizeReady() async {
    if (playerController.debug.playerWidth <= 0 ||
        playerController.debug.playerHeight <= 0) {
      return;
    }
    if (Platform.isAndroid) {
      await _updateAndroidPIPActions(force: true);
      return;
    }
    if (isDesktop() && playerPageController.isPip) {
      await PipUtils.enterDesktopPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      );
    }
  }

  void _initKeyboardActions() {
    keyboardActions = {
      'playorpause': () => playerController.playOrPause(),
      'forward': handleShortcutForwardDown,
      'rewind': handleShortcutRewind,
      'next': () => handlePreNextItem('next'),
      'prev': () => handlePreNextItem('prev'),
      'volumeup': () => handleShortcutVolumeChange('up'),
      'volumedown': () => handleShortcutVolumeChange('down'),
      'togglemute': () => handleShortcutVolumeChange('mute'),
      'fullscreen': () => handleShortcutFullscreen(),
      'screenshot': handleScreenshot,
      'skip': skipOP,
      'exitfullscreen': () => handleShortcutExitFullscreen(),
      'speed1': () => setPlaybackSpeed(1.0),
      'speed2': () => setPlaybackSpeed(2.0),
      'speed3': () => setPlaybackSpeed(3.0),
      'speedup': () => handleSpeedChange('up'),
      'speeddown': () => handleSpeedChange('down'),
      // M3-T2 章节导航：无章节的文件上这两个动作是安全的空操作。
      'nextchapter': () => playerController.chapters.nextChapter(),
      'prevchapter': () => playerController.chapters.previousChapter(),
    };
    keyboardLongPressActions = {
      'forward': PlayerLongPressShortcutActions(
        onRepeat: handleShortcutForwardRepeat,
        onRelease: handleShortcutForwardUp,
      ),
      // PiliPlus player_focus.dart holds ArrowUp/ArrowDown to keep changing
      // the volume; the repeat rate is the system key-repeat rate.
      'volumeup': PlayerLongPressShortcutActions(
        onRepeat: () => handleShortcutVolumeChange('up'),
        onRelease: () {},
      ),
      'volumedown': PlayerLongPressShortcutActions(
        onRepeat: () => handleShortcutVolumeChange('down'),
        onRelease: () {},
      ),
    };
  }

  void _initPlayerMenu() {
    unawaited(PlayerMenuService.initialize(keyboardActions));
  }

  void _disposePlayerMenu() {
    unawaited(PlayerMenuService.dispose());
  }

  Future<void> handlePreNextItem(String direction) async {
    if (playerPageController.loading) return;
    final index = playerPageController.currentIndex;
    final length = playerPageController.playlist.length;
    int targetIndex;
    if (direction == 'next') {
      targetIndex = index + 1;
    } else if (direction == 'prev') {
      targetIndex = index - 1;
    } else {
      return;
    }

    if (targetIndex >= length) {
      EmoDialog.showToast(message: '已经是最后一个条目');
      return;
    }
    if (targetIndex < 0) {
      EmoDialog.showToast(message: '已经是第一个条目');
      return;
    }

    final target = playerPageController.itemAt(targetIndex);
    if (target != null) {
      EmoDialog.showToast(message: '正在加载${target.title}');
    }
    widget.onSelectItem(targetIndex);
  }

  Future<void> handleShortcutRewind() async {
    try {
      await _seekWithPlayerTimer(
        () => playerController.seekBy(
          Duration(seconds: -playerController.playback.arrowKeySkipTime),
        ),
      );
    } catch (e) {
      EmoLogger().e('PlayerController: seek failed', error: e);
    }
  }

  void handleShortcutForwardDown() {
    lastPlayerSpeed = playerController.playback.playerSpeed;
  }

  Future<void> handleShortcutForwardRepeat() async {
    final double defaultShortcutForwardPlaySpeed =
        GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);
    if (playerController.playback.playerSpeed <
        defaultShortcutForwardPlaySpeed) {
      playerController.panel.showPlaySpeed = true;
      await setPlaybackSpeed(defaultShortcutForwardPlaySpeed);
    }
  }

  Future<void> handleShortcutForwardUp() async {
    if (playerController.panel.showPlaySpeed) {
      playerController.panel.showPlaySpeed = false;
      await setPlaybackSpeed(lastPlayerSpeed);
    } else {
      try {
        await _seekWithPlayerTimer(
          () => playerController.seekBy(
            Duration(seconds: playerController.playback.arrowKeySkipTime),
          ),
        );
      } catch (e) {
        EmoLogger().e('PlayerController: seek failed', error: e);
      }
    }
  }

  void handleShortcutFullscreen() {
    if (!playerPageController.isPip) handleFullscreen();
  }

  /// ESC 优先级链（1.x qml/Main.qml:93 handleEscape）：对话框 → 播放器面板
  /// → 全屏 → 应用。M2 分层落地：
  /// - 对话框：Flutter 的 ModalRoute 自带 ESC 关闭；对话框打开时本快捷键层
  ///   被 `route.isCurrent` 守卫跳过，事件交还给对话框。
  /// - 播放器面板：音轨/播放列表面板未接线（SPEC §5 后续阶段），接入后应
  ///   在全屏之前先关面板（1.x PlayerPage.closeTopPanel）。
  /// - 全屏：退出窗口全屏。
  /// - 应用兜底：Kazumi 行为（桌面暂停并隐藏窗口）。
  void handleShortcutExitFullscreen() {
    if (playerPageController.isFullscreen) {
      unawaited(playerPageController.setFullscreen(false));
    } else if (isDesktop() && !Platform.isMacOS) {
      playerController.pause();
      windowManager.hide();
    }
  }

  void _toggleVideoController() {
    if (playerController.panel.showVideoController) {
      hideVideoController();
    } else {
      showVideoController();
    }
  }

  void _handleTap(PointerDeviceKind? pointerKind) {
    if (shouldToggleControllerOnPrimaryTap(
      isDesktop: isDesktop(),
      pointerKind: pointerKind,
    )) {
      _toggleVideoController();
      return;
    }
    playerController.playOrPause();
  }

  void _handleDoubleTap(PointerDeviceKind? pointerKind, double dx) {
    if (shouldToggleFullscreenOnDoubleTap(
      isDesktop: isDesktop(),
      isPip: playerPageController.isPip,
      pointerKind: pointerKind,
    )) {
      handleFullscreen();
      return;
    }
    // PiliPlus onDoubleTapDownMobile: touch double-taps are zoned — the left
    // quarter mounts the backward seek overlay, the right quarter the forward
    // one, the middle half toggles playback.
    final width = MediaQuery.sizeOf(context).width;
    switch (playerDoubleTapZoneFor(dx, width)) {
      case PlayerDoubleTapZone.backward:
        playerController.panel.showSeekBackwardOverlay = true;
        playerController.panel.showSeekForwardOverlay = false;
      case PlayerDoubleTapZone.forward:
        playerController.panel.showSeekBackwardOverlay = false;
        playerController.panel.showSeekForwardOverlay = true;
      case PlayerDoubleTapZone.center:
        _handleDoubleTapCenter();
    }
  }

  /// PiliPlus onDoubleTapCenter: restart from the beginning once completed,
  /// otherwise toggle playback.
  void _handleDoubleTapCenter() {
    if (playerController.playback.completed) {
      unawaited(playerController.playback.restartFromBeginning());
    } else {
      playerController.playOrPause();
    }
  }

  /// Applies the accumulated double-tap seek exactly once when the overlay's
  /// idle timer fires (PiliPlus onForward/onBackward).
  Future<void> _handleSeekOverlaySubmitted(Duration duration) async {
    playerController.panel.showSeekBackwardOverlay = false;
    playerController.panel.showSeekForwardOverlay = false;
    await _seekWithPlayerTimer(() => playerController.seekBy(duration));
  }

  void _handleMouseScroller() {
    playerController.panel.showVolume = true;
    mouseScrollerTimer?.cancel();
    mouseScrollerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        playerController.panel.showVolume = false;
      }
      mouseScrollerTimer = null;
    });
  }

  void _cancelAdjustmentHudHideTimer() {
    _adjustmentHudHideTimer?.cancel();
    _adjustmentHudHideTimer = null;
  }

  void _showVolumeAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showBrightness = false;
    playerController.panel.showVolume = true;
  }

  void _showBrightnessAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showVolume = false;
    playerController.panel.showBrightness = true;
  }

  void _scheduleAdjustmentHudHide({
    Duration delay = const Duration(milliseconds: 650),
  }) {
    _cancelAdjustmentHudHideTimer();
    _adjustmentHudHideTimer = Timer(delay, () {
      if (mounted) {
        playerController.panel.showVolume = false;
        playerController.panel.showBrightness = false;
      }
      _adjustmentHudHideTimer = null;
    });
  }

  void _finishAdjustmentGesture() {
    if (!brightnessVolumeGesture) {
      return;
    }
    if (playerController.panel.volumeSeeking) {
      playerController.panel.volumeSeeking = false;
      unawaited(playerController.finishVolumeGesture());
    }
    if (playerController.panel.brightnessSeeking) {
      playerController.panel.brightnessSeeking = false;
    }
    _scheduleAdjustmentHudHide();
  }

  Future<void> skipOP() async {
    await playerController.seekBy(
      Duration(seconds: playerController.playback.buttonSkipTime),
    );
  }

  Future<void> _bindAudioService() async {
    try {
      await _audioController.bindCallbacks(
        onPlay: () => playerController.play(),
        onPause: () => playerController.pause(),
        onSkipToNext: () => handlePreNextItem('next'),
        onSkipToPrevious: () => handlePreNextItem('prev'),
        onSeek: (position) => playerController.seek(position),
        artworkUrl: null,
      );
      _syncAudioServiceState();
    } catch (e) {
      EmoLogger().w('AudioController: failed to bind callbacks', error: e);
    }
  }

  void _syncAudioServiceState() {
    try {
      final index = playerPageController.currentIndex;
      final length = playerPageController.playlist.length;
      final item = playerPageController.currentItem;
      if (item == null || index < 0) {
        return;
      }

      if (playerController.playback.duration <= Duration.zero) return;

      final canSkipToPrevious = index > 0;
      final canSkipToNext = index < length - 1;

      unawaited(
        _audioController.updateSession(
          mediaId: item.path,
          title: item.title,
          album: '',
          artist: '',
          duration: playerController.playback.duration,
          playing: playerController.playback.playing,
          loading: playerController.playback.loading,
          buffering: playerController.playback.isBuffering,
          completed: playerController.playback.completed,
          updatePosition: playerController.playback.currentPosition,
          bufferedPosition: playerController.playback.buffer,
          speed: playerController.playback.playerSpeed,
          queueIndex: index,
          canSkipToNext: canSkipToNext,
          canSkipToPrevious: canSkipToPrevious,
        ),
      );
    } catch (e) {
      EmoLogger()
          .w('AudioController: failed to sync playback state', error: e);
    }
  }

  void _handleFullscreenChange() {
    playerController.panel.lockPanel = false;
    _releasePlayerPanelHolds();
    _scheduleAndroidPIPSourceRectSync();
  }

  void handleProgressBarDragStart() {
    _beginInteractiveSeek();
    _syncAudioServiceState();
    _progressBarDragHold = acquirePlayerPanelHold();
  }

  void handleProgressBarDragEnd(bool cancelled) {
    unawaited(_finishInteractiveSeek(cancelled: cancelled));
  }

  void _beginInteractiveSeek() {
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    playerTimer?.cancel();
    playerController.seeking.beginInteractiveSeek();
  }

  Future<void> _finishInteractiveSeek({bool cancelled = false}) async {
    var completed = false;
    try {
      completed = await playerController.seeking
          .finishInteractiveSeek(cancelled: cancelled);
    } catch (e) {
      EmoLogger().e('PlayerController: interactive seek failed', error: e);
    }
    if (!mounted ||
        (!completed && playerController.seeking.hasActiveInteractiveSeek)) {
      return;
    }
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    if (completed) {
      _syncAudioServiceState();
    }
    _restartPlayerTimer();
  }

  void _restartPlayerTimer() {
    playerTimer?.cancel();
    playerTimer = getPlayerTimer();
  }

  Future<void> _seekWithPlayerTimer(
    Future<void> Function() seekAction,
  ) async {
    playerTimer?.cancel();
    try {
      await seekAction();
    } finally {
      if (mounted) {
        _restartPlayerTimer();
      }
    }
  }

  Future<void> handleScreenshot() async {
    if (!mounted) return;
    if (!isDesktop()) {
      await _saveScreenshotToGallery();
      return;
    }
    if (_screenshots.busy || _screenshotSheetOpen) return;
    final item = playerPageController.currentItem;
    final source = playerPageController.src;
    final player = playerController.playback.mediaPlayer;
    if (playerPageController.loading || player == null) {
      EmoDialog.showToast(message: '暂未获取到画面，请等视频显示后重试');
      return;
    }
    final added = await _screenshots.capture(
      capturePng: playerController.screenshotPng,
      title: playerPageController.title,
      episode: item?.title ?? '',
      position: player.state.position,
      isCurrent: () =>
          mounted &&
          !playerPageController.loading &&
          playerPageController.src == source &&
          identical(playerController.playback.mediaPlayer, player),
    );
    if (!mounted) return;
    if (added) _playScreenshotFeedback();
    if (!_screenshotSheetOpen) {
      showVideoController();
      if (!added || _screenshots.candidates.length == 1) {
        EmoDialog.showToast(
          message: added
              ? '已截取画面，点击右上角图库挑选保存'
              : _screenshots.message ?? '截图失败，请重试',
          showActionButton: _screenshots.candidates.isNotEmpty,
          actionLabel: '挑选截图',
          onActionPressed: showScreenshotCandidates,
        );
      }
    }
  }

  Future<void> _saveScreenshotToGallery() async {
    _playScreenshotFeedback();
    try {
      final screenshot = await playerController.screenshotPng();
      if (!mounted) return;
      if (screenshot == null || screenshot.isEmpty) {
        EmoDialog.showToast(message: '截图失败：未获取到图像');
        return;
      }
      final result = await SaverGallery.saveImage(
        screenshot,
        fileName: DateTime.timestamp().millisecondsSinceEpoch.toString(),
        extension: 'png',
        skipIfExists: false,
      );
      if (mounted && !result.isSuccess) {
        EmoDialog.showToast(message: '截图保存失败：${result.errorMessage}');
      }
    } catch (e) {
      if (mounted) EmoDialog.showToast(message: '截图失败：$e');
    }
  }

  Future<void> showScreenshotCandidates() async {
    if (!isDesktop() || !mounted || _screenshotSheetOpen || _screenshots.busy) {
      return;
    }
    _screenshotSheetOpen = true;
    final hold = acquirePlayerPanelHold();
    final player = playerController.playback.mediaPlayer;
    final item = playerPageController.currentItem;
    final source = playerPageController.src;
    final resume = playerController.playback.playing;
    final sleepRemaining = TimedShutdownService().remainingSecondsNotifier.value;
    final sleepDeadline = sleepRemaining > 0
        ? DateTime.now().add(Duration(seconds: sleepRemaining))
        : null;
    try {
      if (resume) await playerController.pause(enableSync: false);
      if (!mounted) return;
      await showPlayerScreenshotSheet(context, controller: _screenshots);
    } finally {
      _screenshotSheetOpen = false;
      if (mounted) {
        hold.release();
        widget.keyboardFocus.requestFocus();
        // Resume only the same local playback, respecting the sleep timer.
        if (resume &&
            identical(player, playerController.playback.mediaPlayer) &&
            playerPageController.src == source &&
            playerPageController.currentItem == item &&
            !playerPageController.loading &&
            (sleepDeadline == null || DateTime.now().isBefore(sleepDeadline)) &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
            (ModalRoute.of(context)?.isCurrent ?? false)) {
          await playerController.play(enableSync: false);
        }
      } else {
        hold.releaseSilently();
      }
    }
  }

  void _playScreenshotFeedback() {
    if (!mounted ||
        widget.disableAnimations ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _screenshotFeedbackController.forward(from: 0);
  }

  Future<void> handleSuperResolutionChange(SuperResolutionMode mode) async {
    if (!mounted) return;

    // The mediacodec_embed renderer cannot apply super-resolution shaders.
    if (Platform.isAndroid && mode != SuperResolutionMode.off) {
      final String androidVideoRenderer =
          GStorage.getSetting(SettingsKeys.androidVideoRenderer);

      if (androidVideoRenderer == 'mediacodec_embed') {
        await EmoDialog.show(builder: (context) {
          return AlertDialog(
            title: const Text('兼容性提示'),
            content: const Text('MediaCodec 渲染器不支持超分辨率功能。\n\n'
                '如需使用超分辨率，请在播放设置中将视频渲染器切换为 gpu 或 gpu-next。'),
            actions: [
              TextButton(
                onPressed: () {
                  EmoDialog.dismiss(context: context);
                },
                child: const Text('确定'),
              ),
            ],
          );
        });
        return;
      }
    }

    final bool requiresPerformanceWarning = mode == SuperResolutionMode.quality;
    final bool warningDisabled = GStorage.getSetting(
      SettingsKeys.disableSuperResolutionWarning,
    );

    if (requiresPerformanceWarning && !warningDisabled) {
      bool confirmed = false;

      await EmoDialog.show(builder: (context) {
        bool dontAskAgain = false;

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('性能提示'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: dontAskAgain,
                      onChanged: (value) =>
                          setState(() => dontAskAgain = value ?? false),
                    ),
                    const Text('下次不再询问'),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (dontAskAgain) {
                    await GStorage.putSetting(
                      SettingsKeys.disableSuperResolutionWarning,
                      true,
                    );
                  }
                  if (!context.mounted) return;
                  EmoDialog.dismiss(context: context);
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  confirmed = true;
                  if (dontAskAgain) {
                    await GStorage.putSetting(
                      SettingsKeys.disableSuperResolutionWarning,
                      true,
                    );
                  }
                  if (!context.mounted) return;
                  EmoDialog.dismiss(context: context);
                },
                child: const Text('确认'),
              ),
            ],
          );
        });
      });

      if (confirmed && mounted) {
        playerController.setShader(mode);
      }
    } else {
      playerController.setShader(mode);
    }
  }

  void handleFullscreen() {
    if (!playerPageController.isPip) {
      unawaited(playerPageController.toggleFullscreen());
    }
  }

  void _finishLongPressSpeed() {
    if (!_longPressSpeedEngaged) {
      return;
    }
    setState(() {
      _longPressSpeedEngaged = false;
      playerController.panel.showPlaySpeed = false;
    });
    setPlaybackSpeed(lastPlayerSpeed);
  }

  bool get _canHidePlayerPanel =>
      playerController.panel.canHidePlayerPanel && _playerPanelHolds.isEmpty;

  void showVideoController({bool restartHideTimer = true}) {
    // Re-forwarding restarts the ticker and stalls a frame, so hover must not.
    if (!_panelVisibilityController.isForwardOrCompleted) {
      _panelVisibilityController.forward();
    }
    playerController.panel.showVideoController = true;
    if (restartHideTimer && _canHidePlayerPanel) {
      _startHideTimer();
    }
  }

  void hideVideoController() {
    if (!_canHidePlayerPanel) {
      return;
    }
    _panelVisibilityController.reverse();
    _cancelHideTimer();
    playerController.panel.showVideoController = false;
  }

  PlayerPanelHold acquirePlayerPanelHold() {
    late final PlayerPanelHold hold;
    hold = PlayerPanelHold(
      onRelease: () {
        _playerPanelHolds.remove(hold);
        if (_playerPanelHolds.isNotEmpty) {
          return;
        }
        playerController.panel.canHidePlayerPanel = true;
        _startHideTimer();
      },
    );
    _playerPanelHolds.add(hold);
    playerController.panel.canHidePlayerPanel = false;
    _cancelHideTimer();
    showVideoController(restartHideTimer: false);
    return hold;
  }

  void _handlePlayerMenuVisibilityChanged(bool isOpen) {
    if (isOpen) {
      _openPlayerMenuCount++;
    } else if (_openPlayerMenuCount > 0) {
      _openPlayerMenuCount--;
    }
  }

  // Fullscreen and system overlays can dispose controls before their holds are released.
  void _releasePlayerPanelHolds() {
    for (final hold in _playerPanelHolds.toList()) {
      hold.releaseSilently();
    }
    _playerPanelHolds.clear();
    _progressBarDragHold = null;
    playerController.panel.canHidePlayerPanel = true;
    _startHideTimer();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await playerController.setPlaybackSpeed(speed);
  }

  Future<void> handleSpeedChange(String type) async {
    try {
      final currentSpeed = playerController.playback.playerSpeed;
      int index = defaultPlaySpeedList.indexOf(currentSpeed);
      if (type == "up") {
        if (index < defaultPlaySpeedList.length - 1) {
          index++;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          EmoDialog.showToast(message: '已达倍速上限');
        }
      } else if (type == "down") {
        if (index > 0) {
          index--;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          EmoDialog.showToast(message: '已达倍速下限');
        }
      }
    } catch (e) {
      EmoLogger().e('PlayerController: speed change failed', error: e);
    }
  }

  Future<void> handleShortcutVolumeChange(String type) async {
    try {
      switch (type) {
        case 'up':
          await playerController
              .setVolume(playerController.playback.volume + 10);
          break;
        case 'down':
          await playerController
              .setVolume(playerController.playback.volume - 10);
          break;
        case 'mute':
          await playerController.toggleMute();
          break;
        default:
          return;
      }
      _showVolumeAdjustmentHud();
      _scheduleAdjustmentHudHide(delay: const Duration(seconds: 1));
    } catch (e) {
      EmoLogger().e('PlayerController: volume change failed', error: e);
    }
  }

  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightnessPlatform.instance
          .setApplicationScreenBrightness(value);
    } catch (_) {}
  }

  void _startHideTimer() {
    _cancelHideTimer();
    if (!_canHidePlayerPanel) {
      return;
    }
    hideTimer =
        Timer(Duration(milliseconds: playerControllerLayerDisappearTime), () {
      if (mounted) {
        hideVideoController();
      }
      hideTimer = null;
    });
  }

  void _cancelHideTimer() {
    hideTimer?.cancel();
    hideTimer = null;
  }

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      playerController.syncPlaybackState();
      unawaited(_updateAndroidPIPActions());
      _syncAudioServiceState();
      if (!playerController.panel.volumeSeeking) {
        if (isDesktop()) {
          playerController.playback
              .applyExternalVolume(playerController.playback.playerVolume);
        }
      }
      if (!isDesktop() && !playerController.panel.brightnessSeeking) {
        ScreenBrightnessPlatform.instance.application.then((value) {
          if (!mounted) return;
          playerController.panel.brightness = value;
        });
      }
      if (playerController.playback.completed &&
          !playerPageController.loading) {
        if (playerController.playback.resumedNearEnd) {
          // Replay stale near-end resumes instead of advancing to the next item.
          unawaited(playerController.playback.restartFromBeginning());
        } else {
          final nextIndex = playerPageController.currentIndex + 1;
          if (nextIndex < playerPageController.playlist.length && autoPlayNext) {
            final next = playerPageController.itemAt(nextIndex);
            if (next != null) {
              EmoDialog.showToast(message: '正在加载${next.title}');
            }
            try {
              playerTimer!.cancel();
            } catch (_) {}
            widget.onSelectItem(nextIndex);
          }
        }
      }
    });
  }

  void showVideoInfo() {
    showVideoDetailsSheet(context, playerController: playerController);
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    _initKeyboardActions();
    _initPlayerMenu();
    _fullscreenListener = mobx.reaction<bool>(
      (_) => playerPageController.isFullscreen,
      (_) {
        _handleFullscreenChange();
      },
    );
    _playerSizeListener = mobx.reaction<String>(
      (_) =>
          '${playerController.debug.playerWidth}:${playerController.debug.playerHeight}',
      (_) {
        unawaited(_syncPIPAspectWhenVideoSizeReady());
      },
    );
    if (Platform.isAndroid) {
      PipUtils.initPipHandler(
        onAction: (action) async {
          if (!mounted) return;

          switch (action) {
            case 'play_pause':
              playerController.playOrPause();
              break;

            case 'forward':
              await skipOP();
              break;
          }

          await _updateAndroidPIPActions(force: true);
        },
        onModeChanged: _handleAndroidPIPModeChanged,
      );
      unawaited(_syncAndroidAutoEnterPIPSetting());
      unawaited(_syncAndroidPIPPlayerPageState(true));
      unawaited(_updateAndroidPIPActions(force: true));
      _scheduleAndroidPIPSourceRectSync();
    }
    WidgetsBinding.instance.addObserver(this);
    _panelVisibilityController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _screenshotFeedbackController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _screenshotFeedbackAnimation = CurvedAnimation(
      parent: _screenshotFeedbackController,
      curve: Curves.linear,
    );
    autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);
    backgroundPlayback = GStorage.getSetting(SettingsKeys.backgroundPlayback);
    brightnessVolumeGesture =
        GStorage.getSetting(SettingsKeys.brightnessVolumeGesture);
    playerControllerLayerDisappearTime =
        GStorage.getSetting(SettingsKeys.playerControllerLayerDisappearTime);
    longPressPlaySpeed =
        GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);
    unawaited(_bindAudioService());
    playerTimer = getPlayerTimer();
    windowManager.addListener(this);
    showVideoController();
  }

  @override
  void dispose() {
    // The route-scoped PlayerController owns playback disposal.
    _fullscreenListener();
    _playerSizeListener();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    playerController.seeking.invalidateInteractiveSeek();
    playerTimer?.cancel();
    hideTimer?.cancel();
    mouseScrollerTimer?.cancel();
    _adjustmentHudHideTimer?.cancel();
    _panelVisibilityController.dispose();
    _screenshotFeedbackController.dispose();
    _disposePlayerMenu();
    if (Platform.isAndroid) {
      unawaited(_syncAndroidPIPPlayerPageState(false));
      PipUtils.disposePipHandler();
    }
    playerController.panel.reset();
    // Route teardown can bypass _handleBack (tab switch shortcuts, shell
    // pop); immersive bars and the landscape lock must not outlive playback.
    if (!isDesktop() && playerPageController.isFullscreen) {
      unawaited(playerPageController.setFullscreen(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return ClipRect(
          child: Container(
            color: Colors.black,
            child: MouseRegion(
              cursor: (playerPageController.isFullscreen &&
                      !playerController.panel.showVideoController)
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              onHover: (PointerEvent pointerEvent) {
                // Android taps can emit hover events.
                if (isDesktop()) {
                  if (pointerEvent.position.dy > 50 &&
                      pointerEvent.position.dy <
                          MediaQuery.of(context).size.height - 70) {
                    showVideoController();
                  } else {
                    if (!playerController.panel.showVideoController) {
                      _panelVisibilityController.forward();
                      playerController.panel.showVideoController = true;
                    }
                  }
                }
              },
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    _handleMouseScroller();
                    final scrollDelta = pointerSignal.scrollDelta;
                    final double volume =
                        playerController.playback.volume - scrollDelta.dy / 60;
                    playerController.setVolume(volume);
                  }
                },
                child: SizedBox.expand(
                  child: Stack(alignment: Alignment.center, children: [
                    PlayerKeyboardShortcuts(
                      focusScopeNode: widget.keyboardFocus,
                      actions: keyboardActions,
                      longPressActions: keyboardLongPressActions,
                      isBlocked: () => _openPlayerMenuCount > 0,
                    ),
                    Center(
                      key: _videoSurfaceKey,
                      child: PlayerItemSurface(
                        playerController: playerController,
                      ),
                    ),
                    (playerController.playback.isBuffering ||
                            playerPageController.loading)
                        ? const Positioned.fill(
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Container(),
                    GestureDetector(
                      onTapDown: (details) {
                        _lastTapPointerKind = details.kind;
                      },
                      onTap: () {
                        _handleTap(_lastTapPointerKind);
                        _lastTapPointerKind = null;
                      },
                      onTapCancel: () {
                        _lastTapPointerKind = null;
                      },
                      onDoubleTapDown: (playerController.panel.lockPanel)
                          ? null
                          : (details) {
                              _lastDoubleTapPointerKind = details.kind;
                              _lastDoubleTapDx = details.localPosition.dx;
                            },
                      onDoubleTap: (playerController.panel.lockPanel)
                          ? null
                          : () {
                              _handleDoubleTap(
                                _lastDoubleTapPointerKind ??
                                    _lastTapPointerKind,
                                _lastDoubleTapDx,
                              );
                              _lastDoubleTapPointerKind = null;
                              _lastTapPointerKind = null;
                            },
                      onLongPressStart: (_) {
                        // PiliPlus setLongPressStatus: the temporary speed
                        // only engages while playing, and the matching
                        // end/cancel restores the previous speed.
                        if (playerController.panel.lockPanel ||
                            !playerController.playback.playerPlaying) {
                          return;
                        }
                        setState(() {
                          _longPressSpeedEngaged = true;
                          playerController.panel.showPlaySpeed = true;
                        });
                        lastPlayerSpeed = playerController.playback.playerSpeed;
                        setPlaybackSpeed(longPressPlaySpeed);
                      },
                      onLongPressEnd: (_) {
                        _finishLongPressSpeed();
                      },
                      onLongPressCancel: () {
                        _finishLongPressSpeed();
                      },
                      child: Container(
                        color: Colors.transparent,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    // M7 音乐模式：audioMode 时覆盖视频表面的歌词页（1.x
                    // Main.qml 的 Loader 语义——盖住视频表面与手势层，但保持
                    // 在控制面板之下，播放控制仍在底部栏，P7 v1 范围）。
                    Positioned.fill(child: MusicLyricsPage()),
                    // PiliPlus double-tap seek overlays sit above the gesture
                    // layer so the extra taps accumulate on the indicator.
                    Observer(builder: (context) {
                      final showBackward =
                          playerController.panel.showSeekBackwardOverlay;
                      final showForward =
                          playerController.panel.showSeekForwardOverlay;
                      if (!showBackward && !showForward) {
                        return const SizedBox.shrink();
                      }
                      return PlayerSeekIndicatorOverlay(
                        showBackward: showBackward,
                        showForward: showForward,
                        step: doubleTapSeekStep,
                        onSubmitted: (duration) =>
                            _handleSeekOverlaySubmitted(duration),
                      );
                    }),
                    // Long-press / shortcut speed feedback (Kazumi
                    // PlayerSpeedHud, mounted top-center like the panel).
                    Positioned(
                      top: 25,
                      left: 0,
                      right: 0,
                      child: Observer(
                        builder: (context) => PlayerSpeedHud(
                          visible: playerController.panel.showPlaySpeed,
                          speed: playerController.playback.playerSpeed,
                          disableAnimations: widget.disableAnimations,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: PlayerScreenshotFeedbackOverlay(
                        animation: _screenshotFeedbackAnimation,
                      ),
                    ),
                    (Platform.isAndroid &&
                            (playerPageController.isPip || _pipEnterRequested))
                        ? const SizedBox.shrink()
                        : PlayerItemPanel(
                            fillsWindow: widget.fillsWindow,
                            playerController: playerController,
                            playerPageController: playerPageController,
                            onBackPressed: widget.onBackPressed,
                            setPlaybackSpeed: setPlaybackSpeed,
                            onToggleSidePanel: widget.onToggleSidePanel,
                            onSelectItem: widget.onSelectItem,
                            onLoadSubtitle: widget.onLoadSubtitle,
                            handleFullscreen: handleFullscreen,
                            enterAndroidPictureInPicture:
                                enterAndroidPictureInPicture,
                            handleProgressBarDragStart:
                                handleProgressBarDragStart,
                            handleProgressBarDragEnd: handleProgressBarDragEnd,
                            handleSuperResolutionChange:
                                handleSuperResolutionChange,
                            onNextItem: () => handlePreNextItem('next'),
                            onPrevItem: () => handlePreNextItem('prev'),
                            panelVisibilityController:
                                _panelVisibilityController,
                            keyboardFocus: widget.keyboardFocus,
                            acquirePlayerPanelHold: acquirePlayerPanelHold,
                            onMenuVisibilityChanged:
                                _handlePlayerMenuVisibilityChanged,
                            showVideoInfo: showVideoInfo,
                            pauseForTimedShutdown: widget.pauseForTimedShutdown,
                            disableAnimations: widget.disableAnimations,
                            handleScreenShot: handleScreenshot,
                            showScreenshotCandidates: showScreenshotCandidates,
                            skipOP: skipOP,
                          ),
                    Positioned.fill(
                      left: 16,
                      top: 25,
                      right: 15,
                      bottom: 15,
                      child: (isDesktop() || playerController.panel.lockPanel)
                          ? Container()
                          : PlayerGestureDetector(
                              onSeekStart: () {
                                playerController.panel.seekDirection = 0;
                                playerController.panel.seekCancelPending = false;
                                _beginInteractiveSeek();
                              },
                              onSeekUpdate: (delta, cancelPending) {
                                playerController.panel.showSeekTime = true;
                                playerController.panel.seekCancelPending =
                                    cancelPending;
                                if (delta == 0) return;
                                playerController.panel.seekDirection =
                                    delta > 0 ? 1 : -1;
                                final double scale =
                                    180000 / MediaQuery.sizeOf(context).width;
                                playerController.seeking.updateInteractiveSeek(
                                  playerController.playback.currentPosition +
                                      Duration(
                                        milliseconds:
                                            (delta * scale).round(),
                                      ),
                                );
                              },
                              onSeekEnd: (cancelled) {
                                playerController.panel.showSeekTime = false;
                                playerController.panel.seekCancelPending = false;
                                playerController.panel.seekDirection = 0;
                                unawaited(
                                  _finishInteractiveSeek(cancelled: cancelled),
                                );
                              },
                              onVerticalDragUpdate:
                                  (DragUpdateDetails details) async {
                                if (!brightnessVolumeGesture) {
                                  return;
                                }
                                final double totalWidth =
                                    MediaQuery.sizeOf(context).width;
                                final double totalHeight =
                                    MediaQuery.sizeOf(context).height;
                                final double tapPosition =
                                    details.localPosition.dx;
                                final double sectionWidth = totalWidth / 2;
                                final double delta = details.delta.dy;

                                if (tapPosition < sectionWidth) {
                                  playerController.panel.brightnessSeeking =
                                      true;
                                  _showBrightnessAdjustmentHud();
                                  final double level = (totalHeight) * 2;
                                  final double brightness =
                                      playerController.panel.brightness -
                                          delta / level;
                                  final double result =
                                      brightness.clamp(0.0, 1.0);
                                  setBrightness(result);
                                  playerController.panel.brightness = result;
                                } else {
                                  _showVolumeAdjustmentHud();
                                  if (!playerController.panel.volumeSeeking) {
                                    playerController.panel.volumeSeeking = true;
                                    playerController.playback
                                        .invalidatePreciseVolume();
                                  }
                                  final double baseVolume = playerController
                                              .playback.preciseVolume >=
                                          0
                                      ? playerController.playback.preciseVolume
                                      : playerController.playback.volume;
                                  final double level = (totalHeight) * 0.03;
                                  final double volume =
                                      baseVolume - delta / level;
                                  playerController
                                      .setVolumeDuringGesture(volume);
                                }
                              },
                              onVerticalDragEnd: (_) {
                                _finishAdjustmentGesture();
                              },
                              onVerticalDragCancel: () {
                                _finishAdjustmentGesture();
                              },
                            ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
