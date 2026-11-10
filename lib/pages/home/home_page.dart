import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/bean/widget/state_presentation.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/models/playback_args.dart';
import 'package:emoplay/utils/constants.dart';

/// 首页 Tab.
///
/// 最近播放 / 继续观看 / 快捷打开 / 媒体统计, fed by HistoryStore +
/// LibraryStore (docs/SPEC.md §5). Row interactions ported from 1.x
/// qml/HomePage.qml + qml/HistoryRow.qml: a history row plays its entry at
/// the stored position (startAt>0 -> openAt semantics); the remove button
/// drops only the history record, never the media file.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MediaStores _stores;
  static const int _recentLimit = 6;
  bool _showAllHistory = false;

  @override
  void initState() {
    super.initState();
    _stores = MediaStores.instance;
  }

  /// 1.x Main.qml openMedia(): startAt > 0 becomes openAt(path, seconds);
  /// the player page turns [LocalFilePlaybackArgs.startAt] into the
  /// deferred resume seek (SPEC §4.4).
  void _play(HistoryEntry entry) {
    context.navigate(
      '/tab/player/',
      arguments: LocalFilePlaybackArgs(
        path: entry.path,
        title: entry.title,
        startAt: entry.position,
      ),
    );
  }

  Future<void> _pickMediaFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...MediaClassifier.videoExtensions,
        ...MediaClassifier.audioExtensions,
      ],
      withData: false,
    );
    final paths = result?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) {
      return;
    }
    final path = paths.first;
    if (!mounted) {
      return;
    }
    context.navigate(
      '/tab/player/',
      arguments: LocalFilePlaybackArgs(
        path: path,
        title: path.split('/').last,
      ),
    );
  }

  Future<void> _addMediaFolder() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      return;
    }
    _stores.library.addDirectory(directory);
  }

  String _relativeTime(String iso) {
    if (iso.isEmpty) {
      return '未知时间';
    }
    final then = DateTime.tryParse(iso);
    if (then == null) {
      return '未知时间';
    }
    final minutes =
        DateTime.now().difference(then).inMinutes.abs();
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return '$minutes 分钟前';
    }
    final hours = minutes ~/ 60;
    if (hours < 24) {
      return '$hours 小时前';
    }
    final days = hours ~/ 24;
    if (days < 30) {
      return '$days 天前';
    }
    final local = then.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _scanLabel() {
    final store = _stores.library;
    if (store.isScanning) {
      return '正在扫描 · 已发现 ${store.scanFileCount} 个文件';
    }
    if (store.directories.isEmpty) {
      return '尚未添加媒体目录';
    }
    return '空闲';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _stores.history,
          _stores.library,
          _stores.thumbnails,
        ]),
        builder: (context, _) {
          final history = _stores.history.entries;
          final continueWatching = history
              .where((entry) =>
                  entry.position > 0 &&
                  entry.duration > 0 &&
                  entry.position < entry.duration)
              .toList();
          final recent =
              _showAllHistory ? history : history.take(_recentLimit).toList();
          // Rows show a generated frame when ffmpeg is available; the
          // requests dedupe inside the service and the AnimatedBuilder above
          // re-runs on each ready notification.
          for (final entry in [
            ...continueWatching.take(_recentLimit),
            ...recent,
          ]) {
            _stores.thumbnails.requestThumbnail(entry.path);
          }

          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- header + quick open, side by side on wide windows ----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '欢迎回来',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$appName · 本地媒体播放器',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wide)
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [_quickActions()],
                        ),
                    ],
                  ),
                  if (!wide) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [_quickActions()],
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ---- continue watching ----
                  _section(
                    context,
                    title: '继续观看',
                    icon: Icons.play_circle_outline_rounded,
                    child: continueWatching.isEmpty
                        ? const GeneralEmptyState(
                            compact: true,
                            icon: Icons.history_rounded,
                            title: '暂无未看完的媒体',
                          )
                        : Column(
                            children: [
                              for (final entry in continueWatching)
                                _HistoryRow(
                                  entry: entry,
                                  thumbnail: _stores.thumbnails
                                      .cachedThumbnailPath(entry.path),
                                  timeText: _relativeTime(entry.lastPlayedAt),
                                  highlightProgress: true,
                                  onPlay: () => _play(entry),
                                  onRemove: () =>
                                      _stores.history.removeEntry(entry.path),
                                ),
                            ],
                          ),
                  ),
                  _section(
                    context,
                    title: '最近播放',
                    icon: Icons.schedule_rounded,
                    child: history.isEmpty
                        ? GeneralEmptyState(
                            compact: true,
                            icon: Icons.movie_outlined,
                            title: '播放过的媒体会出现在这里',
                            actions: [
                              // Kazumi 空态按钮 idiom（StateActionButton，
                              // 48px 药丸），普通 FilledButton 观感偏小。
                              StateActionButton.tonal(
                                onPressed: _pickMediaFile,
                                icon: Icons.open_in_new_rounded,
                                text: '选择媒体文件',
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              for (final entry in recent)
                                _HistoryRow(
                                  entry: entry,
                                  thumbnail: _stores.thumbnails
                                      .cachedThumbnailPath(entry.path),
                                  timeText: _relativeTime(entry.lastPlayedAt),
                                  onPlay: () => _play(entry),
                                  onRemove: () =>
                                      _stores.history.removeEntry(entry.path),
                                ),
                              if (history.length > _recentLimit)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => setState(
                                        () => _showAllHistory =
                                            !_showAllHistory),
                                    child: Text(_showAllHistory
                                        ? '收起'
                                        : '查看全部（${history.length}）'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  _section(
                    context,
                    title: '媒体统计',
                    icon: Icons.donut_small_rounded,
                    child: _statsCard(context),
                  ),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _quickActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _pickMediaFile,
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('选择媒体文件'),
        ),
        OutlinedButton.icon(
          onPressed: _addMediaFolder,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('添加媒体文件夹'),
        ),
      ],
    );
  }

  Widget _statsCard(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _stores.library.entryList;
    final videoCount =
        entries.where((entry) => entry.type == 'video').length;
    final audioCount =
        entries.where((entry) => entry.type == 'audio').length;
    final directoryCount = _stores.library.directories.length;
    return TonalCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(context, Icons.videocam_rounded, '视频', '$videoCount'),
              _stat(context, Icons.audiotrack_rounded, '音频', '$audioCount'),
              _stat(context, Icons.folder_rounded, '媒体目录', '$directoryCount'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _scanLabel(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _stores.library.isScanning
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

/// One "recently played" row (1.x qml/HistoryRow.qml): thumbnail, title,
/// path, progress and last-played time. All actions are emitted upwards; the
/// row itself only reads the stores.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.thumbnail,
    required this.timeText,
    required this.onPlay,
    required this.onRemove,
    this.highlightProgress = false,
  });

  final HistoryEntry entry;

  /// Generated frame (cached thumbnail path, empty while pending/unavailable).
  final String thumbnail;

  /// Relative last-played text (1.x HistoryRow.relativeTime).
  final String timeText;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  /// Continue-watching rows emphasize the progress bar.
  final bool highlightProgress;

  String _formatTime(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      return '0:00';
    }
    final total = seconds.floor();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    String pad(int value) => value.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${pad(minutes)}:${pad(secs)}'
        : '$minutes:${pad(secs)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProgress =
        entry.duration > 0 && entry.position > 0 && entry.position < entry.duration;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Thumbnail (or type placeholder) in a fixed 16:9 frame.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 64,
                    height: 40,
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: thumbnail.isEmpty
                        ? Icon(
                            Icons.play_circle_outline_rounded,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : Image.file(
                            File(thumbnail),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.play_circle_outline_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasProgress && highlightProgress) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value:
                                (entry.position / entry.duration).clamp(0.0, 1.0),
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  hasProgress
                      ? '${_formatTime(entry.position)} / ${_formatTime(entry.duration)}'
                      : timeText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '从历史中移除',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
