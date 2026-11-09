import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/emo_menu.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/services/player/timed_shutdown_service.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/utils/device.dart';
import 'package:emoplay/utils/format.dart';

/// Player control panel for EmoPlay.
///
/// M1 rebuild of the Kazumi panel without the danmaku/syncplay feature set:
/// transport bar, playlist, speed/volume, screenshots, super resolution,
/// window fullscreen and (Android) picture in picture.
class PlayerItemPanel extends StatefulWidget {
  const PlayerItemPanel({
    super.key,
    required this.fillsWindow,
    required this.playerController,
    required this.playerPageController,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    this.onToggleSidePanel,
    required this.onSelectItem,
    required this.handleFullscreen,
    required this.enterAndroidPictureInPicture,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarDragEnd,
    required this.handleSuperResolutionChange,
    required this.onNextItem,
    required this.onPrevItem,
    required this.panelVisibilityController,
    required this.keyboardFocus,
    required this.acquirePlayerPanelHold,
    required this.onMenuVisibilityChanged,
    required this.showVideoInfo,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
    required this.handleScreenShot,
    required this.showScreenshotCandidates,
    required this.skipOP,
  });

  final bool fillsWindow;
  final PlayerController playerController;
  final PlayerPageController playerPageController;
  final VoidCallback onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback? onToggleSidePanel;
  final Future<void> Function(int index) onSelectItem;
  final VoidCallback handleFullscreen;
  final Future<void> Function() enterAndroidPictureInPicture;
  final VoidCallback handleProgressBarDragStart;
  final ValueChanged<bool> handleProgressBarDragEnd;
  final Future<void> Function(SuperResolutionMode) handleSuperResolutionChange;
  final VoidCallback onNextItem;
  final VoidCallback onPrevItem;
  final AnimationController panelVisibilityController;
  final FocusNode keyboardFocus;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onMenuVisibilityChanged;
  final VoidCallback showVideoInfo;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;
  final VoidCallback handleScreenShot;
  final VoidCallback showScreenshotCandidates;
  final VoidCallback skipOP;

  @override
  State<PlayerItemPanel> createState() => _PlayerItemPanelState();
}

