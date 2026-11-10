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
///
/// Layout follows the PiliPlus video page: gradient scrims behind the two
/// bars (never a full-surface dim), bars padded by the system insets while
/// the window is not fullscreen, and on phones the secondary actions move
/// into a "more" sheet so the transport row never overflows.
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
    this.onLoadSubtitle,
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

  /// Opens the external-subtitle picker for the current media (M3 sub-add
  /// side-load; null hides the panel entry).
  final VoidCallback? onLoadSubtitle;
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
  static const _iconColor = Colors.white;

  bool get _fullscreen => widget.playerPageController.isFullscreen;

  /// System insets while the bars are visible. Fullscreen playback runs
  /// immersive (bars hidden), so the bars hug the edges; otherwise the panel
  /// clears the status bar and the gesture navigation area (edge-to-edge).
  EdgeInsets get _systemInsets =>
      _fullscreen ? EdgeInsets.zero : MediaQuery.viewPaddingOf(context);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.panelVisibilityController,
      child: Observer(builder: (context) {
        final visible = widget.playerController.panel.showVideoController;
        return IgnorePointer(
          ignoring: !visible,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _topBar(context),
              _bottomBar(context),
            ],
          ),
        );
      }),
    );
  }

  /// Compact icon button: PiliPlus bottom controls are 30-42px, so a phone
  /// transport row fits without spilling.
  Widget _iconButton(
    BuildContext context,
    Widget icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool compact = false,
    double? iconSize,
  }) {
    return IconButton(
      icon: icon,
      color: _iconColor,
      tooltip: tooltip,
      iconSize: iconSize,
      constraints: compact
          ? const BoxConstraints(minWidth: 40, minHeight: 40)
          : null,
      padding: EdgeInsets.zero,
      visualDensity: compact ? VisualDensity.compact : null,
      onPressed: onPressed,
    );
  }

  Widget _topBar(BuildContext context) {
    final title = widget.playerController.mediaTitle;
    final insets = _systemInsets;
    return Container(
      // Top scrim (PiliPlus app_bar_ani): readable title over any frame,
      // without dimming the whole picture.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.72), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(4, insets.top + 4, 4, 14),
      child: Row(
        children: [
          _iconButton(
            context,
            const Icon(Icons.arrow_back),
            '返回',
            widget.onBackPressed,
            compact: true,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: _iconColor, fontSize: 16),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          _iconButton(
            context,
            const Icon(Icons.chevron_left),
            '上一个',
            widget.onPrevItem,
            compact: true,
          ),
          _iconButton(
            context,
            const Icon(Icons.chevron_right),
            '下一个',
            widget.onNextItem,
            compact: true,
          ),
          if (isDesktop())
            _iconButton(
              context,
              const Icon(Icons.subtitles_outlined),
              '加载字幕',
              widget.onLoadSubtitle,
            ),
          _iconButton(
            context,
            const Icon(Icons.video_library_rounded),
            '播放列表',
            () => _openMenu(_showPlaylistSheet),
            compact: true,
          ),
          if (widget.onToggleSidePanel != null)
            _iconButton(
              context,
              const Icon(Icons.view_sidebar_outlined),
              '信息面板',
              widget.onToggleSidePanel,
              compact: true,
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final playback = widget.playerController.playback;
    final insets = _systemInsets;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.72), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _progressRow(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 6, 4),
            child: Row(
              children: [
                Observer(builder: (context) {
                  return _iconButton(
                    context,
                    Icon(playback.playing
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_arrow_rounded),
                    playback.playing ? '暂停' : '播放',
                    () => widget.playerController.playOrPause(),
                    compact: true,
                  );
                }),
                _iconButton(
                  context,
                  Image.asset(
                    'assets/images/forward_80.png',
                    width: 22,
                    height: 22,
                    color: _iconColor,
                  ),
                  '跳过片头',
                  widget.skipOP,
                  compact: true,
                ),
                _speedButton(context),
                if (isDesktop()) ...[
                  _volumeButton(context),
                  _superResolutionButton(context),
                  _iconButton(
                    context,
                    const Icon(Icons.photo_camera_outlined),
                    '截图',
                    widget.handleScreenShot,
                  ),
                  _iconButton(
                    context,
                    const Icon(Icons.photo_library_outlined),
                    '挑选截图',
                    widget.showScreenshotCandidates,
                  ),
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
                  if (Platform.isAndroid)
                    _iconButton(
                      context,
                      const Icon(Icons.picture_in_picture_alt),
                      '画中画',
                      () => widget.enterAndroidPictureInPicture(),
                    ),
                ] else
                  _iconButton(
                    context,
                    const Icon(Icons.photo_camera_outlined),
                    '截图',
                    widget.handleScreenShot,
                    compact: true,
                  ),
                const Spacer(),
                if (!isDesktop())
                  _iconButton(
                    context,
                    const Icon(Icons.more_vert_rounded),
                    '更多',
                    () => _openMenu(_showMoreSheet),
                    compact: true,
                  ),
                _lockButton(context),
                Observer(builder: (context) {
                  return _iconButton(
                    context,
                    Icon(widget.playerPageController.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen),
                    '全屏',
                    widget.handleFullscreen,
                    compact: true,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 锁定控制: a toggle with visible state — the previous lock-only button had
  /// no unlock affordance (fullscreen change resets the lock implicitly).
  Widget _lockButton(BuildContext context) {
    return Observer(builder: (context) {
      final locked = widget.playerController.panel.lockPanel;
      return _iconButton(
        context,
        Icon(locked ? Icons.lock_rounded : Icons.lock_outline),
        locked ? '解除锁定' : '锁定控制',
        () {
          widget.playerController.panel.lockPanel = !locked;
        },
        compact: true,
      );
    });
  }

  Widget _progressRow(BuildContext context) {
    final playback = widget.playerController.playback;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
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
                    width: 46,
                    child: Text(
                      durationToString(position),
                      style:
                          const TextStyle(color: _iconColor, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: position.inMilliseconds
                            .clamp(0, maxMs)
                            .toDouble(),
                        max: maxMs.toDouble(),
                        onChangeStart: (_) =>
                            widget.handleProgressBarDragStart(),
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
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      durationToString(duration),
                      style:
                          const TextStyle(color: _iconColor, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _volumeButton(BuildContext context) {
    return PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      child: Observer(builder: (context) {
        return SizedBox(
          width: 120,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
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
          compact: true,
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
              color: mode == SuperResolutionMode.off ? _iconColor : Colors.lightBlue,
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

  // ---- mobile "more" sheet ------------------------------------------------

  /// Phone transport row keeps six controls (PiliPlus budget); everything
  /// else lives here.
  Future<void> _showMoreSheet() {
    final playback = widget.playerController.playback;
    return showAdaptiveBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Observer(
            builder: (context) {
              final mode = playback.superResolutionMode;
              Widget tile(
                IconData icon,
                String label,
                VoidCallback onTap, {
                bool selected = false,
              }) {
                return ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: selected
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    EmoDialog.dismiss();
                    onTap();
                  },
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onLoadSubtitle != null)
                    tile(
                      Icons.subtitles_outlined,
                      '加载字幕',
                      widget.onLoadSubtitle!,
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '超分辨率',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  for (final candidate in SuperResolutionMode.values)
                    tile(
                      Icons.auto_awesome,
                      candidate.label,
                      () => widget.handleSuperResolutionChange(candidate),
                      selected: mode == candidate,
                    ),
                  const Divider(height: 1),
                  tile(Icons.info_outline, '视频详情', widget.showVideoInfo),
                  tile(
                    Icons.timer_outlined,
                    '定时关闭',
                    () => _openMenu(_showSleepTimerSheet),
                  ),
                  tile(
                    widget.playerController.panel.lockPanel
                        ? Icons.lock_open_rounded
                        : Icons.lock_outline,
                    widget.playerController.panel.lockPanel
                        ? '解除锁定'
                        : '锁定控制',
                    () {
                      widget.playerController.panel.lockPanel =
                          !widget.playerController.panel.lockPanel;
                    },
                  ),
                  if (Platform.isAndroid)
                    tile(
                      Icons.picture_in_picture_alt,
                      '画中画',
                      () => widget.enterAndroidPictureInPicture(),
                    ),
                ],
              );
            },
          ),
        );
      },
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
