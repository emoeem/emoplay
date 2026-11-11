import 'dart:async';

import 'package:flutter/material.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/controller/player_screenshot_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:emoplay/pages/player/player_screenshot_sheet.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:emoplay/services/player/timed_shutdown_service.dart';
import 'package:emoplay/utils/device.dart';

/// Screenshot orchestration extracted from player_item.dart (M3-T0 god-class
/// split; pure move, no behavior change).
///
/// Hosts the desktop capture flow (capture -> feedback -> toast -> candidate
/// sheet), the mobile save-to-gallery path and the sheet resume guard. The
/// hosting state owns the feedback [AnimationController] (created with its
/// TickerProvider) and hands it in here.
class PlayerScreenshotActions {
  PlayerScreenshotActions({
    required this.host,
    required this.playerController,
    required this.playerPageController,
    required this.keyboardFocus,
    required this.feedbackController,
    required this.acquirePlayerPanelHold,
    required this.showVideoController,
    required this.disableAnimations,
  });

  /// Hosting player state; [State.mounted] and [State.context] gate the
  /// async flow exactly like the original inline methods.
  final State host;
  final PlayerController playerController;
  final PlayerPageController playerPageController;

  /// Refocused after the candidate sheet closes (widget.keyboardFocus).
  final FocusNode keyboardFocus;
  final AnimationController feedbackController;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final void Function({bool restartHideTimer}) showVideoController;

  /// widget.disableAnimations (final, so a plain value is enough).
  final bool disableAnimations;

  late final PlayerScreenshotController _screenshots =
      playerController.screenshots;
  bool _screenshotSheetOpen = false;

  Future<void> handleScreenshot() async {
    if (!host.mounted) return;
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
          host.mounted &&
          !playerPageController.loading &&
          playerPageController.src == source &&
          identical(playerController.playback.mediaPlayer, player),
    );
    if (!host.mounted) return;
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
      if (!host.mounted) return;
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
      if (host.mounted && !result.isSuccess) {
        EmoDialog.showToast(message: '截图保存失败：${result.errorMessage}');
      }
    } catch (e) {
      if (host.mounted) EmoDialog.showToast(message: '截图失败：$e');
    }
  }

  Future<void> showScreenshotCandidates() async {
    if (!isDesktop() || !host.mounted || _screenshotSheetOpen || _screenshots.busy) {
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
      if (!host.mounted) return;
      await showPlayerScreenshotSheet(host.context, controller: _screenshots);
    } finally {
      _screenshotSheetOpen = false;
      if (host.mounted) {
        hold.release();
        keyboardFocus.requestFocus();
        // Resume only the same local playback, respecting the sleep timer.
        if (resume &&
            identical(player, playerController.playback.mediaPlayer) &&
            playerPageController.src == source &&
            playerPageController.currentItem == item &&
            !playerPageController.loading &&
            (sleepDeadline == null || DateTime.now().isBefore(sleepDeadline)) &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
            (ModalRoute.of(host.context)?.isCurrent ?? false)) {
          await playerController.play(enableSync: false);
        }
      } else {
        hold.releaseSilently();
      }
    }
  }

  void _playScreenshotFeedback() {
    if (!host.mounted ||
        disableAnimations ||
        MediaQuery.disableAnimationsOf(host.context)) {
      return;
    }
    feedbackController.forward(from: 0);
  }
}
