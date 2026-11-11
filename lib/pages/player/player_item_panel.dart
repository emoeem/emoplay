import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/appbar/drag_to_move_bar.dart';
import 'package:emoplay/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/emo_menu.dart';
import 'package:emoplay/bean/widget/embedded_native_control_area.dart';
import 'package:emoplay/bean/widget/play_pause_icon.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/music_queue.dart';
import 'package:emoplay/pages/player/chapters_sheet.dart';
import 'package:emoplay/pages/player/music_queue_panel.dart';
import 'package:emoplay/pages/player/controller/ab_loop_model.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_panel_hold.dart';
import 'package:emoplay/pages/player/player_progress_bar.dart';
import 'package:emoplay/pages/player/player_screenshot_controls.dart';
import 'package:emoplay/pages/player/player_transport_bar.dart';
import 'package:emoplay/pages/player/subtitles_sheet.dart';
import 'package:emoplay/pages/player/controller/player_aspect_ratio.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/services/player/pip_utils.dart';
import 'package:emoplay/services/player/timed_shutdown_service.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/utils/device.dart';
import 'package:emoplay/utils/format.dart';

/// Player control panel for EmoPlay.
///
/// The two bars copy the Kazumi composition slot by slot
/// (Kazumi@7265274 player_item_panel.dart `_buildBottomControls` /
/// `_buildTopControls`): the bottom bar is a [PlayerPanelHoldMouseRegion]
/// around a [PlayerTransportBar] (play/pause with [PlayPauseIcon], next
/// item, an [Observer]-scoped [PlayerProgressBar] with the seek-drag trio,
/// a tabular-figures time label, the wide controls and fullscreen), and the
/// top bar is back / drag-to-move title / forward / screenshots / PiP / a
/// "more" menu anchor. Danmaku and syncplay entries do not exist in
/// EmoPlay and are intentionally absent; our controller readings replace
/// the Kazumi ones everywhere.
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
  bool get _fullscreen => widget.playerPageController.isFullscreen;

  /// System insets while the bars are visible. Fullscreen playback runs
  /// immersive (bars hidden), so the bars hug the edges; otherwise the panel
  /// clears the status bar and the gesture navigation area (edge-to-edge).
  EdgeInsets get _systemInsets =>
      _fullscreen ? EdgeInsets.zero : MediaQuery.viewPaddingOf(context);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _buildPanel(
          constraints.maxWidth < MediaQuery.textScalerOf(context).scale(600),
        ),
      );

  Widget _buildPanel(bool compact) {
    return FadeTransition(
      opacity: widget.panelVisibilityController,
      child: Observer(builder: (context) {
        final visible = widget.playerController.panel.showVideoController;
        return IgnorePointer(
          ignoring: !visible,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTopControls(compact),
              _buildBottomControls(compact),
            ],
          ),
        );
      }),
    );
  }

  // ---- bottom bar (Kazumi _buildBottomControls) ---------------------------

  Widget _buildBottomControls(bool compact) => Container(
        // Bottom scrim (Kazumi _buildScrim uses Colors.black45).
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black45],
          ),
        ),
        // Our app draws edge-to-edge; Kazumi reaches the same effect with a
        // SafeArea on `!compact && fillsWindow` edges.
        padding: EdgeInsets.only(bottom: _systemInsets.bottom),
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor: (_fullscreen &&
                  !widget.playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: PlayerTransportBar(
            compact: compact,
            timePlacement: PlayerTimeLabelPlacement.forViewport(
              MediaQuery.sizeOf(context),
              desktop: isDesktop(),
            ),
            playPause: IconButton(
              tooltip: widget.playerController.playback.playing ? '暂停' : '播放',
              onPressed: () => widget.playerController.playOrPause(),
              icon: PlayPauseIcon(
                iconColor: Colors.white,
                playing: widget.playerController.playback.playing,
              ),
            ),
            // M3 施工件 C「逐帧」：暂停态才显示的上一帧/下一帧按钮（mpv
            // OSC 惯例位：播放键两侧），播放/加载中整对隐藏。
            frameStepBack: _frameStepButton(forward: false),
            frameStepForward: _frameStepButton(forward: true),
            nextEpisode: IconButton(
              color: Colors.white,
              icon: const Icon(Icons.skip_next_rounded),
              tooltip: '下一集',
              onPressed: widget.onNextItem,
            ),
            // Playback ticks only rebuild the progress bar and its time labels.
            progressBuilder: ({required sideLabels}) => Observer(
                builder: (context) => PlayerProgressBar(
                      sideLabels: sideLabels,
                      progress: widget.playerController.playback.currentPosition,
                      buffered: widget.playerController.playback.buffer,
                      total: widget.playerController.playback.duration,
                      onDragStart: widget.handleProgressBarDragStart,
                      onDragUpdate: (position) => widget
                          .playerController.seeking
                          .updateInteractiveSeek(position),
                      onDragEnd: widget.handleProgressBarDragEnd,
                      onSeek: widget.playerController.seek,
                    )),
            timeLabel: Observer(
                builder: (context) => Text(
                      '${compact ? '    ' : ''}${durationToString(widget.playerController.playback.currentPosition)} / ${durationToString(widget.playerController.playback.duration)}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: !compact && isDesktop() ? 16 : 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    )),
            controls: compact ? const SizedBox.shrink() : _wideControls,
            fullscreen: _buildFullscreenButton(compact),
          ),
        ),
      );

  /// M3 施工件 C「逐帧」：单帧步进按钮。仅暂停且媒体已加载（duration > 0）
  /// 时显示；播放中 mpv 的 frame-step 会先暂停，但按钮跟随暂停态显隐可以让
  /// 入口语义保持"暂停后逐帧检查"。
  Widget _frameStepButton({required bool forward}) {
    return Observer(
      builder: (context) {
        final playback = widget.playerController.playback;
        final visible = !playback.playing && playback.duration > Duration.zero;
        if (!visible) {
          return const SizedBox.shrink();
        }
        return IconButton(
          color: Colors.white,
          icon: Icon(
            forward
                ? Icons.navigate_next_rounded
                : Icons.navigate_before_rounded,
          ),
          tooltip: forward ? '下一帧（.）' : '上一帧（,）',
          onPressed: () => widget.playerController.frameStep(forward ? 1 : -1),
        );
      },
    );
  }

  Widget _buildFullscreenButton(bool compact) {
    if (widget.playerPageController.isPip) {
      return compact ? const Text('    ') : const SizedBox.shrink();
    }
    if (!isDesktop() &&
        widget.fillsWindow &&
        !widget.playerPageController.isFullscreen) {
      return const SizedBox.shrink();
    }
    return IconButton(
      color: Colors.white,
      icon: Icon(widget.playerPageController.isFullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded),
      tooltip: widget.playerPageController.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.handleFullscreen,
    );
  }

  // ---- top bar (Kazumi _buildTopControls) ---------------------------------

  Widget _buildTopControls(bool compact) {
    return Container(
      // Top scrim (Kazumi _buildScrim uses Colors.black45).
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black45, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(top: _systemInsets.top),
      child: EmbeddedNativeControlArea(
        requireOffset: compact || !_fullscreen,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor: (_fullscreen &&
                  !widget.playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
                onPressed: widget.onBackPressed,
              ),
              Expanded(
                child: DragToMoveArea(
                  child: compact
                      ? const SizedBox(height: 40)
                      : Text(
                          ' ${widget.playerController.mediaTitle}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .fontSize,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ),
              _forwardButton(),
              if (isDesktop())
                PlayerScreenshotControls(
                  controller: widget.playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              if ((isDesktop() && (compact || !_fullscreen)) ||
                  Platform.isAndroid)
                _pipButton(),
              _menuButton(
                child: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                ),
                tooltip: '更多选项',
                items: _moreMenuItems(compact),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pipButton() {
    return IconButton(
      onPressed: () async {
        if (isDesktop()) {
          if (widget.playerPageController.isPip) {
            await PipUtils.exitDesktopPIPWindow();
          } else {
            await PipUtils.enterDesktopPIPWindow(
              width: widget.playerController.debug.playerWidth,
              height: widget.playerController.debug.playerHeight,
            );
          }
          widget.playerPageController
              .setPip(!widget.playerPageController.isPip);
          return;
        }
        await widget.enterAndroidPictureInPicture();
      },
      tooltip: '画中画',
      icon: const Icon(
        Icons.picture_in_picture,
        color: Colors.white,
      ),
    );
  }

  Widget _forwardButton() {
    return Tooltip(
      message:
          '快进${widget.playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: _showForwardChange,
        child: IconButton(
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: Colors.white,
            height: 24,
          ),
          onPressed: widget.skipOP,
        ),
      ),
    );
  }

  void _showForwardChange() {
    EmoDialog.show(builder: (context) {
      var input = '';
      return AlertDialog(
        title: const Text('跳过秒数'),
        content: TextField(
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelText:
                widget.playerController.playback.buttonSkipTime.toString(),
          ),
          onChanged: (value) {
            input = value;
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => EmoDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              if (input.isNotEmpty) {
                widget.playerController.setButtonForwardTime(int.parse(input));
              }
              EmoDialog.dismiss();
            },
            child: const Text('确定'),
          ),
        ],
      );
    });
  }

  // ---- wide controls (Kazumi _wideControls, danmaku slots removed) --------

  Widget get _wideControls => Row(children: [
        // Kazumi centers its desktop danmaku controls in this slot; without
        // danmaku the spacer keeps the menus on the right, next to fullscreen.
        const Spacer(),
        _menuButton(
          child: const Text('超分辨率', style: TextStyle(color: Colors.white)),
          items: _superResolutionItems,
        ),
        _menuButton(
          child: Text(
              widget.playerController.playback.playerSpeed == 1
                  ? '倍速'
                  : '${widget.playerController.playback.playerSpeed}x',
              style: const TextStyle(color: Colors.white)),
          items: _speedItems,
        ),
        _menuButton(
          child: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
          tooltip: '视频比例',
          items: _aspectRatioItems,
        ),
        if (widget.onToggleSidePanel != null)
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.menu_open_rounded),
            tooltip: '选集面板',
            onPressed: widget.onToggleSidePanel,
          ),
      ]);

  List<Widget> _choiceItems<T>(
    Iterable<T> values, {
    required String Function(T) label,
    required bool Function(T) selected,
    required void Function(T) onSelected,
  }) =>
      [
        for (final value in values)
          EmoMenuItem(
            onPressed: () => onSelected(value),
            label: label(value),
            selected: selected(value),
          ),
      ];

  List<Widget> get _aspectRatioItems => _choiceItems(
        PlayerAspectRatio.values,
        label: (value) => value.label,
        selected: (value) =>
            value == widget.playerController.panel.aspectRatioMode,
        onSelected: (value) =>
            widget.playerController.panel.aspectRatioMode = value,
      );

  List<Widget> get _speedItems => _choiceItems(
        defaultPlaySpeedList,
        label: (value) => '${value}x',
        selected: (value) =>
            value == widget.playerController.playback.playerSpeed,
        onSelected: widget.setPlaybackSpeed,
      );

  List<Widget> get _superResolutionItems => _choiceItems(
        SuperResolutionMode.values,
        label: (value) => value.label,
        selected: (value) =>
            value == widget.playerController.playback.superResolutionMode,
        onSelected: widget.handleSuperResolutionChange,
      );

  Widget _menuButton(
          {required Widget child,
          required List<Widget> items,
          String? tooltip}) =>
      PlayerPanelHoldMenuAnchor(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
        onVisibilityChanged: widget.onMenuVisibilityChanged,
        builder: (context, toggle) => tooltip == null
            ? TextButton(onPressed: toggle, child: child)
            : IconButton(onPressed: toggle, icon: child, tooltip: tooltip),
        menuChildren: items,
      );

  // ---- "more" menu (Kazumi menuChildren minus danmaku/syncplay, plus our
  // local entries: playlist / prev item / subtitle / mobile screenshots / lock)
  /// M3 施工件 C「A-B 循环」：菜单标签随三态变化（打开菜单时才构建，读到
  /// 的 phase 即当前值）。
  String get _abLoopMenuLabel {
    final abLoop = widget.playerController.abLoop;
    return switch (abLoop.phase) {
      PlayerAbLoopPhase.none => 'A-B 循环：设 A 点',
      PlayerAbLoopPhase.aSet =>
        'A-B 循环：设 B 点（A ${formatAbLoopPosition(abLoop.positionA ?? 0)}）',
      PlayerAbLoopPhase.looping =>
        'A-B 循环：清除（${formatAbLoopPosition(abLoop.positionA ?? 0)} → ${formatAbLoopPosition(abLoop.positionB ?? 0)}）',
    };
  }

  List<Widget> _moreMenuItems(bool compact) {
    final panel = widget.playerController.panel;
    return [
      if (compact) ...[
        SubmenuButton(menuChildren: _aspectRatioItems, child: const Text('视频比例')),
        SubmenuButton(menuChildren: _speedItems, child: const Text('倍速')),
        SubmenuButton(
            menuChildren: _superResolutionItems, child: const Text('超分辨率')),
      ],
      if (widget.onLoadSubtitle != null)
        EmoMenuItem(
          onPressed: widget.onLoadSubtitle,
          label: '加载字幕',
        ),
      // M3 字幕管理：字幕轨道切换面板（含关闭字幕与加载外挂字幕行）。
      EmoMenuItem(
        onPressed: () => _openMenu(_showSubtitlesSheet),
        label: '字幕轨道',
      ),
      EmoMenuItem(
        onPressed: () => _openMenu(_showPlaylistSheet),
        // M5-T1：music 形态（audioMode）入口语义为队列（打开的是带循环
        // 模式切换的音乐队列面板）；视频形态维持「播放列表」。
        label: MediaStores.instance.music.audioMode ? '播放队列' : '播放列表',
      ),
      // M5-T1 循环模式：三态循环入口（标签随当前值变化，打开菜单时才构建
      // ——A-B 循环同款约定）。none→single→playlist→none。
      EmoMenuItem(
        onPressed: _cycleLoopMode,
        label:
            '循环模式：${MediaStores.instance.settings.playlistMode.label}',
      ),
      // M3-T2 章节导航：无章节的文件不显示入口（读取该 observable 的面板
      // Observer 会在章节加载/清空时自动重建菜单）。
      if (widget.playerController.chapters.hasChapters)
        EmoMenuItem(
          onPressed: () => _openMenu(_showChaptersSheet),
          label: '章节',
        ),
      EmoMenuItem(
        onPressed: widget.onPrevItem,
        label: '上一集',
      ),
      // M3 施工件 C「A-B 循环」：三态入口（设 A → 设 B → 清除），标签随
      // 当前阶段变化；拒绝（B 早于 A 等）由 HUD 反馈。
      EmoMenuItem(
        onPressed: () => widget.playerController.cycleAbLoop(),
        label: _abLoopMenuLabel,
      ),
      EmoMenuItem(
        onPressed: widget.showVideoInfo,
        label: '视频详情',
      ),
      if (!isDesktop()) ...[
        EmoMenuItem(
          onPressed: widget.handleScreenShot,
          label: '截图',
        ),
        EmoMenuItem(
          onPressed: widget.showScreenshotCandidates,
          label: '挑选截图',
        ),
      ],
      EmoMenuItem(
        onPressed: () {
          panel.lockPanel = !panel.lockPanel;
        },
        label: panel.lockPanel ? '解除锁定' : '锁定控制',
      ),
      _timedShutdownSubmenu(),
    ];
  }

  Widget _timedShutdownSubmenu() {
    return SubmenuButton(
      menuChildren: [
        EmoMenuItem(
          onPressed: TimedShutdownService().cancel,
          label: '不开启',
          selected: !TimedShutdownService().isActive,
        ),
        for (final int minutes in [15, 30, 60])
          EmoMenuItem(
            onPressed: () {
              TimedShutdownService().start(minutes,
                  onExpired: widget.pauseForTimedShutdown);
              EmoDialog.showToast(
                  message:
                      '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭');
            },
            label: '$minutes 分钟',
            selected: TimedShutdownService().setMinutes == minutes,
          ),
        EmoMenuItem(
          onPressed: () {
            TimedShutdownService.showCustomTimerDialog(
              onExpired: widget.pauseForTimedShutdown,
            );
          },
          label: '自定义',
        ),
      ],
      child: ValueListenableBuilder<int>(
        valueListenable: TimedShutdownService().remainingSecondsNotifier,
        builder: (context, remainingSeconds, _) => Text(
          remainingSeconds > 0
              ? "定时关闭 (${TimedShutdownService().formatRemainingTime()})"
              : "定时关闭",
        ),
      ),
    );
  }

  // ---- sheets --------------------------------------------------------------

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

  Future<void> _showChaptersSheet() {
    return showChaptersSheet(
      context,
      chapters: widget.playerController.chapters,
    );
  }

  Future<void> _showSubtitlesSheet() {
    return showSubtitlesSheet(
      context,
      subtitles: widget.playerController.subtitles,
      onLoadSubtitle: widget.onLoadSubtitle,
    );
  }

  /// M5-T1 循环模式三态循环：切换即落盘（settings.json behavior 段）并对
  /// 存活的当前 Player 即时下发 media_kit setPlaylistMode；下一个 Player
  /// 创建时（createVideoController）也会重新读取。写失败照常上报，内存态
  /// 保持权威（general_settings _persistBehavior 同契约）。
  void _cycleLoopMode() {
    final settings = MediaStores.instance.settings;
    settings.playlistMode = queueLoopModeCycle(settings.playlistMode);
    if (!settings.save()) {
      EmoDialog.showToast(message: '设置保存失败：${settings.filePath}');
    }
    unawaited(widget.playerController.playback.applyPlaylistMode());
  }

  Future<void> _showPlaylistSheet() {
    // M5-T1：music 形态走队列面板（底板同源：showAdaptiveBottomSheet +
    // Observer 列表，加三态循环模式头部）；视频形态维持既有播放列表面板。
    if (MediaStores.instance.music.audioMode) {
      return showMusicQueueSheet(
        context: context,
        playerPageController: widget.playerPageController,
        onSelectItem: widget.onSelectItem,
        onLoopModeChanged: (_) => unawaited(
          widget.playerController.playback.applyPlaylistMode(),
        ),
      );
    }
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
}
