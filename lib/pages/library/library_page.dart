import 'package:flutter/material.dart';

import 'package:emoplay/bean/widget/empty_state_widget.dart';

/// 媒体库 Tab.
///
/// M1 skeleton: directory management, video/audio filtering, sorting, search,
/// scan progress and the thumbnail grid arrive with LibraryStore +
/// ThumbnailService in S4 (docs/SPEC.md §5).
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '管理媒体目录',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: GeneralEmptyState(
        icon: Icons.video_library_outlined,
        title: '媒体库尚未扫描',
        actions: [
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加媒体目录'),
          ),
        ],
      ),
    );
  }
}
