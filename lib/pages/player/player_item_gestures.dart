import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:emoplay/pages/player/player_adjustment_hud.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_gesture_detector.dart';
import 'package:emoplay/pages/player/player_keyboard_shortcuts.dart';
import 'package:emoplay/pages/player/player_pointer_interaction.dart';
import 'package:emoplay/pages/player/player_seek_indicator.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:emoplay/utils/device.dart';

/// Tap / double-tap / long-press / drag wiring extracted from player_item.dart
/// (M3-T0 god-class split; pure move, no behavior change).
///
/// [PlayerItemGestureController] holds the pointer bookkeeping and resolves
/// taps to controller toggles or fullscreen; [PlayerTapGestureLayer] and
/// [PlayerItemDragLayer] are the widget shells that used to sit inline in the
/// player_item build method. All mobx reads that happened inside the player
/// build still happen there (the layers receive plain values), so Observer
/// subscriptions are unchanged.
class PlayerItemGestureController {
  PlayerItemGestureController({
    required this.playerController,
    required this.playerPageController,
    required this.shortcuts,
    required this.showVideoController,
    required this.hideVideoController,
    required this.seekWithPlayerTimer,
    required this.context,
  });

  final PlayerController playerController;
  final PlayerPageController playerPageController;
  final PlayerShortcutHandlers shortcuts;

  /// Panel visibility controls (player_item showVideoController with its
  /// restartHideTimer option, hideVideoController).
  final void Function({bool restartHideTimer}) showVideoController;
  final VoidCallback hideVideoController;

  /// Heartbeat pause/resume around shortcut seeks.
  final Future<void> Function(Future<void> Function() seekAction)
      seekWithPlayerTimer;

  /// Hosting player state context (MediaQuery reads inside tap handlers,
  /// evaluated at event time exactly as before).
  final BuildContext Function() context;

  PointerDeviceKind? _lastTapPointerKind;
  PointerDeviceKind? _lastDoubleTapPointerKind;
  double _lastDoubleTapDx = 0;

  void handleTapDown(PointerDeviceKind? pointerKind) {
    _lastTapPointerKind = pointerKind;
  }

  void handleTapCancel() {
    _lastTapPointerKind = null;
  }

  void handleTap() {
    _handleTap(_lastTapPointerKind);
    _lastTapPointerKind = null;
  }

  void handleDoubleTapDown(PointerDeviceKind? pointerKind, double dx) {
    _lastDoubleTapPointerKind = pointerKind;
    _lastDoubleTapDx = dx;
  }

  void handleDoubleTap() {
    _handleDoubleTap(
      _lastDoubleTapPointerKind ?? _lastTapPointerKind,
      _lastDoubleTapDx,
    );
    _lastDoubleTapPointerKind = null;
    _lastTapPointerKind = null;
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
      shortcuts.handleFullscreen();
      return;
    }
    // PiliPlus onDoubleTapDownMobile: touch double-taps are zoned — the left
    // quarter mounts the backward seek overlay, the right quarter the forward
    // one, the middle half toggles playback.
    final width = MediaQuery.sizeOf(context()).width;
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
  Future<void> handleSeekOverlaySubmitted(Duration duration) async {
    playerController.panel.showSeekBackwardOverlay = false;
    playerController.panel.showSeekForwardOverlay = false;
    await seekWithPlayerTimer(() => playerController.seekBy(duration));
  }
}

/// The tap / double-tap / long-press surface (player_item build, inline
/// GestureDetector subtree). [locked] is evaluated by the parent Observer so
/// the panel-lock subscription stays where it was.
class PlayerTapGestureLayer extends StatelessWidget {
  const PlayerTapGestureLayer({
    super.key,
    required this.gestures,
    required this.shortcuts,
    required this.locked,
  });

  final PlayerItemGestureController gestures;
  final PlayerShortcutHandlers shortcuts;

