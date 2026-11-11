// M5-T1 音乐形态队列面板（roadmap §五 M5-T1「music 形态队列面板（复用
// M3-T3 面板组件）」）。M3-T3 悬浮面板未施工，故沿用既有底板——与
// player_item_panel.dart `_showPlaylistSheet` 同源的 showAdaptiveBottomSheet
// + Observer + ListView 结构，不引入新框架；本面板在其上加：
//  1. 头部三态循环模式切换（none/single/playlist，实时落盘 settings.json
//     behavior.playlistMode 并经 onLoopModeChanged 通知调用方对存活 Player
//     即时下发 media_kit setPlaylistMode）；
//  2. 「第 x / 共 n 首」计数与音乐图标语义（区别于视频形态的 movie 图标）。
//
// 队列 source of truth 是 PlaybackSession（§四统一模型）；面板只读
// PlayerPageController.playlist 派生视图，点选仍走 onSelectItem（与视频
// 形态播放列表面板同一动线）。循环模式切换的持久化在此处直接写
// EmoPlaySettings（唯一设置事实源），回调只负责引擎侧即时生效——widget
// 测试据此断言落盘（test/music_queue_test.dart）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/music_queue.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';

/// Opens the music-form queue sheet (same base plate as the video-form
/// playlist sheet in player_item_panel.dart).
Future<void> showMusicQueueSheet({
  required BuildContext context,
  required PlayerPageController playerPageController,
  required Future<void> Function(int index) onSelectItem,
  required ValueChanged<QueueLoopMode> onLoopModeChanged,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) {
      return MusicQueuePanel(
        playerPageController: playerPageController,
        onSelectItem: onSelectItem,
        onLoopModeChanged: onLoopModeChanged,
      );
    },
  );
}

/// The music queue sheet body: header (title + loop-mode selector) over the
/// shared queue list structure.
class MusicQueuePanel extends StatelessWidget {
  const MusicQueuePanel({
    super.key,
    required this.playerPageController,
    required this.onSelectItem,
    required this.onLoopModeChanged,
  });

  final PlayerPageController playerPageController;

  /// Switches the player to the queue entry at [index] (the same seam the
  /// video-form playlist sheet uses: player_item onSelectItem).
  final Future<void> Function(int index) onSelectItem;

  /// Called after a loop-mode change was persisted, so the host can push the
  /// new mode onto the live player (PlayerPlaybackController.applyPlaylistMode).
  final ValueChanged<QueueLoopMode> onLoopModeChanged;

  void _changeLoopMode(QueueLoopMode mode) {
    final settings = MediaStores.instance.settings;
    if (settings.playlistMode == mode) {
      return;
    }
    settings.playlistMode = mode;
    // 写失败照常上报：内存态保持权威（general_settings _persistBehavior 同
    // 契约），引擎侧即时下发仍执行。
    if (!settings.save()) {
      EmoDialog.showToast(message: '设置保存失败：${settings.filePath}');
    }
    onLoopModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: MediaStores.instance.settings,
            builder: (context, _) => _QueueHeader(
              mode: MediaStores.instance.settings.playlistMode,
              onChanged: _changeLoopMode,
            ),
          ),
          Flexible(
            child: Observer(
              builder: (context) {
                final playlist = playerPageController.playlist;
                final current = playerPageController.currentIndex;
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlist.length,
                  itemBuilder: (context, index) {
                    final item = playlist[index];
                    return ListTile(
                      leading: Icon(
                        index == current
                            ? Icons.play_arrow_rounded
                            : Icons.music_note_rounded,
                        color: index == current
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: index == current
                          ? null
                          : Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      selected: index == current,
                      onTap: () {
                        // 与视频形态播放列表面板同一关闭动线（底板语义）。
                        EmoDialog.dismiss();
                        onSelectItem(index);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.mode, required this.onChanged});

  final QueueLoopMode mode;
  final ValueChanged<QueueLoopMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '播放队列',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          // 三态切换（single/playlist/none，roadmap M5-T1）：打开面板时才
          // 构建，读到的即当前持久化值；切换即落盘并即时下发引擎。
          SegmentedButton<QueueLoopMode>(
            segments: [
              for (final value in QueueLoopMode.values)
                ButtonSegment(
                  value: value,
                  label: Text(value.label),
                ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
            ),
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                onChanged(selection.first);
              }
            },
          ),
        ],
      ),
    );
  }
}
