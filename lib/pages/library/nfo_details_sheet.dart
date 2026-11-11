import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/media/episode_grouper.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/media/nfo_meta_cache.dart';
import 'package:emoplay/media/nfo_parser.dart';
import 'package:emoplay/media/online/metadata_provider.dart';
import 'package:emoplay/media/online/online_meta_service.dart';

// The NFO details sheet (user-added roadmap item M4-T6, 2026-11-12: the
// library grid gains "NFO 数据展示（克制，Kazumi 风格）"). One modal bottom
// sheet in the favorites_sheet idiom (showDragHandle, maxWidth 560): the
// local poster, the parsed fields, and the recorded <thumb> URLs — which
// stay RECORDED ONLY (local-first: nothing is fetched, the URLs are shown
// as text so the user knows what the NFO offers and can fetch it
// themselves).
//
// M4-T7 additions (user redirection 2026-11-12, 在线元数据兜底框架): the
// sheet is now openable for EVERY video cell — the badge on an NFO-less
// cell reads 联网补全 — and carries the 「联网补全」 action. The action runs
// the OnlineMetaService gate chain; every outcome is a graceful message,
// and a usable hit renders inline as a separate 联网补全 card (poster URLs
// stay TEXT — no UI-side fetches in this framework round).
//
// For hasNfo entries the service answers localCovered without any request
// (local-first); the sheet keeps showing the local facts either way, so a
// record whose NFO was corrupt still opens (kind/title lines degrade,
// nothing crashes).
class NfoDetailsSheet extends StatefulWidget {
  const NfoDetailsSheet({
    super.key,
    required this.entry,
    this.info,
  });

  final LibraryEntry entry;

  /// The local NFO/poster facts (media_nfo.json); null when the video has
  /// never been scanned (or nothing was found) — the sheet then offers the
  /// online fallback instead of the local fields.
  final NfoInfo? info;

  /// Opens the sheet above |context|.
  static Future<void> show(
      BuildContext context, LibraryEntry entry, NfoInfo? info) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => NfoDetailsSheet(entry: entry, info: info),
    );
  }

  @override
  State<NfoDetailsSheet> createState() => _NfoDetailsSheetState();
}

class _NfoDetailsSheetState extends State<NfoDetailsSheet> {
  /// The online fallback result rendered below the local facts (filled by
  /// the 联网补全 action or by an existing media_online.json record).
  OnlineMetadata? _online;
  bool _onlineBusy = false;

  @override
  void initState() {
    super.initState();
    // An already-cached hit renders immediately (no request — pure map
    // read of media_online.json).
    _online = MediaStores.instance.onlineMeta.infoFor(widget.entry.path)
        ?.metadata;
  }

  /// Runs the online fallback gate chain for this entry. Every status maps
  /// to one graceful message; found/fromCache fill the inline card. Never
  /// throws (OnlineMetaService.lookup is total by contract).
  Future<void> _runOnlineLookup() async {
    if (_onlineBusy) {
      return;
    }
    setState(() => _onlineBusy = true);
    final result = await MediaStores.instance.onlineMeta.lookup(
      widget.entry.path,
      queryText: widget.entry.title,
      episodeHint: parseEpisodeMarker(p.basename(widget.entry.path)) != null,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _onlineBusy = false;
      if (result.metadata != null) {
        _online = result.metadata;
      }
    });
    switch (result.status) {
      case OnlineLookupStatus.disabled:
        EmoDialog.showToast(context: context, message: '在线元数据已关闭：设置 → 在线元数据');
      case OnlineLookupStatus.noKey:
        EmoDialog.showToast(context: context, message: '未配置 TMDB API key：设置 → 在线元数据');
      case OnlineLookupStatus.localCovered:
        EmoDialog.showToast(context: context, message: '本地 NFO 已覆盖该条目，未发起联网查询（本地优先）');
      case OnlineLookupStatus.fromCache:
        EmoDialog.showToast(context: context, message: '来自缓存（media_online.json），未发请求');
      case OnlineLookupStatus.found:
        EmoDialog.showToast(context: context, message: '联网补全完成（TMDB）');
      case OnlineLookupStatus.notFound:
        EmoDialog.showToast(context: context, message: '未找到匹配结果（已记录，不再重复请求）');
      case OnlineLookupStatus.unavailable:
        EmoDialog.showToast(context: context, message: '联网查询失败（断网/超时/无效 key），已降级为本地数据');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final hasNfo = info?.hasNfo == true;
    final nfo = info?.nfo ?? const NfoDocument();

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
    final title = nfo.title.isNotEmpty ? nfo.title : widget.entry.title;
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
                    child: (info?.poster ?? '').isEmpty
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
                            File(info!.poster),
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
            if (!hasNfo) ...[
              const SizedBox(height: 10),
              Text(
                '本条目没有本地 NFO 数据——可用下方联网补全，或自行放置 NFO/海报文件。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasNfo && plot.isNotEmpty) ...[
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
            if (hasNfo && nfo.uniqueId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'NFO ID：${nfo.uniqueId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasNfo && info!.showTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '所属剧集：${info.showTitle}（tvshow.nfo）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasNfo && nfo.thumbs.isNotEmpty) ...[
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
            if (hasNfo) ...[
              const SizedBox(height: 12),
              Text(
                '来源：${p.basename(widget.entry.path)} 所在目录的 NFO 与海报文件（media_nfo.json 缓存）。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // ---- M4-T7: the 联网补全 action (every entry; the gate chain
            // decides what it actually does) ----
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _onlineBusy ? null : _runOnlineLookup,
                  icon: _onlineBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined, size: 18),
                  label: Text(_onlineBusy ? '查询中…' : '联网补全'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasNfo ? '本地优先：已有 NFO 的条目不会联网' : '仅对无本地 NFO 的条目发起查询',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // The online result card (found / fromCache). Poster URL stays
            // TEXT: no UI-side fetches in this framework round.
            if (_online != null) ...[
              const SizedBox(height: 12),
              Text('联网补全结果（${_online!.provider}）',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                [
                  _online!.title,
                  if (_online!.originalTitle.isNotEmpty &&
                      _online!.originalTitle != _online!.title)
                    _online!.originalTitle,
                  if (_online!.year != null) '${_online!.year}',
                  if (_online!.rating != null)
                    '★ ${_formatRating(_online!.rating!)}',
                  if (_online!.mediaType.isNotEmpty) _online!.mediaType,
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              if (_online!.plot.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _online!.plot,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_online!.posterUrl.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '海报：${_online!.posterUrl}（仅记录不下载）',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '已缓存到 media_online.json，再次查看不再发请求。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
