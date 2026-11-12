// One catalog row for the plugins page (M6-T4; Kazumi RuleCard 同构 —
// title + status tags + caption lines + trailing affordance, the whole row
// routes to the detail view).
//
// The row body carries the 1.x semantics verbatim (from the pre-M6-T4
// _PluginCardBody): mode/customized badges, status text, url+branch,
// baseline and install-head captions, the enable switch for script plugins
// (next-launch semantics) or the shader-pack note, and the quick actions
// 安装/检查/更新/卸载 — all destructive ones flow through the three-stage
// contract via plugin_update_actions.dart. Tapping anywhere else on the row
// opens the detail view (onTap == null rows stay inert — used by tests that
// only exercise the directory shape).
library;

import 'package:flutter/material.dart';

import 'package:emoplay/bean/widget/split_list_row.dart';

/// Themed status badge. Pairs of colorScheme containers — badges
/// previously used a hardcoded dark brown with the inherited text color,
/// which went unreadable in both themes (Kazumi badges always take the
/// colorScheme container pair).
class PluginBadge extends StatelessWidget {
  const PluginBadge({
    super.key,
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  final String label;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: foregroundColor),
      ),
    );
  }
}

/// Status text of one row (1.x statusText contract, copied verbatim).
String pluginStatusText(Map<String, Object?> entry) {
  final installed = entry['installed'] == true;
  if (!installed) {
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

class PluginCatalogRow extends StatelessWidget {
  const PluginCatalogRow({
    super.key,
    required this.entry,
    required this.busy,
    required this.onOperation,
    required this.onCheck,
    this.onTap,
  });

  final Map<String, Object?> entry;
  final bool busy;
  final Future<void> Function(String name, String action) onOperation;
  final VoidCallback onCheck;

  /// Detail routing (catalog dispatch). Null keeps the row inert.
  final VoidCallback? onTap;

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

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PluginBadge(
                label: entry['mode']! as String,
                color: entry['mode'] == 'replace'
                    ? colors.tertiaryContainer
                    : colors.secondaryContainer,
                foregroundColor: entry['mode'] == 'replace'
                    ? colors.onTertiaryContainer
                    : colors.onSecondaryContainer,
              ),
              if (entry['locallyModified'] == true) ...[
                const SizedBox(width: 6),
                PluginBadge(
                  label: '已定制',
                  color: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                ),
              ],
              const SizedBox(width: 8),
              Text(
                pluginStatusText(entry),
                style: TextStyle(
                  fontSize: 12,
                  color: updateAvailable
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
              // Kazumi RuleCard trailing affordance: the row routes to the
              // detail view.
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
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
                const Expanded(
                  child: Text('启用（下次启动生效）', style: TextStyle(fontSize: 12)),
                ),
                Switch(
                  value: entry['enabled'] == true,
                  onChanged: !_installed || busy
                      ? null
                      : (value) =>
                            onOperation(_name, value ? 'enable' : 'disable'),
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
                TextButton(
                  onPressed: busy ? null : onCheck,
                  child: const Text('检查'),
                ),
              if (_installed)
                TextButton(
                  onPressed: busy ? null : () => onOperation(_name, 'update'),
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
        ],
      ),
    );
    if (onTap == null) {
      return body;
    }
    // The row routes to the detail view; taps on the inner buttons/switch
    // win over the inkwell. The highlight forwards to the SplitListRow
    // press state when the row lives in a ContentSection.group (Kazumi
    // RuleCard: whole card tappable).
    return InkWell(
      onTap: onTap,
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: body,
    );
  }
}
