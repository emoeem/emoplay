// 插件 Tab（SPEC §5）：内置 6 插件 + 在线源，安装/更新/删除三段确认
// （SPEC §4.6 不变量：planOperation → UI 确认 → 执行）。
//
// M6-T4 catalog 重组（docs/EMOPLAY-3.0-ROADMAP.md §五；Kazumi
// plugin_editor 范式同构）：目录视图 + 详情页 + 更新动作分离。
//   - plugins_page.dart = 目录视图（本文件）：Kazumi catalog 的搜索框 +
//     全部/已安装/可更新筛选 chip + 逐行详情路由（plugin_catalog_dispatch）。
//   - 不变量 6（三段式 UI 语义）：本地安装 / 仓库（在线源）/ 目录 三段
//     各自成节，不合并、不裁剪；筛选与搜索只收窄各段行数，不改段结构。
//   - 详情页见 plugin_detail_page.dart；操作编排见
//     plugin_update_actions.dart（Kazumi plugin_update_actions.dart 同构）。
//
// Flutter counterpart of mpv-emo qml/PluginDrawer.qml +
// PluginRemoteSection.qml + PluginPage.qml. Semantics kept:
//   - enable/disable applies immediately (non-destructive and reversible —
//     the scripts option is only assembled at the next launch); everything
//     else goes through the plan dialog first.
//   - Check-mode plugins ("本地定制永不覆盖"): updates only compare the
//     remote HEAD with the manifest baseline via git ls-remote; local
//     customizations are never overwritten. Replace-mode updates re-clone
//     and swap, but are refused when local modifications are detected.
//   - Online sources degrade gracefully: a network failure keeps the last
//     cached list and lands in the hint line, never a crash.
//   - First page mount triggers one online refresh per session (the 1.x
//     drawer's refreshOnShow contract); later visits reuse the cache until
//     the user hits Refresh.
library;

import 'package:flutter/material.dart';

