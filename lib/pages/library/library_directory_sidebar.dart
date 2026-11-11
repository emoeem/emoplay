import 'package:flutter/material.dart';

import 'package:emoplay/pages/library/library_folder_tree.dart';

// The library page's directory sidebar (EmoPlay 3.0 roadmap M4-T5:
// "目录侧栏（面包屑+树）"). Purely presentational — the tree comes in
// prebuilt (library_folder_tree.dart, derived from the library store, no
// scanning) and every interaction is emitted upwards:
//
//  - the breadcrumb on top is the chain 全部 → root → … → selection; each
//    crumb (and 全部) is tappable and selects that scope;
//  - the tree lists the roots and their derived subdirectories with an
//    indent per depth; tapping a row selects it (tapping the selected row
//    again clears the scope — the toggle the breadcrumb's 全部 also offers).
//
// Expansion state is local to the sidebar (which branches are unfolded),
// keyed by directory path; roots start expanded.
class LibraryDirectorySidebar extends StatefulWidget {
  const LibraryDirectorySidebar({
    super.key,
    required this.forest,
    required this.selected,
    required this.onSelect,
  });

  final List<LibraryFolderNode> forest;

  // Currently selected directory path; '' = no scope (全部).
  final String selected;

  final ValueChanged<String> onSelect;

  @override
  State<LibraryDirectorySidebar> createState() =>
      _LibraryDirectorySidebarState();
}

class _LibraryDirectorySidebarState extends State<LibraryDirectorySidebar> {
  // Unfolded directory paths (children visible). Roots default open; the
  // set starts empty and the row builder treats "not in the set" as open
  // for depth-0 nodes so the initial paint shows the user's directories.
  final Set<String> _collapsed = <String>{};

  bool _isOpen(LibraryFolderNode node) =>
      node.depth == 0 || !_collapsed.contains(node.path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chain = libraryFolderChain(widget.forest, widget.selected);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('目录树', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _breadcrumb(context, chain),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.forest.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '还没有媒体目录。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final root in widget.forest)
                        _treeRow(context, root),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // 全部 / Movies / Season 1 / … — tappable scopes along the selected chain.
  Widget _breadcrumb(BuildContext context, List<LibraryFolderNode> chain) {
    final theme = Theme.of(context);
    Widget crumb(String label, String path, {required bool isLast}) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isLast ? null : () => widget.onSelect(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (isLast
                    ? theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      )
                    : theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ))
                ?.apply(fontSizeFactor: 1),
          ),
        ),
      );
    }

    final crumbs = <Widget>[
      // Keys give the tests a deterministic handle on each scope target.
      KeyedSubtree(
        key: const ValueKey<String>('folder-crumb-'),
        child: crumb('全部', '', isLast: chain.isEmpty),
      ),
    ];
    for (var i = 0; i < chain.length; i++) {
      crumbs
        ..add(const Text('/', style: TextStyle(fontSize: 11)))
        ..add(KeyedSubtree(
          key: ValueKey<String>('folder-crumb-${chain[i].path}'),
          child: crumb(chain[i].name, chain[i].path,
              isLast: i == chain.length - 1),
        ));
    }
    return Tooltip(
      message: '目录范围：从面包屑切换上层目录',
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox(
        height: 28,
        child: ListView(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: crumbs),
          ],
        ),
      ),
    );
  }

  Widget _treeRow(BuildContext context, LibraryFolderNode node) {
    final theme = Theme.of(context);
    final selected = node.path == widget.selected;
    final open = _isOpen(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey<String>('folder-tree-node-${node.path}'),
          onTap: () => widget.onSelect(selected ? '' : node.path),
          child: Padding(
            padding: EdgeInsets.only(left: 8.0 + node.depth * 16.0),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  // Expand/collapse chevron over the children (a leaf keeps
                  // the indent so labels stay aligned).
                  SizedBox(
                    width: 22,
                    child: node.hasChildren
                        ? InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => setState(() {
                              open
                                  ? _collapsed.add(node.path)
                                  : _collapsed.remove(node.path);
                            }),
                            child: Icon(
                              open
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_right_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                  ),
                  Icon(
                    node.isLibraryRoot
                        ? Icons.folder_special_rounded
                        : Icons.folder_rounded,
                    size: 16,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : null,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open && node.hasChildren)
          for (final child in node.children) _treeRow(context, child),
      ],
    );
  }
}
