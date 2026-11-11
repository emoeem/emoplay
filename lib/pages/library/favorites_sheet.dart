import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/media/favorites_store.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';

// The favorites sheet (EmoPlay 3.0 roadmap M4-T3: "排序复用
// ReorderableListView 范式" — PiliPlus lib/pages/fav_folder_sort/view.dart:71
// as the reference interaction). Lists the favorites in the user's order,
// drag to reorder (an explicit drag handle — the desktop-friendly shape of
// the paradigm; the store persists each applied move), remove per row.
//
// Rows are joined against the library index at open time: a favorite whose
// path is still indexed shows the entry's title, a stale one (file or
// directory removed from the library) degrades to its file name — the
// favorite itself stays until the user removes it.
class FavoritesSheet extends StatefulWidget {
  const FavoritesSheet({super.key, required this.favorites, required this.library});

  final FavoritesStore favorites;
  final LibraryStore library;

  /// Opens the sheet above |context|.
  static Future<void> show(BuildContext context, MediaStores stores) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => FavoritesSheet(
        favorites: stores.favorites,
        library: stores.library,
      ),
    );
  }

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  // The user's order this sheet session edits (kept in sync with the store
  // on every mutation — the store is the authority, the copy only avoids
  // re-deriving the join per drag frame).
  late final List<FavoriteEntry> _entries =
      List<FavoriteEntry>.of(widget.favorites.entries);
  late final Map<String, LibraryEntry> _libraryByPath = <String, LibraryEntry>{
    for (final entry in widget.library.entryList) entry.path: entry,
  };

  // onReorderItem delivers already-adjusted indexes (post-removal
  // coordinates) — the same pair the store's reorder() takes.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _entries.insert(newIndex, _entries.removeAt(oldIndex));
    });
    widget.favorites.reorder(oldIndex, newIndex);
  }

  void _remove(FavoriteEntry entry) {
    setState(() => _entries.remove(entry));
    widget.favorites.remove(entry.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('收藏（拖动排序）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '收藏保存在 favorites.json，与媒体索引互不影响。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '还没有收藏。点击媒体卡片右上角的星标即可收藏。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  itemCount: _entries.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final favorite = _entries[index];
                    final libraryEntry = _libraryByPath[favorite.path];
                    final title = libraryEntry?.title.isNotEmpty == true
                        ? libraryEntry!.title
                        : p.basename(favorite.path);
                    final isStale = libraryEntry == null;
                    return ListTile(
                      key: ValueKey<String>(favorite.path),
                      dense: true,
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        isStale
                            ? '${favorite.path} · 已不在媒体索引中'
                            : favorite.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isStale
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '取消收藏',
                        icon: const Icon(Icons.star_rounded, size: 20),
                        color: theme.colorScheme.primary,
                        onPressed: () => _remove(favorite),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
