import 'dart:async';
import 'dart:io';

import 'package:emoplay/pages/player/player_item_gestures.dart';
import 'package:emoplay/pages/player/player_item_panel.dart';
import 'package:emoplay/pages/player/player_keyboard_shortcuts.dart';
import 'package:emoplay/pages/player/player_pip.dart';
import 'package:emoplay/pages/player/player_audio_binding.dart';
import 'package:emoplay/pages/player/player_menu_binding.dart';
import 'package:emoplay/pages/player/player_progress_pipeline.dart';
import 'package:emoplay/pages/player/player_screenshot_actions.dart';
import 'package:emoplay/pages/player/player_super_resolution_prompt.dart';
import 'package:emoplay/pages/player/player_adjustment_hud.dart';
import 'package:emoplay/pages/player/music_lyrics_page.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:emoplay/pages/player/player_seek_indicator.dart';
import 'package:emoplay/pages/player/player_screenshot_feedback_overlay.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:flutter/gestures.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/video_details_sheet.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/pages/player/player_item_surface.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:emoplay/utils/device.dart';

/// The player surface: video, gestures, keyboard shortcuts, screenshots and
/// the control panel.
///
/// EmoPlay M1: the Kazumi danmaku/syncplay/bangumi-history integrations were
/// removed with the bangumi business layer (docs/STRIP-LIST.md §2); playback
/// state lives in [PlayerController], playlist and fullscreen flags in
/// [PlayerPageController].
///
/// M3-T0 god-class split: the former inline clusters now live in their own
/// units, wired together here — PiP in [PlayerPipCoordinator], the
/// audio_service session in [PlayerAudioBinding], the native menu in
/// [PlayerMenuBinding], shortcut handlers in [PlayerShortcutHandlers]
/// (player_keyboard_shortcuts.dart), HUD scheduling in
/// [PlayerAdjustmentHudScheduler], panel visibility/holds in
/// [PlayerPanelHoldRegistry] (player_panel_hold.dart), the heartbeat and
/// interactive-seek pipeline in [PlayerProgressPipeline], tap/drag layers in
/// player_item_gestures.dart, the screenshot flow in
/// [PlayerScreenshotActions] and the super-resolution prompts in
/// player_super_resolution_prompt.dart. Pure move, no behavior change.
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

  final _videoSurfaceKey = GlobalKey();

  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;

  late final AnimationController _panelVisibilityController;
  late final AnimationController _screenshotFeedbackController;
  late final Animation<double> _screenshotFeedbackAnimation;

  late final PlayerPanelHoldRegistry _holds;
  late final PlayerAdjustmentHudScheduler _hud;
  late final PlayerScreenshotActions _screenshotActions;
  late final PlayerShortcutHandlers _shortcuts;
  late final PlayerAudioBinding _audioBinding;
  late final PlayerMenuBinding _menu = PlayerMenuBinding();
  late final PlayerProgressPipeline _progress;
  late final PlayerPipCoordinator _pip;
  late final PlayerItemGestureController _gestures;

  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _pip.scheduleAndroidPIPSourceRectSync();
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

  void _handleFullscreenChange() {
    playerController.panel.lockPanel = false;
    _holds.releaseAllHolds();
    _pip.scheduleAndroidPIPSourceRectSync();
  }

  void showVideoInfo() {
    showVideoDetailsSheet(context, playerController: playerController);
  }

  Future<void> handleSuperResolutionChange(SuperResolutionMode mode) {
    return resolveSuperResolutionChange(
      playerController: playerController,
      mode: mode,
      isMounted: () => mounted,
    );
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    backgroundPlayback = GStorage.getSetting(SettingsKeys.backgroundPlayback);
    brightnessVolumeGesture =
        GStorage.getSetting(SettingsKeys.brightnessVolumeGesture);
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
    _holds = PlayerPanelHoldRegistry(
      host: this,
      playerController: playerController,
      panelVisibility: _panelVisibilityController,
      hideDelayMs: GStorage.getSetting(
        SettingsKeys.playerControllerLayerDisappearTime,
      ),
    );
    _hud = PlayerAdjustmentHudScheduler(
      host: this,
      playerController: playerController,
      brightnessVolumeGesture: brightnessVolumeGesture,
    );
    _screenshotActions = PlayerScreenshotActions(
      host: this,
      playerController: playerController,
      playerPageController: playerPageController,
      keyboardFocus: widget.keyboardFocus,
      feedbackController: _screenshotFeedbackController,
      acquirePlayerPanelHold: _holds.acquirePlayerPanelHold,
      showVideoController: _holds.showVideoController,
      disableAnimations: widget.disableAnimations,
    );
    _progress = PlayerProgressPipeline(
      host: this,
      playerController: playerController,
      playerPageController: playerPageController,
      syncAudioState: () => _audioBinding.syncState(),
      syncPipActions: () => _pip.updateAndroidPIPActions(),
      holds: _holds,
      onSelectItem: widget.onSelectItem,
    );
    _shortcuts = PlayerShortcutHandlers(
      playerSetState: (fn) => setState(fn),
      playerController: playerController,
      playerPageController: playerPageController,
      hud: _hud,
      seekWithPlayerTimer: _progress.seekWithPlayerTimer,
      onSelectItem: widget.onSelectItem,
      onScreenshot: _screenshotActions.handleScreenshot,
    );
    _audioBinding = PlayerAudioBinding(
      playerController: playerController,
      playerPageController: playerPageController,
      onPreNextItem: _shortcuts.handlePreNextItem,
    );
    _menu.init(_shortcuts.actions);
    _pip = PlayerPipCoordinator(
      host: this,
      playerSetState: (fn) => setState(fn),
      playerController: playerController,
      playerPageController: playerPageController,
      videoSurfaceKey: _videoSurfaceKey,
      onPlayOrPause: () => playerController.playOrPause(),
      onSkipOp: _shortcuts.skipOP,
    );
    _gestures = PlayerItemGestureController(
      playerController: playerController,
      playerPageController: playerPageController,
      shortcuts: _shortcuts,
      showVideoController: _holds.showVideoController,
      hideVideoController: _holds.hideVideoController,
      seekWithPlayerTimer: _progress.seekWithPlayerTimer,
      context: () => context,
    );
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
        unawaited(_pip.syncPIPAspectWhenVideoSizeReady());
      },
    );
    _pip.init();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_audioBinding.bind());
    _progress.start();
    windowManager.addListener(this);
    _holds.showVideoController();
  }

  @override
  void dispose() {
    // The route-scoped PlayerController owns playback disposal.
    _fullscreenListener();
    _playerSizeListener();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    playerController.seeking.invalidateInteractiveSeek();
    _progress.dispose();
    _holds.dispose();
    _hud.dispose();
    _panelVisibilityController.dispose();
    _screenshotFeedbackController.dispose();
    _menu.dispose();
    _pip.dispose();
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
                    _holds.showVideoController();
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
                    _hud.handleMouseScroller();
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
                      actions: _shortcuts.actions,
                      longPressActions: _shortcuts.longPressActions,
                      isBlocked: () => _menu.openCount > 0,
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
                    PlayerTapGestureLayer(
                      gestures: _gestures,
                      shortcuts: _shortcuts,
                      locked: playerController.panel.lockPanel,
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
                            _gestures.handleSeekOverlaySubmitted(duration),
                      );
                    }),
                    ...playerAdjustmentHudLayers(
                      playerController: playerController,
                      disableAnimations: widget.disableAnimations,
                    ),
                    Positioned.fill(
                      child: PlayerScreenshotFeedbackOverlay(
                        animation: _screenshotFeedbackAnimation,
                      ),
                    ),
                    (Platform.isAndroid &&
                            (playerPageController.isPip ||
                                _pip.pipEnterRequested))
                        ? const SizedBox.shrink()
                        : PlayerItemPanel(
                            fillsWindow: widget.fillsWindow,
                            playerController: playerController,
                            playerPageController: playerPageController,
                            onBackPressed: widget.onBackPressed,
                            setPlaybackSpeed: _shortcuts.setPlaybackSpeed,
                            onToggleSidePanel: widget.onToggleSidePanel,
                            onSelectItem: widget.onSelectItem,
                            onLoadSubtitle: widget.onLoadSubtitle,
                            handleFullscreen: _shortcuts.handleFullscreen,
                            enterAndroidPictureInPicture:
                                _pip.enterAndroidPictureInPicture,
                            handleProgressBarDragStart:
                                _progress.handleProgressBarDragStart,
                            handleProgressBarDragEnd:
                                _progress.handleProgressBarDragEnd,
                            handleSuperResolutionChange:
                                handleSuperResolutionChange,
                            onNextItem: () =>
                                _shortcuts.handlePreNextItem('next'),
                            onPrevItem: () =>
                                _shortcuts.handlePreNextItem('prev'),
                            panelVisibilityController:
                                _panelVisibilityController,
                            keyboardFocus: widget.keyboardFocus,
                            acquirePlayerPanelHold:
                                _holds.acquirePlayerPanelHold,
                            onMenuVisibilityChanged:
                                _menu.handleVisibilityChanged,
                            showVideoInfo: showVideoInfo,
                            pauseForTimedShutdown: widget.pauseForTimedShutdown,
                            disableAnimations: widget.disableAnimations,
                            handleScreenShot:
                                _screenshotActions.handleScreenshot,
                            showScreenshotCandidates:
                                _screenshotActions.showScreenshotCandidates,
                            skipOP: _shortcuts.skipOP,
                          ),
                    Positioned.fill(
                      left: 16,
                      top: 25,
                      right: 15,
                      bottom: 15,
                      child: (isDesktop() || playerController.panel.lockPanel)
                          ? Container()
                          : PlayerItemDragLayer(
                              playerController: playerController,
                              brightnessVolumeGesture:
                                  brightnessVolumeGesture,
                              hud: _hud,
                              beginInteractiveSeek:
                                  _progress.beginInteractiveSeek,
                              finishInteractiveSeek:
                                  _progress.finishInteractiveSeek,
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
