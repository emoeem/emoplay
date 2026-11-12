import 'dart:async';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/music/music_queue.dart';
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
  Timer? _dragSeekTimer;
  Duration? _dragSeekTarget;

  /// 拖动中双 seek 的尾随消抖窗（Haruna onMoved 是逐事件 commandAsync，mpv
  /// 自行合并；media_kit 的 player 内部锁串行化每次 seek，这里显式合并）。
  static const Duration _dragSeekDebounce = Duration(milliseconds: 120);

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
    _dragSeekTimer?.cancel();
    _dragSeekTimer = null;
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

  /// M3-T1 帧预览：拖动中的双 seek 入口（进度条 onDragUpdate）。
  ///
  /// Haruna HProgressBar.qml:226-252 onMoved 语义：主实例与预览实例各收到
  /// 一条 `seek <value> absolute`。鼠标拖动且预览激活
  /// （seekPreview.shouldActivate）时主实例追加尾随消抖的绝对 seek（松手时
  /// finishInteractiveSeek 的最终 seek 落点不变，中间 seek 只是让主画面实时
  /// 跟随）；预览实例经 [SeekPreviewController.previewAt] 自带 100ms 消抖。
  /// 触摸拖动无帧预览气泡（进度条 _previewFraction 仅鼠标拖动非空），保持
  /// 2.x 原行为：拖动只更新 UI 状态，松手才 seek。预览未激活时同样保持
  /// 2.x 原行为。
  void handleProgressBarDragUpdate(
    Duration position, {
    required bool mouseDrag,
  }) {
    if (!playerController.seeking.updateInteractiveSeek(position)) {
      return;
    }
    if (!mouseDrag) {
      return;
    }
    final preview = playerController.seekPreview;
    if (!preview.shouldActivate) {
      return;
    }
    preview.previewAt(position);
    _dragSeekTarget = position;
    _dragSeekTimer?.cancel();
    _dragSeekTimer = Timer(_dragSeekDebounce, () {
      _dragSeekTimer = null;
      final target = _dragSeekTarget;
      _dragSeekTarget = null;
      if (target == null) {
        return;
      }
      unawaited(
        playerController.seeking.seekTo(target, enableSync: false).catchError(
              (Object e) => EmoLogger()
                  .w('PlayerController: drag seek failed', error: e),
            ),
      );
    });
  }

  /// player_item handleProgressBarDragEnd.
  void handleProgressBarDragEnd(bool cancelled) {
    // 最终落点由 finishInteractiveSeek 的 seek 负责，挂起的中间 seek 作废。
    _dragSeekTimer?.cancel();
    _dragSeekTimer = null;
    _dragSeekTarget = null;
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
          // M5-T1 循环/队列：推进决策收口到 resolveQueueNextIndex（纯函数，
          // test/music_queue_test.dart 护航）。none：顺序推进、队尾停止
          // （即原 inline 语义）；playlist：队尾回卷到 0；single：永不推进
          // （引擎原生 loop-file 重复，completed 到不了这里，双保险）；
          // autoPlayNext 仍是总闸。模式实时读 settings.json behavior 段
          // （面板/设置页切换即时生效）；MediaStores 未就绪回落 none。
          final nextIndex = resolveQueueNextIndex(
            currentIndex: playerPageController.currentIndex,
            count: playerPageController.playlist.length,
            mode: playerController.playback.currentLoopMode(),
            autoPlayNext: autoPlayNext,
          );
          if (nextIndex != null) {
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
