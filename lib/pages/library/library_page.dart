import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/bean/widget/state_presentation.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/models/playback_args.dart';
import 'package:emoplay/pages/library/favorites_sheet.dart';
import 'package:emoplay/pages/library/library_directory_sidebar.dart';
import 'package:emoplay/pages/library/library_folder_tree.dart';
import 'package:emoplay/pages/library/library_grid_groups.dart';
import 'package:emoplay/services/platform/mobile_media_scanner.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/format.dart';

/// 媒体库 Tab.
///
/// The media folders, their indexed files, search / filter / sort /
/// grid-list switching, scan progress and cancellation. Every piece of state
/// comes from [MediaStores] (LibraryStore + LibraryModel + ThumbnailService
/// + FavoritesStore) — the page itself keeps no media index. Interaction
/// ported from 1.x qml/LibraryPage.qml: the scan-state label, the directory
/// panel, the cancel/rescan toggle and the grid/list switch.
///
/// 3.0 additions (docs/EMOPLAY-3.0-ROADMAP.md M4-T2/T3/T5):
///  - the grid renders as a CustomScrollView of SliverMainAxisGroup(Sliver-
///    PinnedHeader, SliverGrid) per group — Kazumi popular_page's pinned
///    paradigm — grouped by directory or last-played year-month
///    (library_grid_groups.dart); search/typeFilter/sortMode keep their
///    model-side semantics and order the rows inside each group;
///  - a folder sidebar (breadcrumb + tree) scoped to the indexed
///    directories, derived from LibraryStore with no extra scan
///    (library_folder_tree.dart);
///  - favorites: a star badge on every card, an ordered collection
///    (favorites.json) and the ReorderableListView sorting sheet
///    (favorites_sheet.dart).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final MediaStores _stores;
  late final LibraryModel _model;
  bool _showDirectories = false;
  bool _showFolderTree = false;
  bool _gridView = true;

  /// What the grid groups by (M4-T2). Only the grid segment groups; the
  /// list view keeps the flat rows.
  LibraryGroupMode _groupMode = LibraryGroupMode.directory;

  /// Directory scope chosen in the folder sidebar (M4-T5); '' = no scope.
  String _scopeDirectory = '';

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
    setState(() {
      _showDirectories = true;
      _showFolderTree = true;
    });
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

  // ---- derived state (grouping / folder scope) ---------------------------

  /// The model's filtered+sorted visible list, narrowed to the sidebar's
  /// directory scope. The scope only ever REMOVES rows — search, typeFilter
  /// and sortMode keep their model semantics untouched.
  List<LibraryEntry> _scopedEntries() {
    final scope = _effectiveScope();
    if (scope.isEmpty) {
      return _model.visible;
    }
    return [
      for (final entry in _model.visible)
        if (entryMatchesDirectoryScope(entry, scope)) entry,
    ];
  }

  /// The scope as it will actually apply: a selection whose node the current
  /// tree no longer contains (its directory was removed or a rescan dropped
  /// every entry under it) falls back to the unscoped view.
  String _effectiveScope() {
    if (_scopeDirectory.isEmpty) {
      return '';
    }
    return libraryFolderTreeContains(_folderForest(), _scopeDirectory)
        ? _scopeDirectory
        : '';
  }

  /// The directory forest over the store's current state (roots =
  /// LibraryStore.directories, children derived from the indexed entries —
  /// no new scan).
  List<LibraryFolderNode> _folderForest() {
    final store = _stores.library;
    return buildLibraryFolderTree(
      directories: store.directories,
      entries: store.entryList,
      maxDepth: store.scanOptions.maxDepth,
      skipHidden: store.scanOptions.skipHidden,
    );
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
          if (_gridView)
            PopupMenuButton<LibraryGroupMode>(
              tooltip: '网格分组方式',
              icon: const Icon(Icons.workspaces_rounded),
              onSelected: (mode) => setState(() => _groupMode = mode),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: LibraryGroupMode.directory,
                  child: Text(_groupMode == LibraryGroupMode.directory
                      ? '✓ 按目录分组'
                      : '按目录分组'),
                ),
                PopupMenuItem(
                  value: LibraryGroupMode.yearMonth,
                  child: Text(_groupMode == LibraryGroupMode.yearMonth
                      ? '✓ 按年月分组'
                      : '按年月分组'),
                ),
              ],
            ),
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
        // The model drives the rows; the favorites store drives the badges
        // (and the sheet's count) — one rebuild serves both.
        animation: Listenable.merge([_model, _stores.favorites]),
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
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: _emptyState(context),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(
                            left: 16, top: 16, right: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_showFolderTree) ...[
                              SizedBox(
                                width: 240,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: LibraryDirectorySidebar(
                                    forest: _folderForest(),
                                    selected: _scopeDirectory,
                                    onSelect: (path) => setState(
                                        () => _scopeDirectory = path),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: _results(context),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_model.count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(
                      _resultCountLabel(),
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

  /// Footer count: scoped count when the sidebar narrows the view, the model
  /// total otherwise (the 1.x "N 项" line).
  String _resultCountLabel() {
    final scope = _effectiveScope();
    if (scope.isEmpty) {
      return '${_model.count} 项';
    }
    return '${_scopedEntries().length} / ${_model.count} 项 · ${_scopeLabel(scope)}';
  }

  String _scopeLabel(String directory) {
    final slash = directory.lastIndexOf('/');
    final name = slash < 0 ? directory : directory.substring(slash + 1);
    return name.isEmpty ? directory : name;
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
        // M4-T3: the ordered favorites collection (ReorderableListView sheet).
        OutlinedButton.icon(
          onPressed: () => FavoritesSheet.show(context, _stores),
          icon: const Icon(Icons.star_rounded, size: 18),
          label: Text('收藏 (${_stores.favorites.count})'),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _showFolderTree = !_showFolderTree),
          icon: const Icon(Icons.account_tree_rounded, size: 18),
          label: Text('目录树'),
        ),
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

  /// The scoped results: empty page state when the whole model is empty, a
  /// "nothing matches here" state when the scope/filter combination yields
  /// nothing, and the grid/list otherwise.
  Widget _results(BuildContext context) {
    if (_model.count == 0) {
      return _emptyState(context);
    }
    final entries = _scopedEntries();
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text('当前范围没有匹配的媒体', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _scopeDirectory = '';
                _model
                  ..filter = ''
                  ..typeFilter = 'all';
              }),
              child: const Text('显示全部'),
            ),
          ],
        ),
      );
    }
    return _gridView ? _groupedGrid(context, entries) : _list(context, entries);
  }

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
      // Kazumi 空态按钮 idiom（StateActionButton，48px 药丸）。
      actions: [
        if (noDirectories && MobileMediaScanner.isSupported)
          StateActionButton(
            onPressed: _mobileScanning ? null : () => _scanPhoneMedia(),
            icon: Icons.smartphone_rounded,
            text: '扫描手机媒体',
          ),
        StateActionButton(
          onPressed: noDirectories && !MobileMediaScanner.isSupported
              ? _addFolder
              : () => store.requestScan(),
          icon: noDirectories && !MobileMediaScanner.isSupported
              ? Icons.add_rounded
              : Icons.refresh_rounded,
          text: noDirectories && !MobileMediaScanner.isSupported
              ? '添加媒体文件夹'
              : '重新扫描',
        ),
        if (noDirectories && MobileMediaScanner.isSupported)
          StateActionButton.tonal(
            onPressed: _addFolder,
            icon: Icons.add_rounded,
            text: '添加媒体文件夹',
          ),
      ],
    );
  }

  /// The grouped grid (M4-T2, Kazumi popular_page 范式): one
  /// SliverMainAxisGroup per group — a pinned header (SliverPersistentHeader
  /// with pinned: true; this Flutter version has no SliverPinnedHeader
  /// shorthand) that pins while the group's SliverGrid scrolls beneath it,
  /// exactly the popular_page pinned behavior. Group order comes from the
  /// grouping module; rows inside a group keep the model's sort order.
  Widget _groupedGrid(BuildContext context, List<LibraryEntry> entries) {
    final theme = Theme.of(context);
    final groups = groupLibraryEntries(entries, mode: _groupMode);
    return CustomScrollView(
      slivers: [
        for (final group in groups)
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _GroupHeaderDelegate(
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.centerLeft,
                    color: theme.colorScheme.surface,
                    child: Row(
                      children: [
                        Icon(
                          _groupMode == LibraryGroupMode.directory
                              ? Icons.folder_rounded
                              : Icons.calendar_month_rounded,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            group.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${group.entries.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 198 / 174,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = group.entries[index];
                    return _GridCell(
                      title: entry.title,
                      thumbnail:
                          _stores.thumbnails.cachedThumbnailPath(entry.path),
                      isAudio: entry.type == 'audio',
                      isFavorite: _stores.favorites.contains(entry.path),
                      onToggleFavorite: () =>
                          _stores.favorites.toggle(entry.path),
                      onPlay: () => _play(entry),
                      placeholder: Icon(
                        entry.type == 'audio'
                            ? Icons.audiotrack_rounded
                            : Icons.movie_rounded,
                        size: 34,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                  childCount: group.entries.length,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _list(BuildContext context, List<LibraryEntry> entries) {
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: entries.length,
      itemExtent: 44,
      itemBuilder: (context, row) {
        final entry = entries[row];
        final lastPlayed = entry.lastPlayed;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            entry.type == 'audio'
                ? Icons.audiotrack_rounded
                : Icons.movie_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatBytes(entry.size),
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
          onTap: () => _play(entry),
        );
      },
    );
  }
}

/// The pinned group header delegate (M4-T2): a fixed 34px row the sliver
/// keeps pinned while its SliverMainAxisGroup scrolls. The child is rebuilt
/// by the page on every state change, so the delegate only needs identity
/// comparison for shouldRebuild.
class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  _GroupHeaderDelegate({required this.child});

  final Widget child;

  static const double _height = 34;

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_GroupHeaderDelegate oldDelegate) =>
      !identical(oldDelegate.child, child);

  @override
  String toString() => '_GroupHeaderDelegate';
}

/// One grid cell (1.x grid delegate): thumbnail, title and the M4-T3
/// favorite badge (corner star; filled when favorited, tap toggles — the
/// badge's own gesture wins over the cell's play tap).
class _GridCell extends StatefulWidget {
  const _GridCell({
    required this.title,
    required this.thumbnail,
    required this.isAudio,
    required this.isFavorite,
    required this.placeholder,
    required this.onPlay,
    required this.onToggleFavorite,
  });

  final String title;
  final String thumbnail;
  final bool isAudio;
  final bool isFavorite;
  final Widget placeholder;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavorite;

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
      child: Stack(
        children: [
          InkWell(
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
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: widget.isFavorite ? '取消收藏' : '收藏',
              visualDensity: VisualDensity.compact,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: const EdgeInsets.all(4),
              icon: Icon(
                widget.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 19,
                color: widget.isFavorite
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: widget.onToggleFavorite,
            ),
          ),
        ],
      ),
    );
  }
}
