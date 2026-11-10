import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/models/playback_args.dart';
import 'package:emoplay/services/platform/mobile_media_scanner.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/format.dart';

/// 媒体库 Tab.
///
/// The media folders, their indexed files, search / filter / sort /
/// grid-list switching, scan progress and cancellation. Every piece of state
/// comes from [MediaStores] (LibraryStore + LibraryModel + ThumbnailService)
/// — the page itself keeps no media index. Interaction ported from 1.x
/// qml/LibraryPage.qml: the scan-state label, the directory panel, the
/// cancel/rescan toggle and the grid/list switch.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final MediaStores _stores;
  late final LibraryModel _model;
  bool _showDirectories = false;
  bool _gridView = true;

  /// True while the phone storage discovery walks the volumes.
  bool _mobileScanning = false;

  @override
  void initState() {
    super.initState();
    _stores = MediaStores.instance;
    _model = _stores.libraryModel;
    // Phone one-shot: the very first library visit discovers the storage
    // volumes on its own (only when access was granted before — the automatic
    // path must never open the system permission page).
    if (MobileMediaScanner.isSupported &&
        _stores.library.directories.isEmpty &&
        !GStorage.getSetting(SettingsKeys.mobileAutoScanDone)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scanPhoneMedia(auto: true);
        }
      });
    }
  }

  // ---- phone storage discovery -------------------------------------------

  /// Discovers media folders on the phone's storage volumes and adds them to
  /// the library (addDirectory chains one scan for all of them).
  Future<void> _scanPhoneMedia({bool auto = false}) async {
    final store = _stores.library;
    if (_mobileScanning) {
      return;
    }
    if (auto && !(await MobileMediaScanner.hasStorageAccess())) {
      return;
    }
    if (!auto && !(await MobileMediaScanner.requestStorageAccess())) {
      EmoDialog.showToast(message: '需要"所有文件访问"权限才能扫描手机媒体');
      return;
    }
    setState(() => _mobileScanning = true);
    try {
      final found = await MobileMediaScanner.discoverMediaDirectories();
      if (!mounted) {
        return;
      }
      var added = 0;
      for (final directory in found) {
        if (store.addDirectory(directory.path)) {
          added++;
        }
      }
      await GStorage.putSetting(SettingsKeys.mobileAutoScanDone, true);
      if (!mounted) {
        return;
      }
      if (added == 0 && found.isEmpty) {
        EmoDialog.showToast(message: auto ? '手机上暂未发现媒体文件' : '没有发现新的媒体文件夹');
      } else if (added > 0) {
        EmoDialog.showToast(message: '发现 $added 个媒体文件夹，正在索引…');
      }
    } catch (e) {
      EmoDialog.showToast(message: '扫描手机媒体失败：$e');
    } finally {
      if (mounted) {
        setState(() => _mobileScanning = false);
      }
    }
  }

  /// 1.x: grid cell click -> openMedia(path, 0) — library entries start at
  /// the beginning; resume positions live on the Home history rows.
  void _play(LibraryEntry entry) {
    context.navigate(
      '/tab/player/',
      arguments: LocalFilePlaybackArgs(path: entry.path, title: entry.title),
    );
  }

  Future<void> _addFolder() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      return;
    }
    if (!_stores.library.addDirectory(directory)) {
      return;
    }
    setState(() => _showDirectories = true);
  }

  String _scanStateLabel() {
    final store = _stores.library;
    if (_mobileScanning) {
      return '正在扫描手机存储…';
    }
    if (store.isScanning) {
      return '正在扫描 · 已发现 ${store.scanFileCount} 个媒体文件';
    }
    if (store.lastScanCancelled) {
      return '扫描已取消';
    }
    if (store.directories.isEmpty) {
      return MobileMediaScanner.isSupported ? '尚未扫描手机媒体' : '尚未添加媒体目录';
    }
    return '空闲 · 已索引 ${_model.count} 个媒体文件';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = _stores.library;
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: _gridView ? '切换为列表' : '切换为网格',
            icon: Icon(_gridView
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _model,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _toolbar(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _scanRow(context),
              ),
              if (store.isScanning)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_showDirectories)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _directoryCard(context),
                ),
              Expanded(
                child: _model.count == 0
                    ? _emptyState(context)
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: _gridView
                            ? _grid(context)
                            : _list(context),
                      ),
              ),
              if (_model.count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(
                      '${_model.count} 项',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---- search / type filter / sort ------------------------------------

  Widget _toolbar(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: '搜索标题或路径',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) => _model.filter = value,
          ),
        ),
        DropdownButton<String>(
          value: _model.typeFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('全部类型')),
            DropdownMenuItem(value: 'video', child: Text('视频')),
            DropdownMenuItem(value: 'audio', child: Text('音频')),
          ],
          onChanged: (value) => setState(() => _model.typeFilter = value ?? 'all'),
        ),
        DropdownButton<String>(
          value: _model.sortMode,
          items: const [
            DropdownMenuItem(value: 'title', child: Text('按名称')),
            DropdownMenuItem(value: 'titledesc', child: Text('按名称倒序')),
            DropdownMenuItem(value: 'size', child: Text('按大小')),
            DropdownMenuItem(value: 'recent', child: Text('按最近播放')),
            DropdownMenuItem(value: 'path', child: Text('按路径')),
          ],
          onChanged: (value) =>
              setState(() => _model.sortMode = value ?? 'title'),
        ),
        Text(
          '已索引 ${_model.count} 项',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ---- scan progress + directory actions -------------------------------

  Widget _scanRow(BuildContext context) {
    final theme = Theme.of(context);
    final store = _stores.library;
    final scanning = store.isScanning;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _scanStateLabel(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scanning
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: () => setState(() => _showDirectories = !_showDirectories),
          child: Text('媒体目录 (${store.directories.length})'),
        ),
        OutlinedButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('添加文件夹…'),
        ),
        if (MobileMediaScanner.isSupported)
          OutlinedButton.icon(
            onPressed: _mobileScanning ? null : () => _scanPhoneMedia(),
            icon: const Icon(Icons.smartphone_rounded, size: 18),
            label: const Text('扫描手机媒体'),
          ),
        FilledButton.tonalIcon(
          // 1.x: the scan button flips to cancel while scanning and is
          // disabled with no directories to scan.
          onPressed: store.directories.isEmpty
              ? null
              : () => scanning
                  ? store.cancelScan()
                  : store.requestScan(),
          icon: Icon(
            scanning
                ? Icons.cancel_outlined
                : Icons.refresh_rounded,
            size: 18,
          ),
          label: Text(scanning ? '取消扫描' : '重新扫描'),
        ),
      ],
    );
  }

  Widget _directoryCard(BuildContext context) {
    final theme = Theme.of(context);
    final store = _stores.library;
    return TonalCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('媒体目录', style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '移除目录只会删除索引，不会删除磁盘上的文件。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (store.directories.isEmpty)
            Text(
              '还没有添加媒体目录。',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final directory in store.directories)
              Row(
                children: [
                  const Icon(Icons.folder_rounded,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      directory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '移除索引',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => store.removeDirectory(directory),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  // ---- results ----------------------------------------------------------

  Widget _emptyState(BuildContext context) {
    final store = _stores.library;
    final filtered =
        _model.filter.isNotEmpty || _model.typeFilter != 'all';
    final noDirectories = store.directories.isEmpty;
    return GeneralEmptyState(
      icon: Icons.video_library_outlined,
      title: noDirectories
          ? '媒体库还是空的'
          : (filtered ? '没有匹配的媒体' : '还没有索引到媒体文件'),
      actions: [
        if (noDirectories && MobileMediaScanner.isSupported)
          FilledButton.icon(
            onPressed: _mobileScanning ? null : () => _scanPhoneMedia(),
            icon: const Icon(Icons.smartphone_rounded),
            label: const Text('扫描手机媒体'),
          ),
        FilledButton.icon(
          onPressed: noDirectories && !MobileMediaScanner.isSupported
              ? _addFolder
              : () => store.requestScan(),
          icon: Icon(
            noDirectories && !MobileMediaScanner.isSupported
                ? Icons.add_rounded
                : Icons.refresh_rounded,
          ),
          label: Text(noDirectories && !MobileMediaScanner.isSupported
              ? '添加媒体文件夹'
              : '重新扫描'),
        ),
        if (noDirectories && MobileMediaScanner.isSupported)
          FilledButton.tonalIcon(
            onPressed: _addFolder,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加媒体文件夹'),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    final theme = Theme.of(context);
    final count = _model.count;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 198 / 174,
      ),
      itemCount: count,
      itemBuilder: (context, row) {
        final thumbnail = _model.thumbnailAt(row);
        final isAudio = _model.typeAt(row) == 'audio';
        return _GridCell(
          title: _model.titleAt(row),
          thumbnail: thumbnail,
          isAudio: isAudio,
          onPlay: () => _play(_entryAt(row)),
          placeholder: Icon(
            isAudio ? Icons.audiotrack_rounded : Icons.movie_rounded,
            size: 34,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final count = _model.count;
    return ListView.builder(
      itemCount: count,
      itemExtent: 44,
      itemBuilder: (context, row) {
        final isAudio = _model.typeAt(row) == 'audio';
        final lastPlayed = _model.lastPlayedAt(row);
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            isAudio ? Icons.audiotrack_rounded : Icons.movie_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            _model.titleAt(row),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatBytes(_model.sizeAt(row)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Text(
                  lastPlayed.length >= 10
                      ? lastPlayed.substring(0, 10)
                      : '未播放',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          onTap: () => _play(_entryAt(row)),
        );
      },
    );
  }

  LibraryEntry _entryAt(int row) => LibraryEntry(
        path: _model.pathAt(row),
        title: _model.titleAt(row),
        type: _model.typeAt(row),
        size: _model.sizeAt(row),
        lastPlayed: _model.lastPlayedAt(row),
      );
}

class _GridCell extends StatefulWidget {
  const _GridCell({
    required this.title,
    required this.thumbnail,
    required this.isAudio,
    required this.placeholder,
    required this.onPlay,
  });

  final String title;
  final String thumbnail;
  final bool isAudio;
  final Widget placeholder;
  final VoidCallback onPlay;

  @override
  State<_GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<_GridCell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widget = this.widget;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onPlay,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovering
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovering
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: widget.thumbnail.isEmpty
                        ? widget.placeholder
                        : Image.file(
                            File(widget.thumbnail),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => widget.placeholder,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
