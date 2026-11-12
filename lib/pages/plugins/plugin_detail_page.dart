// One plugin's detail view (M6-T4, docs/EMOPLAY-3.0-ROADMAP.md §五;
// Kazumi plugin_view_page.dart 同构: the catalog row routes here, the view
// shows the full metadata and hosts the per-plugin actions).
//
// Everything destructive keeps the three-stage contract
// (SPEC §4.6 不变量 6) through plugin_update_actions.dart; the enable
// switch keeps its 1.x next-launch semantics. Metadata surfaces the
// M6-T1 integrity pair (sizeBytes + sha256) and the destination/entry
// path whenever the row carries them (online directory entries may not).
library;

import 'package:flutter/material.dart';

import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/bean/widget/tonal_card.dart';
import 'package:emoplay/pages/plugins/plugin_catalog_row.dart';

class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({
    super.key,
    required this.row,
    required this.busy,
    required this.statusMessage,
    required this.statusIsError,
    required this.onBack,
    required this.onOperation,
    required this.onCheck,
  });

  final Map<String, Object?> row;
  final bool busy;
  final String statusMessage;
  final bool statusIsError;
  final VoidCallback onBack;
  final Future<void> Function(String name, String action) onOperation;
  final VoidCallback onCheck;

  String get _name => row['name']! as String;
  bool get _installed => row['installed'] == true;
  bool get _isScript => row['isScript'] == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final updateAvailable = row['updateAvailable'] == true;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回目录',
          onPressed: onBack,
        ),
        title: Text(_name),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                statusMessage,
                style: TextStyle(
                  color: statusIsError ? colors.error : colors.onSurfaceVariant,
                ),
              ),
            ),
          TonalCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PluginBadge(
                        label: row['mode']! as String,
                        color: row['mode'] == 'replace'
                            ? colors.tertiaryContainer
                            : colors.secondaryContainer,
                        foregroundColor: row['mode'] == 'replace'
                            ? colors.onTertiaryContainer
                            : colors.onSecondaryContainer,
                      ),
                      if (row['locallyModified'] == true) ...[
                        const SizedBox(width: 6),
                        PluginBadge(
                          label: '已定制',
                          color: colors.errorContainer,
                          foregroundColor: colors.onErrorContainer,
                        ),
                      ],
                      const Spacer(),
                      Text(
                        pluginStatusText(row),
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
                  if (_isScript)
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '启用（下次启动生效）',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Switch(
                          value: row['enabled'] == true,
                          onChanged: !_installed || busy
                              ? null
                              : (value) => onOperation(
                                  _name,
                                  value ? 'enable' : 'disable',
                                ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '着色器包 — 由画质面板手动挂载，不经 scripts 生效',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ContentSection.group(
            title: '详情',
            children: [
              for (final entry in _metadataRows())
                ListTile(
                  dense: true,
                  title: Text(entry.$1, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    entry.$2,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ContentSection.group(
            title: '操作',
            description:
                '安装/更新/卸载先列出变更清单并确认后执行'
                '（planOperation → UI 确认 → 执行）。',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (!_installed)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => onOperation(_name, 'install'),
                        child: const Text('安装'),
                      ),
                    if (_installed)
                      TextButton(
                        onPressed: busy ? null : onCheck,
                        child: const Text('检查'),
                      ),
                    if (_installed)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => onOperation(_name, 'update'),
                        child: const Text('更新'),
                      ),
                    if (_installed)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => onOperation(_name, 'uninstall'),
                        child: const Text('卸载'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// (label, value) pairs for the 详情 section — only fields the row
  /// actually carries, in 1.x order, with the M6-T1 integrity pair last.
  List<(String, String)> _metadataRows() {
    final rows = <(String, String)>[
      ('来源', '${row['url']}  (${row['branch']})'),
    ];
    final destination = row['destination'] as String? ?? '';
    if (destination.isNotEmpty) {
      rows.add(('安装目标 destination', destination));
    }
    final baseline = row['baseline'] as String? ?? '';
    if (baseline.isNotEmpty) {
      rows.add(('Baseline', '$baseline（本地定制基于该上游版本）'));
    }
    final head = row['head'] as String? ?? '';
    if (_installed && head.isNotEmpty) {
      rows.add(('已安装自', head));
    }
    final remoteHead = row['remoteHead'] as String? ?? '';
    if (remoteHead.isNotEmpty) {
      rows.add(('远端 HEAD', remoteHead));
    }
    final sha256 = row['sha256'] as String? ?? '';
    final sizeBytes = row['sizeBytes'] as int? ?? 0;
    if (sha256.isNotEmpty || sizeBytes > 0) {
      rows.add((
        '完整性（M6-T1）',
        'sha256 ${sha256.isEmpty ? '未固定' : sha256}'
            '${sizeBytes > 0 ? ' · $sizeBytes bytes' : ''}',
      ));
    }
    final entryPath = row['entryPath'] as String? ?? '';
    if (entryPath.isNotEmpty) {
      rows.add(('scripts 入口', entryPath));
    }
    return rows;
  }
}
