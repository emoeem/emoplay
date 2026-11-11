import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/library/library_directory_sidebar.dart';
import 'package:emoplay/pages/library/library_folder_tree.dart';
import 'package:emoplay/pages/library/library_page.dart';

/// M4-T5 guard tests (EmoPlay 3.0 roadmap): the library page's folder
/// sidebar builds its tree purely from LibraryStore state — the user's
/// directories as roots, children derived from the already-indexed entry
/// paths, with NO new scan — and the pruning mirrors the scanner exactly.
///
///  * 树构造: roots, derived children, nested store roots merged;
///  * 深度剪枝与扫描器语义一致: a REAL LibraryStore.scanDirectories run
///    over a fixture tree feeds the builder — the tree ends exactly where
///    the scanner's maxDepth stops (and hidden directories never appear);
///  * 选中联动: the scope predicate keeps a selected directory's own files
///    and everything below it, and the page-level test drives the real
///    sidebar (open it, tap a node, watch the results narrow).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-tree-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Fixture tree on disk (files carry their extension only; sizes do not
  /// matter here):
  ///   root/Movies/movie.mkv                  (level 0 file)
  ///   root/Movies/Season 1/ep1.mkv           (level 1)
  ///   root/Movies/Season 1/Deep/nested.mp4   (level 2)
  ///   root/Movies/Season 1/Deep/Deepest/too-deep.mp4 (level 3)
  ///   root/Movies/.hidden/secret.mkv         (hidden directory)
  ///   root/Music/track.flac                  (level 0)
  ///   root/Music/album/song.mp3              (level 1)
  Future<List<LibraryEntry>> writeFixture() async {
    final files = <String>[
      'Movies/movie.mkv',
      'Movies/Season 1/ep1.mkv',
      'Movies/Season 1/Deep/nested.mp4',
      'Movies/Season 1/Deep/Deepest/too-deep.mp4',
      'Movies/.hidden/secret.mkv',
      'Music/track.flac',
      'Music/album/song.mp3',
    ];
    for (final relative in files) {
      final file = File('${tempDir.path}/root/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString('x');
    }
    final root = '${tempDir.path}/root';
    return LibraryStore.scanDirectories(
      ['$root/Movies', '$root/Music'],
      const ScanOptions(maxDepth: 2, skipHidden: true),
    );
  }

  test('buildsForestFromRootsAndDerivedChildren', () async {
    final root = '${tempDir.path}/root';
    final entries = [
      _entry('$root/Movies/movie.mkv'),
      _entry('$root/Movies/Season 1/ep1.mkv'),
      _entry('$root/Music/track.flac'),
    ];

    final forest = buildLibraryFolderTree(
      directories: ['$root/Movies', '$root/Music'],
      entries: entries,
      maxDepth: 2,
      skipHidden: true,
    );

    // Top-level = the store directories, store order kept.
    expect(forest.map((node) => node.path).toList(),
        ['$root/Movies', '$root/Music']);
    expect(forest.map((node) => node.name).toList(), ['Movies', 'Music']);
    expect(forest.map((node) => node.isLibraryRoot).toList(), [true, true]);
    // Children derived from the entry paths, case-insensitive by name.
    expect(forest[0].children.map((node) => node.path).toList(),
        ['$root/Movies/Season 1']);
    expect(forest[0].children.single.depth, 1);
    expect(forest[1].children, isEmpty,
        reason: 'Music has its file directly in the root — no child dirs');
  });

  test('depthPruningMatchesScannerSemantics', () async {
    final root = '${tempDir.path}/root';
    final scanned = await writeFixture();
    // The scanner itself (maxDepth 2, skipHidden): Season 1/Deep files are
    // in, Deepest and .hidden are out.
    final scannedPaths = scanned.map((entry) => entry.path).toList();
    expect(scannedPaths, contains('$root/Movies/Season 1/Deep/nested.mp4'));
    expect(scannedPaths,
        isNot(contains('$root/Movies/Season 1/Deep/Deepest/too-deep.mp4')));
    expect(scannedPaths, isNot(contains('$root/Movies/.hidden/secret.mkv')));

    // The tree over the scanner's own output ends exactly where the scan
    // stopped: Deep (level 2) exists, Deepest and .hidden cannot.
    final forest = buildLibraryFolderTree(
      directories: ['$root/Movies', '$root/Music'],
      entries: scanned,
      maxDepth: 2,
      skipHidden: true,
    );
    final movies = forest.first;
    final season = movies.children.single;
    expect(season.path, '$root/Movies/Season 1');
    expect(season.children.map((node) => node.name).toList(), ['Deep']);
    expect(season.children.single.children, isEmpty,
        reason: 'level 3 is beyond maxDepth 2 — the scanner never indexed '
            'anything there, so the tree stops at Deep');

    // And with the unlimited depth the scan would have produced (maxDepth
    // <= 0), the same builder reaches level 3 — pruning follows the scan
    // options, not a hardcoded constant.
    final unlimitedScan = await LibraryStore.scanDirectories(
      ['$root/Movies'],
      const ScanOptions(maxDepth: 0, skipHidden: true),
    );
    final unlimitedForest = buildLibraryFolderTree(
      directories: ['$root/Movies'],
      entries: unlimitedScan,
      maxDepth: 0,
      skipHidden: true,
    );
    // Movies → Season 1 → Deep → Deepest (the scan found too-deep.mp4 at
    // level 3, so all three directory levels derive).
    final deepest = unlimitedForest.first.children.single.children.single.children.single;
    expect(deepest.path, '$root/Movies/Season 1/Deep/Deepest');
    expect(deepest.depth, 3);

    // Hand-injected entries the scanner would never produce are pruned the
    // same way (hidden chains and beyond-depth chains).
    final injected = buildLibraryFolderTree(
      directories: ['$root/Movies'],
      entries: [
        _entry('$root/Movies/.hidden/secret.mkv'),
        _entry('$root/Movies/Season 1/Deep/Deepest/too-deep.mp4'),
      ],
      maxDepth: 2,
      skipHidden: true,
    );
    expect(
        injected.first.children.single.children.single.children, isEmpty);
  });

  test('nestedStoreRootsMergeAndBreadcrumbChainWalksDown', () {
    final entries = [
      _entry('/media/Movies/Season 1/ep1.mkv'),
      _entry('/media/Music/x.flac'),
    ];
    final forest = buildLibraryFolderTree(
      directories: ['/media/Movies', '/media/Movies/Season 1', '/media/Music'],
      entries: entries,
      maxDepth: 2,
      skipHidden: true,
    );

    // '/media/Movies/Season 1' is itself a store directory but lives under
    // '/media/Movies' in the tree (one top-level per contained root chain).
    expect(forest.map((node) => node.path).toList(),
        ['/media/Movies', '/media/Music']);
    final season = forest.first.children.single;
    expect(season.path, '/media/Movies/Season 1');
    expect(season.isLibraryRoot, isTrue,
        reason: 'the user added it as its own media directory');
    expect(season.children, isEmpty);

    // The breadcrumb chain walks root → … → selection; an unknown path
    // (removed directory, rescan drop) yields an empty chain.
    final chain = libraryFolderChain(forest, '/media/Movies/Season 1');
    expect(chain.map((node) => node.path).toList(),
        ['/media/Movies', '/media/Movies/Season 1']);
    expect(libraryFolderChain(forest, '/media/nowhere'), isEmpty);
    expect(libraryFolderTreeContains(forest, '/media/Movies/Season 1'), isTrue);
    expect(libraryFolderTreeContains(forest, '/media/nowhere'), isFalse);
  });

  test('selectionScopePredicateKeepsSubtreeAndDropsSiblings', () {
    final inScopeOwn = _entry('/media/Movies/movie.mkv');
    final inScopeDeep = _entry('/media/Movies/Season 1/Deep/nested.mp4');
    final outOfScope = _entry('/media/Music/track.flac');
    final prefixTrap = _entry('/media/Movies Deluxe/x.mkv');

    // Selecting /media/Movies keeps its own files and everything below,
    // drops the sibling root and the "/media/Movies Deluxe" prefix trap
    // (the same '$path/' discipline LibraryStore.removeDirectory uses).
    for (final entry in [inScopeOwn, inScopeDeep]) {
      expect(entryMatchesDirectoryScope(entry, '/media/Movies'), isTrue);
    }
    for (final entry in [outOfScope, prefixTrap]) {
      expect(entryMatchesDirectoryScope(entry, '/media/Movies'), isFalse);
    }

    // A deeper selection narrows further; '' is the unscoped view.
    expect(entryMatchesDirectoryScope(inScopeDeep, '/media/Movies/Season 1'),
        isTrue);
    expect(entryMatchesDirectoryScope(inScopeOwn, '/media/Movies/Season 1'),
        isFalse);
    expect(entryMatchesDirectoryScope(outOfScope, ''), isTrue);
  });

  testWidgets('sidebarSelectionNarrowsTheResults', (tester) async {
    final root = tempDir.path;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    File('$root/library.json').writeAsStringSync(jsonEncode(<String, Object?>{
      'version': 1,
      'directories': ['$root/Movies', '$root/Music'],
      'entries': [
        <String, Object?>{
          'path': '$root/Movies/movie.mkv',
          'title': 'movie',
          'type': 'video',
          'size': 10,
          'lastPlayed': ''
        },
        <String, Object?>{
          'path': '$root/Movies/Season 1/ep1.mkv',
          'title': 'ep1',
          'type': 'video',
          'size': 11,
          'lastPlayed': ''
        },
        <String, Object?>{
          'path': '$root/Music/song.flac',
          'title': 'song',
          'type': 'audio',
          'size': 12,
          'lastPlayed': ''
        },
      ],
    }));

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });

    // Tall surface: with the default 800×600 test viewport the third
    // group's grid cell sits below the fold and its text is never built.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // All three titles are visible before any scope.
    expect(find.text('movie'), findsOneWidget);
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('song'), findsOneWidget);

    // Open the sidebar, then select the Movies scope (deterministic key on
    // the tree row — the same label also renders as the grid's group header).
    await tester.tap(find.text('目录树'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryDirectorySidebar), findsOneWidget);

    await tester
        .tap(find.byKey(ValueKey<String>('folder-tree-node-$root/Movies')));
    await tester.pumpAndSettle();

    // 选中联动: the Movies subtree stays (movie + its Season 1 child file),
    // the Music file leaves, and the footer reports the scoped count.
    expect(find.text('movie'), findsOneWidget);
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('song'), findsNothing);
    expect(find.textContaining('2 / 3 项'), findsOneWidget);

    // 全部 clears the scope from the breadcrumb.
    await tester.tap(find.byKey(const ValueKey<String>('folder-crumb-')));
    await tester.pumpAndSettle();
    expect(find.text('song'), findsOneWidget);
  });
}

LibraryEntry _entry(String path) => LibraryEntry(
      path: path,
      title: path.split('/').last,
      type: path.endsWith('.flac') || path.endsWith('.wav') ? 'audio' : 'video',
      size: 10,
    );

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
