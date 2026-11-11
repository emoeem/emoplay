import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/player/pip_utils.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/device.dart';

/// Android/desktop Picture-in-Picture coordination extracted from
/// player_item.dart (M3-T0 god-class split; pure move, no behavior change).
///
/// Owns the PiP flags, the native handler wiring and the source-rect sync.
/// [host] is the hosting player state: PiP entry mutates its widget tree via
/// [playerSetState] and measures the video surface through its context.
class PlayerPipCoordinator {
  PlayerPipCoordinator({
    required this.host,
    required this.playerSetState,
    required this.playerController,
    required this.playerPageController,
    required this.videoSurfaceKey,
    required this.onPlayOrPause,
    required this.onSkipOp,
  });

  /// Hosting player state; only [State.mounted] and [State.context] are used.
  final State host;

  /// Wraps the host's [State.setState] (PiP entry toggles widget-local state).
  final void Function(VoidCallback fn) playerSetState;
  final PlayerController playerController;
  final PlayerPageController playerPageController;
  final GlobalKey videoSurfaceKey;

  /// PiP "play/pause" native action (player_item initState onAction).
  final Future<void> Function() onPlayOrPause;

  /// PiP "forward" native action (player_item initState onAction -> skipOP).
  final Future<void> Function() onSkipOp;

  bool? _lastPipPlaying;
  Rect? _lastPipSourceRect;
  bool _pipSourceRectSyncScheduled = false;
  bool _pipEnterRequested = false;

  /// True between a PiP entry request and its confirmation/native mode change;
  /// the panel hides while it is set (player_item build).
  bool get pipEnterRequested => _pipEnterRequested;

  Future<void> syncAndroidAutoEnterPIPSetting() async {
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

  Future<void> syncAndroidPIPPlayerPageState(bool inPlayerPage) async {
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

  Future<void> updateAndroidPIPActions({bool force = false}) async {
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
    if (!host.mounted) {
      return null;
    }
    final renderObject = videoSurfaceKey.currentContext?.findRenderObject();
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
    final double ratio = MediaQuery.devicePixelRatioOf(host.context);
    return Rect.fromLTRB(
      rect.left * ratio,
      rect.top * ratio,
      rect.right * ratio,
      rect.bottom * ratio,
    );
  }

  // Remove controls before PiP entry to avoid rebuilding during the resize animation.
  Future<void> enterAndroidPictureInPicture() async {
    if (!Platform.isAndroid || !host.mounted) {
      return;
    }
    final bool supported = await PipUtils.isAndroidPIPSupported();
    if (!host.mounted) {
      return;
    }
    if (!supported) {
      EmoDialog.showToast(message: '当前设备不支持画中画');
      return;
    }
    playerSetState(() {
      _pipEnterRequested = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!host.mounted) {
      return;
    }
    await updateAndroidPIPActions(force: true);
    final bool entered = await PipUtils.enterAndroidPIPWindow(
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
    );
    if (entered || !host.mounted) {
      return;
    }
    EmoDialog.showToast(message: '进入画中画失败');
    playerSetState(() {
      _pipEnterRequested = false;
    });
  }

  void handleAndroidPIPModeChanged(bool inPipMode) {
    if (!host.mounted || playerPageController.isPip == inPipMode) {
      return;
    }
    playerSetState(() {
      playerPageController.setPip(inPipMode);
    });
    if (!inPipMode) {
      _pipEnterRequested = false;
      scheduleAndroidPIPSourceRectSync();
    }
  }

  void scheduleAndroidPIPSourceRectSync() {
    if (!Platform.isAndroid || _pipSourceRectSyncScheduled) {
      return;
    }
    _pipSourceRectSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pipSourceRectSyncScheduled = false;
      if (!host.mounted) {
        return;
      }
      unawaited(updateAndroidPIPActions());
    });
  }

  Future<void> syncPIPAspectWhenVideoSizeReady() async {
    if (playerController.debug.playerWidth <= 0 ||
        playerController.debug.playerHeight <= 0) {
      return;
    }
    if (Platform.isAndroid) {
      await updateAndroidPIPActions(force: true);
      return;
    }
    if (isDesktop() && playerPageController.isPip) {
      await PipUtils.enterDesktopPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      );
    }
  }

  /// Native handler wiring from player_item.initState (Android only).
  void init() {
    if (!Platform.isAndroid) {
      return;
    }
    PipUtils.initPipHandler(
      onAction: (action) async {
        if (!host.mounted) return;

        switch (action) {
          case 'play_pause':
            // Matches the original initState wiring: playOrPause is fired,
            // not awaited, before the forced actions refresh.
            onPlayOrPause();
            break;

          case 'forward':
            await onSkipOp();
            break;
        }

        await updateAndroidPIPActions(force: true);
      },
      onModeChanged: handleAndroidPIPModeChanged,
    );
    unawaited(syncAndroidAutoEnterPIPSetting());
    unawaited(syncAndroidPIPPlayerPageState(true));
    unawaited(updateAndroidPIPActions(force: true));
    scheduleAndroidPIPSourceRectSync();
  }

  /// Native teardown from player_item.dispose (Android only).
  void dispose() {
    if (!Platform.isAndroid) {
      return;
    }
    unawaited(syncAndroidPIPPlayerPageState(false));
    PipUtils.disposePipHandler();
  }
}
