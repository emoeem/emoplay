import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/constants.dart';

/// Update settings.
///
/// EmoPlay M1: the Kazumi GitHub-release auto-updater was removed with the
/// bangumi API layer (docs/STRIP-LIST.md §2); the update-check endpoint will
/// be re-introduced for the EmoPlay repository in M8. The toggle persists so
/// the setting survives that change.
class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  bool _autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);

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
                  description: const Text('当前版本 $appVersion（更新源在后续版本接入）'),
                  initialValue: _autoUpdate,
                  onToggle: (value) {
                    setState(() => _autoUpdate = value ?? !_autoUpdate);
                    GStorage.putSetting(SettingsKeys.autoUpdate, _autoUpdate);
                  },
                ),
              ],
            ),
          ],
        ),
      );
}
