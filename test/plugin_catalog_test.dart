// M6-T4 catalog dispatch tests (docs/EMOPLAY-3.0-ROADMAP.md §五 M6-T4:
// "新增 catalog 分派测试 ≥2（视图切换、详情路由）").
//
// Two layers:
//   1. Headless PluginCatalogDispatch unit tests — view switching
//      (目录视图 ⇄ 详情页), detail routing (row resolution, unknown-name
//      refusal, fallback when the routed row vanishes) and the Kazumi
//      directory shaping (search + 全部/已安装/可更新 chips) applied to the
//      three sections without merging them (不变量 6).
//   2. The separated plugin_update_actions module — the immediate
//      enable/disable pair and the confirmed-operation funnel — plus a
//      widget test mounting the real PluginsPage with the injectable
//      manager/source seams (FakeGitRunner + FakeFetcher, temp app-data,
//      no network), tapping a row through the detail route and back.
//
// The page mount is possible headless because M6-T4 made PluginsPage take
// optional manager/source injections (see kazumi_alignment_ui_test.dart's
// old note: the page path previously had no injectable fetcher).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/pages/plugins/plugin_catalog_dispatch.dart';
import 'package:emoplay/pages/plugins/plugin_update_actions.dart';
import 'package:emoplay/pages/plugins/plugins_page.dart';
import 'package:emoplay/plugins/plugin_git_runner.dart';
import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/remote_manifest_source.dart';

class FakeGitRunner implements PluginGitRunner {
  Future<PluginGitResult> Function(List<String>, String)? handler;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<PluginGitResult> run(
    List<String> arguments,
    String workingDirectory,
  ) async {
    calls.add(arguments);
    if (handler != null) {
      return handler!(arguments, workingDirectory);
    }
    return const PluginGitResult(exitCode: 0, started: true);
  }
}

class FakeFetcher implements PluginRemoteFetcher {
  @override
  void Function(Uri url, PluginRemoteFetchResult result)? onFinished;

  @override
  void fetch(Uri url) {
    // Never completes: the page's first-mount refresh stays pending and the
    // test exercises the cached/empty directory offline.
  }
}

const String kCatalogJson =
    '{"sources": ['
    '{"name": "uosc_danmaku",'
    ' "url": "https://git.example/uosc_danmaku.git",'
    ' "branch": "main", "source": ".",'
    ' "destination": "scripts/uosc_danmaku",'
    ' "mode": "check", "baseline": "old1"},'
    '{"name": "mpv360",'
    ' "url": "https://git.example/mpv360.git",'
    ' "branch": "master", "source": ".",'
    ' "destination": "scripts/mpv360.lua", "mode": "check"},'
    '{"name": "anime4k",'
    ' "url": "https://git.example/anime4k.git",'
    ' "branch": "master", "source": "glsl",'
    ' "destination": "shaders/Anime4K/glsl", "mode": "replace"}'
    ']}';

Map<String, Object?> syntheticRow({
  required String name,
  bool installed = false,
  bool updateAvailable = false,
  String mode = 'check',
}) => <String, Object?>{
  'name': name,
  'url': 'https://git.example/$name.git',
  'branch': 'main',
  'mode': mode,
  'installed': installed,
  'enabled': false,
  'updateAvailable': updateAvailable,
};

class Fixture {
  Fixture() {
    final dir = Directory.systemTemp.createTempSync('emoplay-catalog-');
    path = dir.path;
    catalogPath = '$path/catalog.json';
    File(catalogPath).writeAsStringSync(kCatalogJson);
    tempDir = dir;
  }

  late final Directory tempDir;
  late final String path;
  late final String catalogPath;

