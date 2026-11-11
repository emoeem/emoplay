import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/media/library_store.dart';

// Directory tree for the library page's folder sidebar (EmoPlay 3.0 roadmap
// M4-T5: "目录侧栏（面包屑+树），数据源 LibraryStore.directories 派生，
// 不加新扫描").
//
// Pure logic, no widgets, NO filesystem IO: the top-level nodes are the
// store's media directories (LibraryStore.directories, the user's explicit
// folder list) and every child is derived from the indexed entry paths the
// scan already produced — a re-derivation of in-memory state, not a new
// walk. A directory the scanner never indexed (empty, hidden, beyond the
// scan depth, or a directory symlink — the walk never descends into one, so
// no entry path can pass through it) therefore never appears, which is
// exactly the "与扫描器语义一致" contract:
//
//  - depth pruning: scanDirectories indexes files only at walk level
//    ≤ maxDepth (lib/media/library_store.dart, `level > options.maxDepth`),
//    so child directories are derived only down to that level; with
//    maxDepth ≤ 0 (unlimited) nothing is pruned by depth;
//  - hidden pruning: the walk skips dot entries and does not descend into
//    them, so a hidden segment prunes the whole chain (guarded even for
//    hand-built inputs the scanner would never have produced);
//  - symlinked directories: never indexed ⇒ never derivable ⇒ never shown.

// One node of the directory forest.
@immutable
class LibraryFolderNode {
  const LibraryFolderNode({
    required this.path,
    required this.name,
    required this.children,
    this.depth = 0,
    this.isLibraryRoot = false,
  });

  // Absolute directory path (unique key; '' only for the virtual "all" crumb
  // the sidebar renders itself).
  final String path;

  // Display label: the folder's own name.
  final String name;

  // Levels below the top-level root this node hangs from (the root itself
  // is 0). Display/indentation only — pruning already happened at build.
  final int depth;

  // True when this path is itself one of LibraryStore.directories (the user
  // explicitly added it — the sidebar marks it like the directories card).
  final bool isLibraryRoot;

  // Children ordered case-insensitively by name (the store's title-sort
  // convention).
  final List<LibraryFolderNode> children;

  bool get hasChildren => children.isNotEmpty;
}

// Builds the directory forest.
//
// |directories| = LibraryStore.directories (top-level candidates, store
// order preserved). |entries| = LibraryStore.entryList (or the model's
// visible list) — the only source for children. |maxDepth| / |skipHidden|
// are the LibraryStore ScanOptions the last scan ran with, so the tree can
// prune exactly where the scanner stopped.
List<LibraryFolderNode> buildLibraryFolderTree({
  required List<String> directories,
  required List<LibraryEntry> entries,
  required int maxDepth,
  required bool skipHidden,
}) {
  // Direct child directories per parent path. Seeded from the entry paths,
  // then the nested store directories are merged in (a user-added subfolder
  // shows even when the scan found nothing under it).
  final childrenOf = <String, Set<String>>{};

  void register(String parent, String child) =>
      (childrenOf[parent] ??= <String>{}).add(child);

  // 1. Derive from entries: for an entry at |root|/d1/…/dn/file, the
  // directories d1…dmin(n, maxDepth) join the tree (depth pruning mirrors
  // the scanner's `level > maxDepth` file check; a directory at level i can
  // only hold indexed files when i ≤ maxDepth).
  for (final entry in entries) {
    final parent = p.dirname(entry.path);
    if (parent == entry.path) {
      continue; // degenerate (no directory component); never from a scan
    }
    final owner = _longestContainingRoot(directories, entry.path);
    if (owner == null) {
      continue; // not under any media directory
    }
    if (parent == owner) {
      continue; // directly in the root: contributes no child directory
    }
    final relative = p.relative(parent, from: owner);
    final segments = p.split(relative);
    var hidden = false;
    for (final segment in segments) {
      if (skipHidden && segment.startsWith('.')) {
        hidden = true; // the walk never descends into dot directories
        break;
      }
    }
    if (hidden) {
      continue;
    }
    var current = owner;
    final levels =
        maxDepth > 0 && segments.length > maxDepth ? maxDepth : segments.length;
    for (var i = 0; i < levels; i++) {
      final next = '${current == '/' ? '' : current}/${segments[i]}';
      register(current, next);
      current = next;
    }
  }

  // 2. Merge the user's own directories in: a store directory nested under
  // another store directory appears inside that subtree (marked
  // isLibraryRoot), even with no indexed entries. Chain registration runs
  // in path order so the intermediate levels exist.
  final rootSet = <String>{...directories};
  final nested = directories
      .where((directory) =>
          _longestContainingRoot(directories, directory) != null)
      .toList();
  for (final directory in nested) {
    final ancestor = _longestContainingRoot(directories, directory);
    var current = ancestor!;
    for (final segment in p.split(p.relative(directory, from: ancestor))) {
      final next = '${current == '/' ? '' : current}/$segment';
      register(current, next);
      current = next;
    }
  }

  // 3. Build nodes: top-level = store directories that no other store
  // directory contains (nested ones were merged above), store order kept.
  final topLevel = directories
      .where((directory) =>
          _longestContainingRoot(directories, directory) == null)
      .toList();
  return [
    for (final directory in topLevel)
      _buildNode(
        path: directory,
        depth: 0,
        isRoot: true,
        childrenOf: childrenOf,
        rootSet: rootSet,
      ),
  ];
}

