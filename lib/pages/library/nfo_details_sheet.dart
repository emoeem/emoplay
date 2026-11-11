import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/nfo_meta_cache.dart';
import 'package:emoplay/media/nfo_parser.dart';

// The NFO details sheet (user-added roadmap item M4-T6, 2026-11-12: the
// library grid gains "NFO 数据展示（克制，Kazumi 风格）"). One modal bottom
// sheet in the favorites_sheet idiom (showDragHandle, maxWidth 560): the
// local poster, the parsed fields, and the recorded <thumb> URLs — which
// stay RECORDED ONLY (local-first: nothing is fetched, the URLs are shown
// as text so the user knows what the NFO offers and can fetch it
// themselves).
//
// The badge that opens this sheet only exists where NFO data exists
// (hasNfo), so the sheet always has something to say; a record whose NFO
// was corrupt still opens (kind/title lines degrade, nothing crashes).
class NfoDetailsSheet extends StatelessWidget {
  const NfoDetailsSheet({
    super.key,
    required this.entry,
    required this.info,
  });

  final LibraryEntry entry;
  final NfoInfo info;

  /// Opens the sheet above |context|.
  static Future<void> show(
      BuildContext context, LibraryEntry entry, NfoInfo info) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => NfoDetailsSheet(entry: entry, info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nfo = info.nfo;

    // Head facts: year · rating · genres, then the episode marker, then the
    // aired/premiered date and the studio — whatever exists.
    final facts = <String>[
      if (nfo.year != null) '${nfo.year}',
      if (nfo.rating != null) '★ ${_formatRating(nfo.rating!)}',
      ...nfo.genres,
    ];
    final marker = (nfo.kind == NfoKind.episode &&
            nfo.season != null &&
            nfo.episode != null)
        ? 'S${nfo.season.toString().padLeft(2, '0')}'
            'E${nfo.episode.toString().padLeft(2, '0')}'
        : '';
    final title = nfo.title.isNotEmpty ? nfo.title : entry.title;
    final plot = nfo.plot.isNotEmpty ? nfo.plot : nfo.outline;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 144,
                    child: info.poster.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.movie_rounded,
                              size: 30,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : Image.file(
                            File(info.poster),
                            fit: BoxFit.cover,
                            width: 96,
                            height: 144,
                            errorBuilder: (_, _, _) => Container(
                              color:
                                  theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 30,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          facts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (marker.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          marker,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (nfo.aired.isNotEmpty || nfo.premiered.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nfo.aired.isNotEmpty
                              ? '首播 ${nfo.aired}'
                              : '首播 ${nfo.premiered}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (nfo.studio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nfo.studio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (plot.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('简介', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                plot,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (nfo.uniqueId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'NFO ID：${nfo.uniqueId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (info.showTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '所属剧集：${info.showTitle}（tvshow.nfo）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (nfo.thumbs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('NFO 海报链接', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '仅记录不下载（本地优先）——图片来自同目录的 poster/folder/fanart。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final thumb in nfo.thumbs.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    thumb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              '来源：${p.basename(entry.path)} 所在目录的 NFO 与海报文件（media_nfo.json 缓存）。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRating(double rating) =>
      rating == rating.roundToDouble()
          ? rating.toStringAsFixed(0)
          : rating.toStringAsFixed(1);
}
