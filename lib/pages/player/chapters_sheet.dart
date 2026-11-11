import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_chapters_controller.dart';
import 'package:emoplay/utils/format.dart';

/// 章节列表面板（M3-T2 章节导航）。
///
/// 与播放列表面板（player_item_panel.dart `_showPlaylistSheet`）同款 Kazumi
/// 交互：底部自适应面板 + ListTile，当前章节高亮（selected + 播放图标），
/// 点击跳转到该章节开头后收起面板。入口在「更多选项」菜单，且仅在当前
/// 媒体存在章节时显示（无章节的文件优雅隐藏，见 player_item_panel.dart
/// `_moreMenuItems`）；面板自身为空时也保持空白而非报错。
Future<void> showChaptersSheet(
  BuildContext context, {
  required PlayerChaptersController chapters,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) {
      return Observer(
        builder: (context) {
          final list = chapters.chapters;
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final chapter = list[index];
                final isCurrent = index == chapters.currentIndex;
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
                              '${index + 1}',
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
                    chapter.title.isEmpty ? '章节 ${index + 1}' : chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: chapter.endTime != null
                      ? Text(
                          '${durationToString(chapter.startTime)} - '
                          '${durationToString(chapter.endTime!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : Text(
                          durationToString(chapter.startTime),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                  selected: isCurrent,
                  onTap: () {
                    EmoDialog.dismiss();
                    chapters.jumpToChapter(index);
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
