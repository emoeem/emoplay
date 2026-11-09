// 设置中心「诊断」分类页 (SPEC §6 category 10)：appVersion / mpvVersion /
// renderBackend / dataDir / configDir / logDir，全部运行时读取。
//
// 1.x SettingsPage 的诊断段落（qml/SettingsPage.qml §6）+ DiagnosticsInfo
// 的 Flutter 对应页；附一段可复制的诊断文本（1.x diagnosticsText()）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/diagnostics/diagnostics_info.dart';

class DiagnosticsSettingsPage extends StatelessWidget {
  const DiagnosticsSettingsPage({super.key});

  Future<DiagnosticsSnapshot> _collect(DiagnosticsInfo info) async {
    final mpvVersion = await info.mpvVersion();
    final renderBackend = await info.renderBackend();
    return DiagnosticsSnapshot(mpvVersion: mpvVersion, renderBackend: renderBackend);
  }

  String _diagnosticsText(DiagnosticsInfo info, DiagnosticsSnapshot snapshot) {
    return [
      'EmoPlay ${info.appVersion}',
      'libmpv ${snapshot.mpvVersion == 'unknown' ? '未知' : snapshot.mpvVersion}',
      '渲染后端 ${snapshot.renderBackend}',
      '数据目录 ${info.dataDir}',
      '配置目录 ${info.configDir}',
      '日志目录 ${info.logDir}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final info = MediaStores.instance.diagnostics;
    return SettingsDetailScaffold(
      title: const Text('诊断'),
      body: FutureBuilder<DiagnosticsSnapshot>(
        future: _collect(info),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('版本'),
                tiles: [
                  SettingsTile(
                    leading: Icons.info_outline_rounded,
                    title: const Text('EmoPlay'),
                    description: Text(info.appVersion),
                  ),
                  SettingsTile(
                    leading: Icons.play_circle_outline_rounded,
                    title: const Text('libmpv'),
                    description: Text(data == null
                        ? '读取中…'
                        : (data.mpvVersion == 'unknown'
                            ? '未知（当前没有播放会话）'
                            : data.mpvVersion)),
                  ),
                  SettingsTile(
                    leading: Icons.monitor_rounded,
                    title: const Text('渲染后端'),
                    description: Text(data == null
                        ? '读取中…'
                        : (data.renderBackend == 'unknown'
                            ? '未知（当前没有播放会话）'
                            : data.renderBackend)),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('目录'),
                tiles: [
                  SettingsTile(
                    leading: Icons.folder_rounded,
                    title: const Text('数据目录'),
                    description: Text(info.dataDir),
                  ),
                  SettingsTile(
                    leading: Icons.settings_outlined,
                    title: const Text('配置目录'),
                    description: Text(info.configDir),
                  ),
                  SettingsTile(
                    leading: Icons.article_outlined,
                    title: const Text('日志目录'),
                    description: Text(info.logDir),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('诊断信息'),
                tiles: [
                  if (data != null)
                    SettingsTile(
                      leading: Icons.copy_rounded,
                      title: const Text('复制诊断信息'),
                      description: const Text('报告问题时请附上这段文本'),
                      onPressed: (_) async {
                        await Clipboard.setData(ClipboardData(
                            text: _diagnosticsText(info, data)));
                        if (context.mounted) {
                          EmoDialog.showToast(
                              context: context, message: '已复制到剪贴板');
                        }
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
