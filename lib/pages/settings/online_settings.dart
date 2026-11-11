// 设置中心「在线元数据」分类页（roadmap M4-T7，2026-11-12 用户改向纳入）。
//
// 两件事，全部本地优先语义：
//  - 总开关（settings.json online.enabled，默认 FALSE）：关闭时
//    OnlineMetaService 的门禁第一步就返回 disabled，机器上永远没有
//    联网元数据请求（test/online_meta_service_test.dart 锁定）。
//  - TMDB API key（online.apiKey，默认 ''）：用户自行在 themoviedb.org
//    申请后填入；空 key 即 noKey 降级路径。key 只落本机 settings.json，
//    不内置、不上传（输入框 obscure 显示，确认后 trim）。
//
// SPEC §6 的 11 分类没有本分类，作为用户改向新增项挂在「应用」组
//（存储与缓存之后）；键追加与往返用例见 test/emoplay_settings_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

class OnlineSettingsPage extends StatefulWidget {
  const OnlineSettingsPage({super.key});

  @override
  State<OnlineSettingsPage> createState() => _OnlineSettingsPageState();
}

class _OnlineSettingsPageState extends State<OnlineSettingsPage> {
  EmoPlaySettings get _settings => MediaStores.instance.settings;

  void _persist() {
    if (!_settings.save()) {
      EmoDialog.showToast(
          context: context, message: '设置保存失败（内存态保持生效）');
    }
  }

  /// API key 编辑对话框：obscure 输入，确定时 trim 落盘，空值即清除
  ///（回到 noKey 降级路径）。
  Future<void> _editApiKey() async {
    final controller = TextEditingController(text: _settings.onlineApiKey);
    final saved = await EmoDialog.show<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('TMDB API key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在 themoviedb.org 注册后在账户设置 → API 申请。'
                  'key 只保存在本机 settings.json。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.singleLineFormatter,
                ],
                decoration: const InputDecoration(
                  labelText: '32 位十六进制 key',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (saved != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _settings.onlineApiKey = controller.text);
    _persist();
    EmoDialog.showToast(
        context: context,
        message: _settings.onlineApiKey.isEmpty ? '已清除 API key' : 'API key 已保存');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiKey = _settings.onlineApiKey;
    return SettingsDetailScaffold(
      title: const Text('在线元数据'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('联网补全（本地优先）'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.cloud_sync_outlined,
                title: const Text('启用在线元数据'),
                description: const Text(
                    '默认关闭。开启后仅对没有本地 NFO 的媒体发起 TMDB 查询；'
                    '断网、超时或损坏响应一律降级到本地数据。'),
                initialValue: _settings.onlineEnabled,
                onToggle: (value) {
                  setState(() => _settings.onlineEnabled = value ?? !_settings.onlineEnabled);
                  _persist();
                },
              ),
              SettingsTile(
                leading: Icons.key_rounded,
                title: const Text('TMDB API key'),
                description: Text(
                  apiKey.isEmpty ? '未设置（联网补全不可用）' : '已设置 · ${_maskKey(apiKey)}',
                  style: TextStyle(
                    color: apiKey.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onPressed: (_) => _editApiKey(),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('说明'),
            tiles: [
              SettingsTile(
                leading: Icons.info_outline_rounded,
                title: const Text('本地优先纪律'),
                description: const Text(
                    '有本地 NFO 的条目永不联网；查询结果落 media_online.json 缓存，'
                    '命中缓存不再发请求。本框架轮的真实数据流需有效 key 后人工验收。'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 掩码显示：保留前后各 2 位，中间用 • 遮住（短 key 全遮）。
  String _maskKey(String key) {
    if (key.length <= 4) {
      return '••••';
    }
    return '${key.substring(0, 2)}••••${key.substring(key.length - 2)}'
        '（${key.length} 位）';
  }
}