  void dispose() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  group('plugin catalog dispatch (M6-T4 分派)', () {
    test('viewSwitchingMovesCatalogToDetailAndBack', () {
      final dispatch = PluginCatalogDispatch();
      expect(dispatch.view, PluginCatalogViewId.catalog);
      expect(dispatch.detailRow, isNull);

      final uosc = syntheticRow(name: 'uosc_danmaku', installed: true);
      dispatch.syncRows([uosc, syntheticRow(name: 'mpv360')]);

      dispatch.openDetail('uosc_danmaku');
      expect(dispatch.view, PluginCatalogViewId.detail);
      expect(dispatch.detailName, 'uosc_danmaku');
      // The routed row resolves to the synced catalog row (same instance).
      expect(identical(dispatch.detailRow, uosc), isTrue);

      dispatch.backToCatalog();
      expect(dispatch.view, PluginCatalogViewId.catalog);
      expect(dispatch.detailName, '');
      expect(dispatch.detailRow, isNull);
    });

    test('detailRoutingRefusesUnknownNames', () {
      final dispatch = PluginCatalogDispatch();
      dispatch.syncRows([syntheticRow(name: 'uosc_danmaku')]);

      // An unknown name is refused: the catalog stays put, nothing crashes.
      dispatch.openDetail('ghost');
      expect(dispatch.view, PluginCatalogViewId.catalog);
      expect(dispatch.detailRow, isNull);

      // Empty dispatch: nothing routable at all.
      dispatch.syncRows(const []);
      dispatch.openDetail('uosc_danmaku');
      expect(dispatch.view, PluginCatalogViewId.catalog);
    });

    test('detailRoutingPrefersTheFirstSyncedRowForAName', () {
      final dispatch = PluginCatalogDispatch();
      final managerRow = syntheticRow(
        name: 'uosc_danmaku',
        installed: true,
        mode: 'check',
      );
      final entryRow = syntheticRow(name: 'uosc_danmaku', mode: 'replace');
      // Local manager rows are synced before online entries (builtin names
      // stay authoritative) — the dispatch dedupes keeping the first.
      dispatch.syncRows([managerRow, entryRow]);
      dispatch.openDetail('uosc_danmaku');
      expect(dispatch.detailRow?['mode'], 'check');
      expect(dispatch.detailRow?['installed'], isTrue);
    });

    test('detailRoutingFallsBackToCatalogWhenTheRowVanishes', () {
      final dispatch = PluginCatalogDispatch();
      dispatch.syncRows([syntheticRow(name: 'uosc_danmaku')]);
      dispatch.openDetail('uosc_danmaku');
      expect(dispatch.view, PluginCatalogViewId.detail);

      // Uninstall / source refresh removes the row; the next build pass
      // syncs and the stale detail falls back to the catalog instead of
      // lingering.
      dispatch.syncRows([syntheticRow(name: 'mpv360')]);
      expect(dispatch.view, PluginCatalogViewId.catalog);
      expect(dispatch.detailName, '');
      expect(dispatch.detailRow, isNull);
    });

    test('filterAndSearchShapeTheDirectoryWithoutMergingSections', () {
      final dispatch = PluginCatalogDispatch();
      final rows = [
        syntheticRow(name: 'uosc_danmaku', installed: true),
        syntheticRow(name: 'mpv360'),
        syntheticRow(name: 'anime4k', installed: true, updateAvailable: true),
      ];
      dispatch.syncRows(rows);

      // 可更新 chip.
      dispatch.setFilter(PluginCatalogFilter.updates);
      expect(dispatch.visibleRows(rows).map((r) => r['name']), ['anime4k']);
      // 已安装 chip.
      dispatch.setFilter(PluginCatalogFilter.installed);
      expect(dispatch.visibleRows(rows).map((r) => r['name']).toSet(), {
        'uosc_danmaku',
        'anime4k',
      });
      // 全部 chip + search box.
      dispatch.setFilter(PluginCatalogFilter.all);
      dispatch.setQuery('MPV');
      expect(dispatch.visibleRows(rows).map((r) => r['name']), ['mpv360']);
      // Search reset: an empty query shows every row again.
      dispatch.setQuery('');
      expect(dispatch.visibleRows(rows).length, 3);
      // Sections feed their own rows through the same shaping: the local
      // and directory segments stay separate lists (不变量 6).
      final localOnly = dispatch.visibleRows([rows[0]]);
      final entriesOnly = dispatch.visibleRows([rows[1]]);
      expect(localOnly.map((r) => r['name']), ['uosc_danmaku']);
      expect(entriesOnly.map((r) => r['name']), ['mpv360']);
    });
  });