class _PlayerItemPanelState extends State<PlayerItemPanel> {
  @override
  Widget build(BuildContext context) {
    final overlayColor = Colors.white;
    return FadeTransition(
      opacity: widget.panelVisibilityController,
      child: Observer(builder: (context) {
        final visible = widget.playerController.panel.showVideoController;
        return IgnorePointer(
          ignoring: !visible,
          child: ColoredBox(
            color: visible
                ? Colors.black.withValues(alpha: 0.35)
                : Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _topBar(context, overlayColor),
                _bottomBar(context, overlayColor),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _iconButton(
    BuildContext context,
    Widget icon,
    String tooltip,
    VoidCallback? onPressed,
  ) {
    return IconButton(
      icon: icon,
      color: Colors.white,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _topBar(BuildContext context, Color color) {
    final title = widget.playerController.mediaTitle;
    return Row(
      children: [
        _iconButton(
          context,
          const Icon(Icons.arrow_back),
          '返回',
          widget.onBackPressed,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: color, fontSize: 16),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        _iconButton(
          context,
          const Icon(Icons.chevron_left),
          '上一个',
          widget.onPrevItem,
        ),
        _iconButton(
          context,
          const Icon(Icons.chevron_right),
          '下一个',
          widget.onNextItem,
        ),
        _iconButton(
          context,
          const Icon(Icons.video_library_rounded),
          '播放列表',
          () => _openMenu(_showPlaylistSheet),
        ),
        if (widget.onToggleSidePanel != null)
          _iconButton(
            context,
            const Icon(Icons.view_sidebar_outlined),
            '信息面板',
            widget.onToggleSidePanel,
          ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, Color color) {
    final playback = widget.playerController.playback;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _progressRow(context, color),
        Row(
          children: [
            Observer(builder: (context) {
              return _iconButton(
                context,
                Icon(playback.playing
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_arrow_rounded),
                playback.playing ? '暂停' : '播放',
                () => widget.playerController.playOrPause(),
              );
            }),
            _iconButton(
              context,
              Image.asset(
                'assets/images/forward_80.png',
                width: 24,
                height: 24,
                color: Colors.white,
              ),
              '跳过片头',
              widget.skipOP,
            ),
            if (isDesktop())
              _volumeButton(context),
            _speedButton(context),
            const Spacer(),
            _iconButton(
              context,
              const Icon(Icons.photo_camera_outlined),
              '截图',
              widget.handleScreenShot,
            ),
            if (isDesktop())
              _iconButton(
                context,
                const Icon(Icons.photo_library_outlined),
                '挑选截图',
                widget.showScreenshotCandidates,
              ),
            _superResolutionButton(context),
            _iconButton(
              context,
              const Icon(Icons.info_outline),
              '视频详情',
              widget.showVideoInfo,
            ),
            _iconButton(
              context,
              const Icon(Icons.timer_outlined),
              '定时关闭',
              () => _openMenu(_showSleepTimerSheet),
            ),
            _iconButton(
              context,
              const Icon(Icons.lock_outline),
              '锁定控制',
              () {
                setState(() {
                  widget.playerController.panel.lockPanel = true;
                });
              },
            ),
            if (Platform.isAndroid)
              _iconButton(
                context,
                const Icon(Icons.picture_in_picture_alt),
                '画中画',
                () => widget.enterAndroidPictureInPicture(),
              ),
            Observer(builder: (context) {
              return _iconButton(
                context,
                Icon(widget.playerPageController.isFullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen),
                '全屏',
                widget.handleFullscreen,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _progressRow(BuildContext context, Color color) {
    final playback = widget.playerController.playback;
    return Row(
      children: [
        Expanded(
          child: Observer(builder: (context) {
            final duration = playback.duration;
            final position = playback.currentPosition;
            final maxMs =
                duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
            return Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    durationToString(position),
                    style: TextStyle(color: color, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: position.inMilliseconds
                        .clamp(0, maxMs)
                        .toDouble(),
                    max: maxMs.toDouble(),
                    onChangeStart: (_) => widget.handleProgressBarDragStart(),
                    onChanged: (value) {
                      playback.currentPosition =
                          Duration(milliseconds: value.round());
                    },
                    onChangeEnd: (value) {
                      widget.playerController
                          .seek(Duration(milliseconds: value.round()));
                      widget.handleProgressBarDragEnd(false);
                    },
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    durationToString(duration),
                    style: TextStyle(color: color, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _volumeButton(BuildContext context) {
    return PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      child: Observer(builder: (context) {
        return SizedBox(
          width: 120,
          child: Slider(
            value: widget.playerController.playback.volume
                .clamp(0.0, 100.0)
                .toDouble(),
            max: 100,
            onChanged: (value) {
              widget.playerController.setVolumeDuringGesture(value);
            },
            onChangeEnd: (value) {
              widget.playerController.finishVolumeGesture();
            },
          ),
        );
      }),
    );
  }

  Widget _speedButton(BuildContext context) {
    return PlayerPanelHoldMenuAnchor(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      onVisibilityChanged: widget.onMenuVisibilityChanged,
      builder: (context, showMenu) {
        return _iconButton(
          context,
          const Icon(Icons.speed_rounded),
          '倍速',
          showMenu,
        );
      },
      menuChildren: [
        for (final speed in defaultPlaySpeedList)
          EmoMenuItem(
            label: '${speed}x',
            onPressed: () {
              EmoDialog.dismiss();
              widget.setPlaybackSpeed(speed);
            },
          ),
      ],
    );
  }

  Widget _superResolutionButton(BuildContext context) {
    return PlayerPanelHoldMenuAnchor(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      onVisibilityChanged: widget.onMenuVisibilityChanged,
      builder: (context, showMenu) {
        return Observer(builder: (context) {
          final mode = widget.playerController.playback.superResolutionMode;
          return _iconButton(
            context,
            Icon(
              Icons.auto_awesome,
              color: mode == SuperResolutionMode.off ? null : Colors.lightBlue,
            ),
            '超分辨率',
            showMenu,
          );
        });
      },
      menuChildren: [
        for (final mode in SuperResolutionMode.values)
          EmoMenuItem(
            label: mode.label,
            onPressed: () {
              EmoDialog.dismiss();
              widget.handleSuperResolutionChange(mode);
            },
          ),
      ],
    );
  }

  Future<void> _openMenu(Future<void> Function() sheet) async {
    widget.onMenuVisibilityChanged(true);
    final hold = widget.acquirePlayerPanelHold();
    try {
      await sheet();
    } finally {
      hold.release();
      if (mounted) {
        widget.onMenuVisibilityChanged(false);
        widget.keyboardFocus.requestFocus();
      }
    }
  }

  Future<void> _showPlaylistSheet() {
    return showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) {
        return Observer(
          builder: (context) {
            final playlist = widget.playerPageController.playlist;
            final current = widget.playerPageController.currentIndex;
            return SafeArea(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlist.length,
                itemBuilder: (context, index) {
                  final item = playlist[index];
                  return ListTile(
                    leading: Icon(
                      index == current
                          ? Icons.play_arrow_rounded
                          : Icons.movie_outlined,
                      color: index == current
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: index == current,
                    onTap: () {
                      EmoDialog.dismiss();
                      widget.onSelectItem(index);
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSleepTimerSheet() {
    return showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) {
        Widget tile(String label, VoidCallback onTap) {
          return ListTile(
            title: Text(label),
            onTap: () {
              EmoDialog.dismiss();
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile('取消定时关闭', () => TimedShutdownService().cancel()),
              tile('15 分钟后暂停', () => _startSleepTimer(15)),
              tile('30 分钟后暂停', () => _startSleepTimer(30)),
              tile('60 分钟后暂停', () => _startSleepTimer(60)),
            ],
          ),
        );
      },
    );
  }

  void _startSleepTimer(int minutes) {
    TimedShutdownService()
        .start(minutes, onExpired: widget.pauseForTimedShutdown);
    EmoDialog.showToast(message: '将在 $minutes 分钟后暂停播放');
  }
}
