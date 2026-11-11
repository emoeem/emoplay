// M5-T3 常驻迷你条（docs/EMOPLAY-3.0-ROADMAP.md §五：非播放页常驻迷你条）
// — 1.x 没有对应件，交互参考 PiliPlus 的音频页底栏模式（M5 行）：离开播放
// 页后当前曲目继续播，非播放页底部显示当前曲目/播放暂停/进度，点击回播放
// 页。
//
// 数据源全部来自 tab 作用域单例（index_module.dart）：
//   - PlayerPageController：会话与当前曲目（title/currentIndex/pageCurrent），
//   - PlayerController：播放态（playing/currentPosition/duration）与
//     playOrPause()。
// 可见性条件：`currentIndex >= 0 && !pageCurrent` —— 有活动条目且不在播放
// 页。播放页自身（pageCurrent）与空闲态（currentIndex == -1）都返回
// SizedBox.shrink()，shell 布局不受影响。视频条目同样适用（标题/进度/暂停
// 均通用），文件名保留 music_mini_bar 与路线图一致。
//
// 挂载（pages/menu/menu.dart）：竖屏在 NavigationBar 之上，横屏在
// outlet 之下；onOpenPlayer 由 shell 注入 _selectDestination(_playerTabIndex)
// —— 与点 tab 完全同一条切页路径。缺省回调（测试/无 shell 挂载）走
// context.navigate('/tab/player/')。
library;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';

class MusicMiniBar extends StatelessWidget {
  const MusicMiniBar({super.key, this.onOpenPlayer});

  /// Shell-provided "return to the player page" (menu.dart passes its tab
  /// switch). Null → default root-level navigate (tests / bare mounts).
  final VoidCallback? onOpenPlayer;

  /// 播放页 tab 在 router.dart menu 顺序里的路径。
  static const String _playerRoute = '/tab/player/';

  /// mm:ss（负值夹 0；时长未知时由调用方不显示）。
  static String formatClock(Duration duration) {
    final total = duration.inMilliseconds < 0
        ? 0
        : duration.inMilliseconds ~/ 1000;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _open(BuildContext context) {
    final callback = onOpenPlayer;
    if (callback != null) {
      callback();
      return;
    }
    context.navigate(_playerRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final page = inject<PlayerPageController>();
        final player = inject<PlayerController>();
        // 非播放页 + 有活动条目才显示（见文件头可见性条件）。
        final visible = page.currentIndex >= 0 && !page.pageCurrent;
        if (!visible) {
          return const SizedBox.shrink();
        }
        final position = player.playback.currentPosition;
        final duration = player.playback.duration;
        final progress = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        final title = page.title;
        return Material(
          key: const ValueKey('music_mini_bar'),
          color: const Color(0xF0101014),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _open(context),
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          Icons.music_note_rounded,
                          size: 20,
                          color: const Color(0xFF4f8cff),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title.isNotEmpty ? title : '正在播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFe8e8ee),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${formatClock(position)} / ${formatClock(duration)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8a8a96),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const ValueKey('music_mini_bar_play_pause'),
                          tooltip: player.playback.playing ? '暂停' : '播放',
                          icon: Icon(
                            player.playback.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 26,
                            color: const Color(0xFFe8e8ee),
                          ),
                          onPressed: player.playOrPause,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: const Color(0xFF2a2a32),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF4f8cff)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
