// M5-T1 循环/队列模型（docs/EMOPLAY-3.0-ROADMAP.md §五 M5-T1）。
//
// 把 player_playback_controller.dart:443 的 `PlaylistMode.none` 硬编码提升为
// 三态设置（single/playlist/none）后，这里承载三件事：
//
//  1. [QueueLoopMode] —— 设置的取值域与持久化词汇。落 settings.json
//     behavior 段新键 `playlistMode`（§四红线：settings.json 允许追加键，
//     默认值与往返用例进 test/emoplay_settings_test.dart）。默认 `none`
//     保持 1.x/Kazumi 现状（硬编码即 none），老用户行为零变化。
//  2. [queueLoopModeCycle] —— 面板/设置页的循环切换次序。
//  3. [resolveQueueNextIndex] —— 队列续播的纯决策函数：当前曲目播放完毕
//     （completed）后下一首要播的 index，null = 停止。
//
// 与 media_kit 原生 PlaylistMode 的映射在 player_playback_controller.dart
// （applyPlaylistMode 旁的注释）：single 走引擎原生 loop-file；none/playlist
// 保持引擎 loop 关闭——media_kit `open(Media)` 只装一个 entry 的内部
// playlist（real.dart open(): `playlist.add(playable)`），`loop-playlist=yes`
// 会让 mpv 在文件结尾回卷到这唯一 entry、文件自身无限循环，completed/eof
// 永远到不了应用层，队列无法续播。列表循环的回卷因此在应用层实现：队列的
// source of truth 是 PlaybackSession（§四统一模型），每个文件一个 Player
// 实例（player_page.dart _loadCurrent），推进由 PlayerProgressPipeline 在
// completed 时调用 [resolveQueueNextIndex] 完成。纯 Dart、零依赖，测试见
// test/music_queue_test.dart。
library;

/// 循环模式三态（roadmap M5-T1：single/playlist/none）。
enum QueueLoopMode {
  /// 顺序播完整个队列后停止（1.x 现状；引擎 loop-file/loop-playlist 均关）。
  none,

  /// 单曲循环：引擎原生 `loop-file` 重复当前文件，队列不前进。
  single,

  /// 列表循环：队列内顺序推进，末尾回卷到第 0 首（应用层回卷，见文件头）。
  playlist;

  /// settings.json `behavior.playlistMode` 的持久化词汇。
  String get storageValue => name;

  /// 面板/设置页展示标签（zh，跟随播放设置页既有中文文案约定）。
  String get label => switch (this) {
        QueueLoopMode.none => '不循环',
        QueueLoopMode.single => '单曲循环',
        QueueLoopMode.playlist => '列表循环',
      };

  /// 从持久化值恢复；null/未知值/错误类型一律回落默认 `none`（默认值契约，
  /// 老文件与手改文件都安全）。
  static QueueLoopMode fromStorageValue(Object? value) {
    for (final mode in QueueLoopMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return QueueLoopMode.none;
  }
}

/// 循环切换次序：none → single → playlist → none（面板菜单循环项与
/// 设置页下拉共用同一词汇）。
QueueLoopMode queueLoopModeCycle(QueueLoopMode current) {
  final next = (current.index + 1) % QueueLoopMode.values.length;
  return QueueLoopMode.values[next];
}

/// 队列续播决策：`count` 首的队列中第 [currentIndex] 首播完（completed），
/// 返回下一首的 index；null = 停止（不推进）。
///
/// 语义（与 PlayerProgressPipeline 既有行为逐条对齐）：
///  * `autoPlayNext == false`：任何模式都不自动推进——「自动连播」是总闸，
///    与 1.x 的 `nextIndex < length && autoPlayNext` 门一致；列表循环也不
///    例外（用户显式关掉了自动续播）。
///  * `single`：永不推进。引擎原生 loop-file 会一直重复当前文件，理论上
///    completed 不会到达应用层；这里仍显式返回 null，防御未来信号源变化。
///  * `playlist`：顺序推进，末尾（含单曲目队列）回卷到 0。
///  * `none`：顺序推进到队尾后停止（默认行为，即 1.x 现状）。
///  * 越界的 [currentIndex]（含 -1 空闲哨兵）与空队列：null。
///
/// 形态无关：video/music 两形态共用同一策略——循环模式是全局设置，形态
/// （PlaybackSession.isMusic / MusicController.audioMode）只决定 UI（音乐
/// 队列面板）的呈现，不改变续播语义。
int? resolveQueueNextIndex({
  required int currentIndex,
  required int count,
  required QueueLoopMode mode,
  required bool autoPlayNext,
}) {
  if (!autoPlayNext || count <= 0) {
    return null;
  }
  if (mode == QueueLoopMode.single) {
    return null;
  }
  if (currentIndex < 0 || currentIndex >= count) {
    return null;
  }
  final next = currentIndex + 1;
  if (next < count) {
    return next;
  }
  return mode == QueueLoopMode.playlist ? 0 : null;
}
