// Catalog dispatch for the plugins page (M6-T4, docs/EMOPLAY-3.0-ROADMAP.md
// §五; Kazumi plugin_editor 同构 — plugin_catalog_view.dart drives its
// catalog with search + 全部/已安装/可更新 filter chips and pushes a detail
// page per rule; EmoPlay keeps the tab-mounted page and dispatches between
// the two views in place, so tab state survives per SPEC §5).
//
// The dispatch owns exactly three concerns, all headless-testable:
//   1. view switching — 目录视图 ⇄ 详情页;
//   2. detail routing — a detail is only ever opened for a name that
//      resolves in the synced catalog rows; unknown names are refused, and
//      a detail whose row disappears (uninstall / source refresh) falls
//      back to the catalog on the next build pass instead of lingering;
//   3. directory shaping — the Kazumi search box and filter chips
//      (全部/已安装/可更新) narrow each section's rows; they transform the
//      view, they never merge or trim the three sections themselves
//      (不变量 6: 本地安装/仓库/目录三段不合并、不裁剪).
library;

import 'package:flutter/foundation.dart';

/// Which view the plugins page shows: the three-section catalog or one
/// plugin's detail page.
enum PluginCatalogViewId { catalog, detail }

/// The Kazumi catalog filter chips (plugin_catalog_view.dart
/// `_CatalogFilter`), mapped onto the EmoPlay row fields.
enum PluginCatalogFilter { all, installed, updates }

class PluginCatalogDispatch extends ChangeNotifier {
  final Map<String, Map<String, Object?>> _rowsByName =
      <String, Map<String, Object?>>{};

  PluginCatalogViewId _view = PluginCatalogViewId.catalog;
  String _detailName = '';
  PluginCatalogFilter _filter = PluginCatalogFilter.all;
  String _query = '';

  PluginCatalogViewId get view => _view;

  /// The routed detail row's plugin name ('' on the catalog view).
  String get detailName => _detailName;

  PluginCatalogFilter get filter => _filter;

  String get query => _query;

  /// The row the detail view renders, or null when the catalog view is up
  /// (or the routed name no longer resolves — the page then renders the
  /// catalog instead of a stale detail).
  Map<String, Object?>? get detailRow =>
      _view == PluginCatalogViewId.detail ? _rowsByName[_detailName] : null;

  /// Re-indexes the catalog rows that back the detail route — local
  /// manager rows first (builtin names stay authoritative), then the online
  /// directory entries. Silent on purpose: the page calls this from its
  /// build pass, so notifying here would notify during build.
  ///
  /// When the routed row vanishes (uninstall, removed source), the view
  /// falls back to the catalog immediately; the page's builder reads the
  /// adjusted state in the same pass.
  void syncRows(Iterable<Map<String, Object?>> rows) {
    _rowsByName.clear();
    for (final row in rows) {
      final name = row['name'];
      // First wins: local manager rows are synced before the online
      // directory entries, so a builtin name keeps its authoritative row
      // (Map.addEntries would keep the LAST duplicate instead).
      if (name is String && name.isNotEmpty && !_rowsByName.containsKey(name)) {
        _rowsByName[name] = row;
      }
    }
    if (_view == PluginCatalogViewId.detail &&
        !_rowsByName.containsKey(_detailName)) {
      _view = PluginCatalogViewId.catalog;
      _detailName = '';
    }
  }

  /// Detail routing: only a known plugin name opens the detail view.
  /// Unknown names are refused — the catalog stays put, nothing crashes.
  void openDetail(String name) {
    if (!_rowsByName.containsKey(name)) {
      return;
    }
    _view = PluginCatalogViewId.detail;
    _detailName = name;
    notifyListeners();
  }

  void backToCatalog() {
    if (_view == PluginCatalogViewId.catalog) {
      return;
    }
    _view = PluginCatalogViewId.catalog;
    _detailName = '';
    notifyListeners();
  }

  void setFilter(PluginCatalogFilter value) {
    if (_filter == value) {
      return;
    }
    _filter = value;
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    notifyListeners();
  }

  /// The directory rows after the Kazumi filter chips + search box: name
  /// substring (case-insensitive) plus 全部/已安装/可更新. Pure — each
  /// section feeds its own rows through this and keeps its identity.
  List<Map<String, Object?>> visibleRows(Iterable<Map<String, Object?>> rows) {
    final needle = _query.trim().toLowerCase();
    return <Map<String, Object?>>[
      for (final row in rows)
        if (_matches(row, needle)) row,
    ];
  }

  bool _matches(Map<String, Object?> row, String needle) {
    final name = row['name'] as String? ?? '';
    if (needle.isNotEmpty && !name.toLowerCase().contains(needle)) {
      return false;
    }
    return switch (_filter) {
      PluginCatalogFilter.all => true,
      PluginCatalogFilter.installed => row['installed'] == true,
      PluginCatalogFilter.updates => row['updateAvailable'] == true,
    };
  }
}
