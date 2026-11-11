import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_subtitles_controller.dart';
import 'package:emoplay/pages/player/controller/player_subtitles_model.dart';

/// 字幕轨道面板（M3 字幕管理）。
///
/// 与章节面板（chapters_sheet.dart）同款 Kazumi 交互：底部自适应面板 +
/// ListTile，当前轨道高亮（selected + 播放图标），点击切换后收起。顶部固定
/// 两个动作行：加载外挂字幕（复用播放页的文件选择器回调，扩展名限定
/// srt/ass/ssa/vtt/sub）与关闭字幕（mpv `sid=no`）。mpv 的 `sid` 属性是选中
/// 状态的真相源（PlayerSubtitlesController 观察），'no' 高亮关闭行、'auto'
/// 或未匹配时不高亮任何轨道（mpv 自动选择的轨道尚未被显式选中）。
Future<void> showSubtitlesSheet(
  BuildContext context, {
  required PlayerSubtitlesController subtitles,
  VoidCallback? onLoadSubtitle,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) {
      return Observer(
        builder: (context) {
          final list = subtitles.tracks;
          final currentId = subtitles.currentSubId;
          // 关闭字幕 +（可选）加载外挂字幕 + N 条轨道。
          final trackOffset = onLoadSubtitle == null ? 1 : 2;
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length + trackOffset,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isOff = currentId == 'no';
                  return ListTile(
                    leading: Icon(
                      Icons.subtitles_off_outlined,
                      color: isOff
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: const Text('关闭字幕'),
                    selected: isOff,
                    onTap: () {
                      EmoDialog.dismiss();
                      subtitles.selectNone();
                    },
                  );
                }
                if (index == 1 && onLoadSubtitle != null) {
                  return ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('加载外挂字幕…'),
                    onTap: () {
                      EmoDialog.dismiss();
                      onLoadSubtitle();
                    },
                  );
                }
                final track = list[index - trackOffset];
                final isCurrent = track.id == currentId;
                return ListTile(
                  leading: isCurrent
                      ? Icon(
                          Icons.play_arrow_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : SizedBox(
                          width: IconTheme.of(context).size ?? 24,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${index - trackOffset + 1}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                  title: Text(
                    describeSubtitleTrack(
                        track.title, track.language, index - trackOffset + 1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: (track.language?.isNotEmpty ?? false)
                      ? Text(track.language!,
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
                  selected: isCurrent,
                  onTap: () {
                    EmoDialog.dismiss();
                    subtitles.select(track);
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