// Chain of nodes from a top-level root down to |path| (breadcrumb trail, in
// walk order). Empty when the forest does not contain |path| — the page
// treats that as "selection gone" (a rescan or directory removal dropped
// it) and falls back to the unscoped view.
List<LibraryFolderNode> libraryFolderChain(
  List<LibraryFolderNode> forest,
  String path,
) {
  for (final node in forest) {
    if (node.path == path) {
      return [node];
    }
    final below = libraryFolderChain(node.children, path);
    if (below.isNotEmpty) {
      return [node, ...below];
    }
  }
  return const <LibraryFolderNode>[];
}

bool libraryFolderTreeContains(List<LibraryFolderNode> forest, String path) =>
    libraryFolderChain(forest, path).isNotEmpty;

// The directory-scope predicate (选中联动): with a sidebar selection of
// |selected|, an entry matches when it lives in that directory itself or in
// any directory below it. |selected| == '' (or a path the tree dropped)
// matches everything — the unscoped view.
bool entryMatchesDirectoryScope(LibraryEntry entry, String selected) {
  if (selected.isEmpty) {
    return true;
  }
  final parent = p.dirname(entry.path);
  return parent == selected || parent.startsWith('$selected/');
}

// The nearest store directory that strictly contains |path| — a directory
// other than |path| itself that |path| extends with '/' — or null. Longest
// match wins, so with roots /a and /a/b a path under /a/b belongs to /a/b.
// (The trailing-'/' in the startsWith keeps '/a/bc' from matching '/a/b',
// the same trick LibraryStore.removeDirectory uses for its prefix drop.)
String? _longestContainingRoot(List<String> directories, String path) {
  String? best;
  for (final directory in directories) {
    if (directory == path) {
      continue; // a directory does not contain itself
    }
    if (path.startsWith('$directory/')) {
      if (best == null || directory.length > best.length) {
        best = directory;
      }
    }
  }
  return best;
}

LibraryFolderNode _buildNode({
  required String path,
  required int depth,
  required bool isRoot,
  required Map<String, Set<String>> childrenOf,
  required Set<String> rootSet,
}) {
  final name = p.basename(path);
  final childPaths = childrenOf[path] ?? const <String>{};
  final children = [
    for (final child in childPaths)
      _buildNode(
        path: child,
        depth: depth + 1,
        isRoot: rootSet.contains(child),
        childrenOf: childrenOf,
        rootSet: rootSet,
      ),
  ]..sort((a, b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return LibraryFolderNode(
    path: path,
    name: name.isEmpty ? path : name,
    depth: depth,
    isLibraryRoot: isRoot,
    children: List.unmodifiable(children),
  );
}
