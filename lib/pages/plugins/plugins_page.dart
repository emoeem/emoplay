// 插件 Tab（SPEC §5）：内置 6 插件 + 在线源，安装/更新/删除三段确认
// （SPEC §4.6 不变量：planOperation → UI 确认 → 执行）。
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

import 'package:emoplay/bean/dialog/dialog.dart';
import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/remote_manifest_source.dart';
import 'package:emoplay/utils/date_time.dart' as date_fmt;

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  bool _refreshedOnce = false;
  String _statusMessage = '';
  bool _statusIsError = false;

  PluginManager get _manager => MediaStores.instance.plugins;
  RemoteManifestSource get _source => MediaStores.instance.pluginSources;

  @override
  void initState() {
    super.initState();
    _manager.onOperationFinished = _onOperationFinished;
  }

  @override
  void dispose() {
    _manager.onOperationFinished = null;
    super.dispose();
  }

  void _onOperationFinished(
      String name, String action, bool success, String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
      _statusIsError = !success;
    });
  }

  // ---- three-stage confirmation ---------------------------------------------

  /// Stage 1: plan. Stage 2: dialog. Stage 3: execute — the manager never
  /// performs an install/update/uninstall without the confirmed plan.
  Future<void> _beginOperation(String name, String action) async {
    // Enable/disable applies immediately: it is non-destructive and
    // reversible, and planOperation only plans the three destructive
    // actions (an enable/disable plan would be refused as an unknown
    // action, leaving the switch stuck on the model value).
    if (action == 'enable' || action == 'disable') {
      _manager.setEnabled(name, action == 'enable');
      return;
    }
    final plan = _manager.planOperation(name, action);
    if (plan.containsKey('error')) {
      setState(() {
        _statusMessage = plan['error']! as String;
        _statusIsError = true;
      });
      return;
    }
    final confirmed = await EmoDialog.show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(plan['title']! as String),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in plan['details']! as List<String>)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return; // refused: nothing was executed
    }
    switch (action) {
      case 'install':
        await _manager.install(name);
      case 'uninstall':
        await _manager.uninstall(name);
      case 'update':
        await _manager.update(name);
    }
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

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: ListenableBuilder(
        listenable: Listenable.merge([_manager, _source]),
        builder: (context, _) {
          // First mount refreshes the online sources once per session.
          if (!_refreshedOnce) {
            _refreshedOnce = true;
            _source.refreshAll();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusIsError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Text(
                '本地定制永不覆盖：check 模式插件只比较远端 HEAD 与 baseline；'
                'replace 模式更新在检测到本地改动时会被拒绝。启用的插件在下次启动时'
                '追加进 scripts 选项。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              _RemoteSourcesSection(
                source: _source,
                manager: _manager,
                onOperation: _beginOperation,
                newestRefreshLabel: _newestRefreshLabel(),
              ),
              const SizedBox(height: 16),
              ...[
                for (final entry in _manager.plugins())
                  _PluginCard(
                    entry: entry,
                    busy: _manager.busy,
                    onOperation: _beginOperation,
                    onCheck: () => _manager.checkForUpdate(
                        entry['name']! as String),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RemoteSourcesSection extends StatefulWidget {
  const _RemoteSourcesSection({
    required this.source,
    required this.manager,
    required this.onOperation,
    required this.newestRefreshLabel,
  });

  final RemoteManifestSource source;
  final PluginManager manager;
  final Future<void> Function(String name, String action) onOperation;
  final String newestRefreshLabel;

  @override
  State<_RemoteSourcesSection> createState() => _RemoteSourcesSectionState();
}

class _RemoteSourcesSectionState extends State<_RemoteSourcesSection> {
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
                ? const Text('默认', style: TextStyle(fontSize: 11))
                : TextButton(
                    onPressed: source.refreshing
                        ? null
                        : () => source
                            .removeSource(Uri.parse(row['url']! as String)),
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
        for (final entry in source.entries)
          _PluginCardBody(
            entry: entry,
            busy: manager.busy,
            onOperation: widget.onOperation,
            onCheck: () =>
                manager.checkForUpdate(entry['name']! as String),
          ),
        if (source.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '暂无在线条目 — 刷新以拉取清单源。',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.entry,
    required this.busy,
    required this.onOperation,
    required this.onCheck,
  });

  final Map<String, Object?> entry;
  final bool busy;
  final Future<void> Function(String name, String action) onOperation;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TonalCard(
        child: _PluginCardBody(
          entry: entry,
          busy: busy,
          onOperation: onOperation,
          onCheck: onCheck,
        ),
      ),
    );
  }
}

class _PluginCardBody extends StatelessWidget {
  const _PluginCardBody({
    required this.entry,
    required this.busy,
    required this.onOperation,
    required this.onCheck,
  });

  final Map<String, Object?> entry;
  final bool busy;
  final Future<void> Function(String name, String action) onOperation;
  final VoidCallback onCheck;

  String get _name => entry['name']! as String;
  bool get _installed => entry['installed'] == true;
  bool get _isScript => entry['isScript'] == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final updateAvailable = entry['updateAvailable'] == true;
    final baseline = entry['baseline'] as String? ?? '';
    final head = entry['head'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _Badge(
                label: entry['mode']! as String,
                color: entry['mode'] == 'replace'
                    ? colors.tertiaryContainer
                    : colors.secondaryContainer,
              ),
              if (entry['locallyModified'] == true) ...[
                const SizedBox(width: 6),
                const _Badge(label: '已定制', color: Color(0xFF5a3d1e)),
              ],
              const Spacer(),
              Text(
                _statusTextOf(),
                style: TextStyle(
                  fontSize: 12,
                  color: updateAvailable
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${entry['url']}  (${entry['branch']})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          if (baseline.isNotEmpty)
            Text(
              'Baseline $baseline（本地定制基于该上游版本）',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          if (_installed && head.isNotEmpty)
            Text(
              '已安装自 ${head.substring(0, head.length > 12 ? 12 : head.length)}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          if (_isScript)
            Row(
              children: [
                const Expanded(child: Text('启用（下次启动生效）', style: TextStyle(fontSize: 12))),
                Switch(
                  value: entry['enabled'] == true,
                  onChanged: !_installed || busy
                      ? null
                      : (value) => onOperation(_name, value ? 'enable' : 'disable'),
                ),
              ],
            )
          else
            Text(
              '着色器包 — 由画质面板手动挂载，不经 scripts 生效',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              if (!_installed)
                TextButton(
                  onPressed: busy ? null : () => onOperation(_name, 'install'),
                  child: const Text('安装'),
                ),
              if (_installed)
                TextButton(onPressed: busy ? null : onCheck, child: const Text('检查')),
              if (_installed)
                TextButton(
                  onPressed: busy ? null : () => onOperation(_name, 'update'),
                  child: const Text('更新'),
                ),
              if (_installed)
                TextButton(
                  onPressed: busy ? null : () => onOperation(_name, 'uninstall'),
                  child: const Text('卸载'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusTextOf() {
    if (!_installed) {
      return '未安装';
    }
    if (entry['updateAvailable'] == true) {
      return '有可用更新';
    }
    if ((entry['remoteHead'] as String? ?? '').isNotEmpty) {
      return '已是最新';
    }
    return '已安装';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}
