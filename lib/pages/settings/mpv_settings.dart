// 设置中心「mpv 配置」分类页 (SPEC §6 category 5)：导入向导重跑、导入
// 决策重置、当前生效选项审计表。
//
// 审计表如实呈现两件事：compat 层组装的导入选项 + MpvPlayerProperties 的
// 预置（load-scripts=no、写路径重定向、插件 scripts 追加）——即 1.x
// main.cpp 装配顺序的最终产物，下一次启动才生效（向导选择的 2.0 语义，
// 与 MediaStores.init 一次性组装一致）。
import 'package:flutter/material.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/settings/import_wizard_dialog.dart';

class MpvSettingsPage extends StatelessWidget {
  const MpvSettingsPage({super.key});

  static const Map<String, String> _decisionLabels = {
    '': '未决定（首次启动时询问）',
    'full': '完整导入',
    'selective': '选择性导入',
    'standalone': '独立配置（不读用户目录）',
    'skip': '跳过',
  };

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await EmoDialog.show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('重置导入决策？'),
        content: const Text(
            '将清除已记录的 mpv 配置导入决策；下次启动会重新询问。已导入的选项在重新导入前保持原样。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final stores = MediaStores.instance;
    stores.settings.setImportDecision('');
    stores.settings.dontAskAgain = false;
    if (!stores.settings.save()) {
      EmoDialog.showToast(context: context, message: '设置保存失败，请检查磁盘');
    } else {
      EmoDialog.showToast(context: context, message: '导入决策已重置，下次启动重新询问');
    }
  }

  Future<void> _rerunWizard(BuildContext context) async {
    // The wizard's choice persists and applies on the NEXT launch (2.0
    // one-shot startup assembly, docs/SPEC.md §4.3).
    MediaStores.instance.compat.requestWizard();
    await showMpvImportWizardDialog();
  }

  @override
  Widget build(BuildContext context) {
    final stores = MediaStores.instance;
    final compat = stores.compat;
    final audit = stores.startupMpvProperties;
    return SettingsDetailScaffold(
      title: const Text('mpv 配置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('导入'),
            tiles: [
              SettingsTile(
                leading: Icons.movie_creation_outlined,
                title: const Text('重跑导入向导'),
                description: Text(
                    '检测到的配置目录：${compat.configDetected ? compat.sourceDir : '（无）'}'),
                onPressed: (_) => _rerunWizard(context),
              ),
              SettingsTile(
                leading: Icons.restart_alt_rounded,
                title: const Text('重置导入决策'),
                description: Text(
                    '当前决策：${_decisionLabels[compat.importDecision] ?? compat.importDecision}'),
                onPressed: (_) => _confirmReset(context),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('当前生效选项（下次启动组装结果）'),
            bottomInfo: Text(
                '共 ${audit.length} 项：compat 导入选项 + 预置（load-scripts=no、写路径重定向、插件 scripts 追加）。'
                '直接改动 mpv 配置文件不会被 EmoPlay 捕获，请使用导入向导。'),
            tiles: [
              for (final entry in audit.entries)
                SettingsTile(
                  title: Text(entry.key),
                  description: Text(
                    entry.value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
