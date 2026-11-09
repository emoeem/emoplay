import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/services/update_checker.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// Update settings.
///
/// The toggle drives the startup check wiring in lib/main.dart: when enabled
/// (default), one background GET of the GitHub releases API per launch
/// (mpv-emo src/main.cpp:315-321 semantics) against
/// repos/emoeem/emoplay/releases/latest via lib/services/update_checker.dart.
/// The result is only ever reported — never downloaded or installed — and
/// every failure mode stays silent (1.x contract): a network-less launch
/// looks exactly like an up-to-date one. When a newer release *is* confirmed,
/// the tile below surfaces the release page (the 1.x qml/UpdateBadge.qml
/// role: opening the page is user-initiated and nothing else happens).
class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  bool _autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);

  // The startup check (3s after launch) may land while this page is open;
  // the found-update section below reads the checker state, so rebuild on it.
  void _onCheckerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    UpdateChecker.instance.addListener(_onCheckerChanged);
  }

  @override
  void dispose() {
    UpdateChecker.instance.removeListener(_onCheckerChanged);
    super.dispose();
  }

  Future<void> _openReleasePage(String url) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('更新设置'),
        body: SettingsList(
          sections: [
            SettingsSection(
              title: const Text('启动时检查更新'),
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.update_rounded,
                  title: const Text('应用更新'),
                  description: const Text('当前版本 $appVersion · 更新源 GitHub Releases'),
                  initialValue: _autoUpdate,
                  onToggle: (value) {
                    setState(() => _autoUpdate = value ?? !_autoUpdate);
                    GStorage.putSetting(SettingsKeys.autoUpdate, _autoUpdate);
                  },
                ),
              ],
            ),
            // Visible only when a newer release has been confirmed; stays
            // hidden on every failure path and on an up-to-date launch
            // (1.x UpdateBadge semantics).
            if (UpdateChecker.instance.hasUpdate)
              SettingsSection(
                title: const Text('发现新版本'),
                tiles: [
                  SettingsTile(
                    leading: Icons.rocket_launch_rounded,
                    title: Text(
                      '发现新版本 ${UpdateChecker.instance.latestVersion}',
                    ),
                    description: const Text('点击前往 GitHub 发布页（不自动下载）'),
                    onPressed: (context) => _openReleasePage(
                        UpdateChecker.instance.releaseUrl),
                  ),
                ],
              ),
          ],
        ),
      );
}