  /// playerController.panel.lockPanel, read by the parent Observer.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        gestures.handleTapDown(details.kind);
      },
      onTap: () {
        gestures.handleTap();
      },
      onTapCancel: () {
        gestures.handleTapCancel();
      },
      onDoubleTapDown: locked
          ? null
          : (details) {
              gestures.handleDoubleTapDown(
                details.kind,
                details.localPosition.dx,
              );
            },
      onDoubleTap: locked
          ? null
          : () {
              gestures.handleDoubleTap();
            },
      onLongPressStart: (_) {
        shortcuts.beginLongPressSpeed();
      },
      onLongPressEnd: (_) {
        shortcuts.finishLongPressSpeed();
      },
      onLongPressCancel: () {
        shortcuts.finishLongPressSpeed();
      },
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

/// Mobile seek-drag + brightness/volume drag wiring (player_item build, inline
/// PlayerGestureDetector subtree). The parent Observer evaluates the
/// desktop/lockPanel gate; the closures here run at event time only.
class PlayerItemDragLayer extends StatelessWidget {
  const PlayerItemDragLayer({
    super.key,
    required this.playerController,
    required this.brightnessVolumeGesture,
    required this.hud,
    required this.beginInteractiveSeek,
    required this.finishInteractiveSeek,
  });

  final PlayerController playerController;

  /// SettingsKeys.brightnessVolumeGesture, read once at initState.
  final bool brightnessVolumeGesture;
  final PlayerAdjustmentHudScheduler hud;
  final VoidCallback beginInteractiveSeek;
  final Future<void> Function({bool cancelled}) finishInteractiveSeek;

  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightnessPlatform.instance
          .setApplicationScreenBrightness(value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PlayerGestureDetector(
      onSeekStart: () {
        playerController.panel.seekDirection = 0;
        playerController.panel.seekCancelPending = false;
        beginInteractiveSeek();
      },
      onSeekUpdate: (delta, cancelPending) {
        playerController.panel.showSeekTime = true;
        playerController.panel.seekCancelPending = cancelPending;
        if (delta == 0) return;
        playerController.panel.seekDirection = delta > 0 ? 1 : -1;
        final double scale = 180000 / MediaQuery.sizeOf(context).width;
        playerController.seeking.updateInteractiveSeek(
          playerController.playback.currentPosition +
              Duration(
                milliseconds: (delta * scale).round(),
              ),
        );
      },
      onSeekEnd: (cancelled) {
        playerController.panel.showSeekTime = false;
        playerController.panel.seekCancelPending = false;
        playerController.panel.seekDirection = 0;
        unawaited(finishInteractiveSeek(cancelled: cancelled));
      },
      onVerticalDragUpdate: (DragUpdateDetails details) async {
        if (!brightnessVolumeGesture) {
          return;
        }
        final double totalWidth = MediaQuery.sizeOf(context).width;
        final double totalHeight = MediaQuery.sizeOf(context).height;
        final double tapPosition = details.localPosition.dx;
        final double sectionWidth = totalWidth / 2;
        final double delta = details.delta.dy;

        if (tapPosition < sectionWidth) {
          playerController.panel.brightnessSeeking = true;
          hud.showBrightnessAdjustmentHud();
          final double level = (totalHeight) * 2;
          final double brightness =
              playerController.panel.brightness - delta / level;
          final double result = brightness.clamp(0.0, 1.0);
          setBrightness(result);
          playerController.panel.brightness = result;
        } else {
          hud.showVolumeAdjustmentHud();
          if (!playerController.panel.volumeSeeking) {
            playerController.panel.volumeSeeking = true;
            playerController.playback.invalidatePreciseVolume();
          }
          final double baseVolume = playerController.playback.preciseVolume >= 0
              ? playerController.playback.preciseVolume
              : playerController.playback.volume;
          final double level = (totalHeight) * 0.03;
          final double volume = baseVolume - delta / level;
          playerController.setVolumeDuringGesture(volume);
        }
      },
      onVerticalDragEnd: (_) {
        hud.finishAdjustmentGesture();
      },
      onVerticalDragCancel: () {
        hud.finishAdjustmentGesture();
      },
    );
  }
}
