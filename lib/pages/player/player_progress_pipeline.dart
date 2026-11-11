import 'dart:async';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/device.dart';
import 'package:flutter/material.dart';

/// Playback heartbeat + interactive-seek pipeline extracted from
/// player_item.dart (M3-T0 god-class split; pure move, no behavior change).
///
/// Owns the 1s progress timer (state sync, external volume/brightness
/// mirrors, auto-next), the heartbeat pause/resume around shortcut seeks and
/// the progress-bar drag lifecycle (interactive seek + panel hold).
class PlayerProgressPipeline {
  PlayerProgressPipeline({
    required this.host,
    required this.playerController,
    required this.playerPageController,
    required this.syncAudioState,
    required this.syncPipActions,
    required this.holds,
    required this.onSelectItem,
  }) : autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);

  /// Hosting player state; only [State.mounted] is used inside timers.
  final State host;
  final PlayerController playerController;
  final PlayerPageController playerPageController;

  /// Mirrors the playback state into the audio_service session
  /// (PlayerAudioBinding.syncState, late-bound by the host to break the
  /// construction cycle).
  final void Function() syncAudioState;

  /// Refreshes the Android PiP notification actions
  /// (PlayerPipCoordinator.updateAndroidPIPActions, late-bound likewise).
  final Future<void> Function() syncPipActions;
  final PlayerPanelHoldRegistry holds;

  /// Switches the player to the playlist entry at the given index
  /// (player_item widget.onSelectItem).
  final Future<void> Function(int index) onSelectItem;

  /// SettingsKeys.autoPlayNext, read once at initState timing as before.
  late final bool autoPlayNext;

  Timer? _playerTimer;
  PlayerPanelHold? _progressBarDragHold;

  /// player_item getPlayerTimer.
  void start() {
    _playerTimer = _createPlayerTimer();
  }

  /// player_item _restartPlayerTimer.
  void restart() {
    _playerTimer?.cancel();
    _playerTimer = _createPlayerTimer();
  }

  /// player_item dispose playerTimer?.cancel().
  void dispose() {
    _playerTimer?.cancel();
  }

  /// player_item _seekWithPlayerTimer.
  Future<void> seekWithPlayerTimer(
    Future<void> Function() seekAction,
  ) async {
    _playerTimer?.cancel();
    try {
      await seekAction();
    } finally {
      if (host.mounted) {
        restart();
      }
    }
  }

  /// player_item handleProgressBarDragStart.
  void handleProgressBarDragStart() {
    beginInteractiveSeek();
    syncAudioState();
    _progressBarDragHold = holds.acquirePlayerPanelHold();
  }

  /// player_item handleProgressBarDragEnd.
  void handleProgressBarDragEnd(bool cancelled) {
    unawaited(finishInteractiveSeek(cancelled: cancelled));
  }

  /// player_item _beginInteractiveSeek.
  void beginInteractiveSeek() {
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    _playerTimer?.cancel();
    playerController.seeking.beginInteractiveSeek();
  }

  /// player_item _finishInteractiveSeek.
  Future<void> finishInteractiveSeek({bool cancelled = false}) async {
    var completed = false;
    try {
      completed = await playerController.seeking
          .finishInteractiveSeek(cancelled: cancelled);
    } catch (e) {
      EmoLogger().e('PlayerController: interactive seek failed', error: e);
    }
    if (!host.mounted ||
        (!completed && playerController.seeking.hasActiveInteractiveSeek)) {
      return;
    }
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    if (completed) {
      syncAudioState();
    }
    restart();
  }

  Timer _createPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      playerController.syncPlaybackState();
      unawaited(syncPipActions());
      syncAudioState();
      if (!playerController.panel.volumeSeeking) {
        if (isDesktop()) {
          playerController.playback
              .applyExternalVolume(playerController.playback.playerVolume);
        }
      }
      if (!isDesktop() && !playerController.panel.brightnessSeeking) {
        ScreenBrightnessPlatform.instance.application.then((value) {
          if (!host.mounted) return;
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
              _playerTimer!.cancel();
            } catch (_) {}
            onSelectItem(nextIndex);
          }
        }
      }
    });
  }
}