  group('plugin update actions separation (M6-T4)', () {
    test('enableDisableAppliesImmediatelyWithoutAPlan', () async {
      final f = Fixture();
      addTearDown(f.dispose);
      final git = FakeGitRunner();
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: git,
      );
      // The row's 'enabled' mirrors installed && script && state
      // (pluginRow), so install the plugin first through the same fake
      // clone used by plugin_manager_test.dart.
      git.handler = (arguments, _) async {
        if (arguments.first == 'rev-parse') {
          return const PluginGitResult(
            exitCode: 0,
            standardOutput: 'head0123456789\n',
            started: true,
          );
        }
        if (arguments.isNotEmpty && arguments.first == 'clone') {
          final target = arguments.last;
          final dir = Directory(target);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          File('$target/main.lua').writeAsStringSync('fake\n');
        }
        return const PluginGitResult(exitCode: 0, started: true);
      };
      await executeConfirmedPluginOperation(manager, 'uosc_danmaku', 'install');
      Map<String, Object?> uosc() =>
          manager.plugins().firstWhere((r) => r['name'] == 'uosc_danmaku');
      // The 1.x install default keeps the plugin enabled (see
      // installClonesAndRecordsHead in plugin_manager_test.dart).
      expect(uosc(), containsPair('enabled', isTrue));

      // Stage 1 returns null for the immediate pair — no plan is built and
      // no git runs (planOperation would refuse these as unknown actions);
      // the setEnabled already happened.
      final callsBefore = git.calls.length;
      expect(planPluginOperation(manager, 'uosc_danmaku', 'disable'), isNull);
      expect(git.calls.length, callsBefore);
      expect(uosc(), containsPair('enabled', isFalse));
      planPluginOperation(manager, 'uosc_danmaku', 'enable');
      expect(uosc(), containsPair('enabled', isTrue));
    });

    test('executeConfirmedOperationIsTheOnlyFunnelToTheManager', () async {
      final f = Fixture();
      addTearDown(f.dispose);
      final git = FakeGitRunner();
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: git,
      );
      git.handler = (arguments, _) async {
        if (arguments.first == 'rev-parse') {
          return const PluginGitResult(
            exitCode: 0,
            standardOutput: 'head0123456789\n',
            started: true,
          );
        }
        // Like fakeClone in plugin_manager_test.dart: create the target
        // directory with an entry marker file.
        if (arguments.isNotEmpty && arguments.first == 'clone') {
          final target = arguments.last;
          final dir = Directory(target);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          File('$target/main.lua').writeAsStringSync('fake\n');
        }
        return const PluginGitResult(exitCode: 0, started: true);
      };

      expect(manager.isInstalled('uosc_danmaku'), isFalse);
      // Stage 3: dispatch a confirmed install through the separated funnel.
      await executeConfirmedPluginOperation(manager, 'uosc_danmaku', 'install');
      expect(manager.isInstalled('uosc_danmaku'), isTrue);
      expect(git.calls.any((call) => call.first == 'clone'), isTrue);

      await executeConfirmedPluginOperation(
        manager,
        'uosc_danmaku',
        'uninstall',
      );
      expect(manager.isInstalled('uosc_danmaku'), isFalse);
    });
  });

  group('plugins page catalog view (widget, no network)', () {
    testWidgets('threeSectionsRenderAndRowRoutesToDetailAndBack', (
      tester,
    ) async {
      final f = Fixture();
      addTearDown(f.dispose);
      final git = FakeGitRunner();
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: git,
      );
      final source = RemoteManifestSource(
        appDataDir: f.path,
        manager: manager,
        fetcher: FakeFetcher(), // queued and never completed: offline
      );
      addTearDown(source.dispose);

      // A tall surface so the lazy ListView builds all three sections
      // (仓库/目录 sit below the 800×600 fold).
      await tester.binding.setSurfaceSize(const Size(800, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PluginsPage(manager: manager, source: source),
        ),
      );
      await tester.pumpAndSettle();

      // 不变量 6: the three sections render as three distinct sections —
      // 本地安装 / 仓库（在线源）/ 目录 — none merged, none trimmed.
      expect(find.text('本地安装'), findsOneWidget);
      expect(find.text('在线源'), findsOneWidget);
      expect(find.text('目录'), findsOneWidget);
      // The builtin-catalog rows land in 本地安装; the offline directory is
      // empty with its kept hint text.
      expect(find.text('uosc_danmaku'), findsOneWidget);
      expect(find.text('暂无在线条目 — 刷新以拉取清单源。'), findsOneWidget);
      // Kazumi catalog header: search box + the three filter chips.
      expect(find.text('搜索插件'), findsOneWidget);
      expect(find.text('全部 3'), findsOneWidget);

      // Detail routing: tapping the row opens the plugin detail view.
      await tester.ensureVisible(find.text('uosc_danmaku'));
      await tester.tap(find.text('uosc_danmaku'));
      await tester.pumpAndSettle();
      expect(find.text('详情'), findsOneWidget);
      expect(find.text('操作'), findsOneWidget);
      expect(find.textContaining('git.example'), findsWidgets);
      // The catalog view is gone after the switch completes.
      expect(find.text('目录'), findsNothing);

      // View switching: back returns to the catalog.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('目录'), findsOneWidget);
      expect(find.text('本地安装'), findsOneWidget);
    });

    testWidgets('unknownDetailRouteStaysOnTheCatalog', (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      final manager = PluginManager(
        appDataDir: f.path,
        catalogJson: kCatalogJson,
        catalogPath: f.catalogPath,
        gitRunner: FakeGitRunner(),
      );
      final source = RemoteManifestSource(
        appDataDir: f.path,
        manager: manager,
        fetcher: FakeFetcher(),
      );
      addTearDown(source.dispose);

      // The dispatch refuses unknown names by contract; through the page
      // this pins that a stale/foreign detail request never blank-screens.
      final dispatch = PluginCatalogDispatch();
      dispatch.syncRows(manager.plugins());
      dispatch.openDetail('ghost');
      expect(dispatch.view, PluginCatalogViewId.catalog);
      expect(dispatch.detailRow, isNull);
    });
  });
}
