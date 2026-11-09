import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/utils/constants.dart';

/// 首页 Tab.
///
/// M1 skeleton: the 最近播放 / 继续观看 / 媒体统计 sections become live once
/// the JSON stores (HistoryStore / LibraryStore, docs/SPEC.md §7) are ported
/// in S4; the layout shell is already in place.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '欢迎回来',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '$appName · 本地媒体播放器',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _section(
              context,
              title: '继续观看',
              icon: Icons.play_circle_outline_rounded,
              child: GeneralEmptyState(
                icon: Icons.history_rounded,
                title: '暂无观看记录',
                actions: [
                  FilledButton.icon(
                    onPressed: () => context.navigate('/tab/player/'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('打开播放页'),
                  ),
                ],
              ),
            ),
            _section(
              context,
              title: '最近播放',
              icon: Icons.schedule_rounded,
              child: GeneralEmptyState(
                icon: Icons.movie_outlined,
                title: '播放过的视频会出现在这里',
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () => context.navigate('/tab/library/'),
                    icon: const Icon(Icons.video_library_rounded),
                    label: const Text('前往媒体库'),
                  ),
                ],
              ),
            ),
            _section(
              context,
              title: '媒体统计',
              icon: Icons.donut_small_rounded,
              child: TonalCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(context, Icons.videocam_rounded, '视频', '—'),
                    _stat(context, Icons.audiotrack_rounded, '音频', '—'),
                    _stat(context, Icons.folder_rounded, '媒体目录', '—'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleLarge),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