import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/plugins/plugin_catalog_dispatch.dart';
import 'package:emoplay/pages/plugins/plugin_catalog_row.dart';
import 'package:emoplay/pages/plugins/plugin_detail_page.dart';
import 'package:emoplay/pages/plugins/plugin_update_actions.dart';
import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/remote_manifest_source.dart';
import 'package:emoplay/utils/date_time.dart' as date_fmt;

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, this.manager, this.source});

  /// Injectable stores for headless tests (fake git/fetcher seams, temp
  /// app-data); production resolves [MediaStores.instance] lazily, so a
  /// non-null injection never touches the real singletons.
  final PluginManager? manager;
  final RemoteManifestSource? source;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  final PluginCatalogDispatch _dispatch = PluginCatalogDispatch();
  final TextEditingController _search = TextEditingController();
  bool _refreshedOnce = false;
  String _statusMessage = '';
  bool _statusIsError = false;

  PluginManager get _manager => widget.manager ?? MediaStores.instance.plugins;
  RemoteManifestSource get _source =>
      widget.source ?? MediaStores.instance.pluginSources;

  @override
  void initState() {
    super.initState();
    _manager.onOperationFinished = _onOperationFinished;
  }

  @override
  void dispose() {
    _manager.onOperationFinished = null;
    _search.dispose();
    _dispatch.dispose();
    super.dispose();
  }

  void _onOperationFinished(
    String name,
    String action,
    bool success,
    String message,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
      _statusIsError = !success;
    });
  }

  // ---- three-stage confirmation ---------------------------------------------

  /// The three-stage contract lives in plugin_update_actions.dart; the page
  /// only funnels (name, action) pairs in and surfaces status out.
  Future<void> _beginOperation(String name, String action) {
    return beginPluginOperation(
      context,
      manager: _manager,
      name: name,
      action: action,
      onStatus: (message, isError) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage = message;
          _statusIsError = isError;
        });
      },
    );
  }

  String _newestRefreshLabel() {
    var best = 0;
    for (final row in _source.sources) {
      final ms = row['lastRefreshMs'] as int? ?? 0;
      if (ms > best) {
        best = ms;
      }
    }
    if (best == 0) {
      return '从未刷新';
    }
    return '上次刷新：${date_fmt.formatDateTime(DateTime.fromMillisecondsSinceEpoch(best))}';
  }

  // ---- catalog plumbing -------------------------------------------------------

  /// The rows backing the detail route: local manager rows first (builtin
  /// names stay authoritative), then the online directory entries; the
  /// dispatch dedupes by name keeping the first.
  List<Map<String, Object?>> _catalogRows() => <Map<String, Object?>>[
    ..._manager.plugins(),
    ..._source.entries,
  ];

  Widget _statusLine(BuildContext context) {
    return Text(
      _statusMessage,
      style: TextStyle(
        color: _statusIsError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Kazumi catalog header (plugin_catalog_view.dart): search field +
  /// 全部/已安装/可更新 chips with counts. Shapes the directory rows; the
  /// three sections stay distinct (不变量 6).
  Widget _catalogHeader(
    BuildContext context,
    int total,
    int installed,
    int updates,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: _dispatch.setQuery,
          decoration: InputDecoration(
            hintText: '搜索插件',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      _search.clear();
                      _dispatch.setQuery('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final entry in [
              (PluginCatalogFilter.all, '全部 $total'),
              (PluginCatalogFilter.installed, '已安装 $installed'),
              (PluginCatalogFilter.updates, '可更新 $updates'),
            ])
              FilterChip(
                label: Text(entry.$2),
                selected: _dispatch.filter == entry.$1,
                onSelected: (_) => _dispatch.setFilter(entry.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Kazumi 次要文案 idiom：bodySmall + onSurfaceVariant 弱化，
        // 提示行不再与卡片标题抢对比度。
        Text(
          '本地定制永不覆盖：check 模式插件只比较远端 HEAD 与 baseline；'
          'replace 模式更新在检测到本地改动时会被拒绝。启用的插件在下次启动时'
          '追加进 scripts 选项。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _catalogRowFor(BuildContext context, Map<String, Object?> entry) {
    return PluginCatalogRow(
      key: ValueKey('row/${entry['name']}'),
      entry: entry,
      busy: _manager.busy,
      onOperation: _beginOperation,
      onCheck: () => _manager.checkForUpdate(entry['name']! as String),
      onTap: () => _dispatch.openDetail(entry['name']! as String),
    );
  }

  // ---- views ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_manager, _source, _dispatch]),
      builder: (context, _) {
        // First mount refreshes the online sources once per session.
        if (!_refreshedOnce) {
          _refreshedOnce = true;
          _source.refreshAll();
        }
        _dispatch.syncRows(_catalogRows());
        final detail = _dispatch.detailRow;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: detail == null
              ? _catalogView(context, key: const ValueKey('catalog'))
              : PluginDetailPage(
                  key: ValueKey('detail/${detail['name']}'),
                  row: detail,
                  busy: _manager.busy,
                  statusMessage: _statusMessage,
                  statusIsError: _statusIsError,
                  onBack: _dispatch.backToCatalog,
                  onOperation: _beginOperation,
                  onCheck: () =>
                      _manager.checkForUpdate(detail['name']! as String),
                ),
        );
      },
    );
  }

  Widget _catalogView(BuildContext context, {Key? key}) {
    final localRows = _dispatch.visibleRows(_manager.plugins());
    final entryRows = _dispatch.visibleRows(_source.entries);

    // Chip counts run over the merged catalog (name-deduped, manager rows
    // first) — the same set the detail route resolves against.
    final merged = _catalogRows();
    final seen = <String>{};
    var installedCount = 0;
    var updatesCount = 0;
    for (final row in merged) {
      final name = row['name'] as String? ?? '';
      if (name.isEmpty || !seen.add(name)) {
        continue;
      }
      if (row['installed'] == true) {
        installedCount++;
      }
      if (row['updateAvailable'] == true) {
        updatesCount++;
      }
    }

    return Scaffold(
      key: key,
      appBar: AppBar(
        title: const Text('插件'),
        centerTitle: false,
        actions: [
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _manager.busy ? null : () => _manager.checkAll(),
                icon: const Icon(Icons.sync_rounded, size: 20),
                label: const Text('全部检查'),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _statusLine(context),
            ),
          _catalogHeader(context, merged.length, installedCount, updatesCount),
          // ---- 三段式（不变量 6）：本地安装 / 仓库（在线源）/ 目录 ----
          ContentSection.group(
            title: '本地安装',
            description: '本地清单与安装状态，点击行进入详情。',
            children: [
              if (localRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Text('没有符合筛选条件的本地插件。'),
                )
              else
                for (final entry in localRows) _catalogRowFor(context, entry),
            ],
          ),
          const SizedBox(height: 16),
          _SourceRepositorySection(
            source: _source,
            manager: _manager,
            newestRefreshLabel: _newestRefreshLabel(),
          ),
          const SizedBox(height: 16),
          ContentSection.group(
            title: '目录',
            description: '在线清单条目，点击行进入详情。',
            children: [
              if (_source.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('暂无在线条目 — 刷新以拉取清单源。'),
                )
              else if (entryRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('没有符合筛选条件的目录条目。'),
                )
              else
                for (final entry in entryRows) _catalogRowFor(context, entry),
            ],
          ),
        ],
      ),
    );
  }
}

/// 仓库（在线源）段: the manifest-source management kept verbatim from the
/// pre-M6-T4 在线源 section (sources add/remove/refresh, refresh label,
/// error line). Its plugin entries moved to the 目录 section — the segment
/// itself is neither merged nor trimmed (不变量 6).
class _SourceRepositorySection extends StatefulWidget {
  const _SourceRepositorySection({
    required this.source,
    required this.manager,
    required this.newestRefreshLabel,
  });

  final RemoteManifestSource source;
  final PluginManager manager;
  final String newestRefreshLabel;

  @override
  State<_SourceRepositorySection> createState() =>
      _SourceRepositorySectionState();
}

class _SourceRepositorySectionState extends State<_SourceRepositorySection> {
  final TextEditingController _sourceInput = TextEditingController();

  @override
  void dispose() {
    _sourceInput.dispose();
    super.dispose();
  }

  void _addSource() {
    final url = Uri.tryParse(_sourceInput.text.trim());
    if (url == null || url.toString().isEmpty) {
      return;
    }
    // A rejection reports the precise reason via lastError (rendered in the
    // hint line); the typed text stays in the field so it can be corrected.
    if (widget.source.addSource(url)) {
      _sourceInput.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final manager = widget.manager;
    return ContentSection.group(
      title: '在线源',
      description: '仓库清单源：默认源与自定义源的增删、刷新。',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  source.refreshing ? '正在拉取在线源…' : widget.newestRefreshLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: source.refreshing
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: (source.refreshing || manager.busy)
                    ? null
                    : () => source.refreshAll(),
                child: const Text('刷新'),
              ),
            ],
          ),
        ),
        if (source.lastError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              source.lastError,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final row in source.sources)
          ListTile(
            dense: true,
            title: Text(
              row['url']! as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: row['isDefault'] == true
                ? Text(
                    '默认',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : TextButton(
                    onPressed: source.refreshing
                        ? null
                        : () => source.removeSource(
                            Uri.parse(row['url']! as String),
                          ),
                    child: const Text('移除'),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _sourceInput,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: '添加清单源 URL（https://…）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _addSource(),
          ),
        ),
      ],
    );
  }
}
