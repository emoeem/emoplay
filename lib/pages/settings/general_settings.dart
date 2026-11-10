// 设置中心「常规」分类页 (SPEC §6 category 1)：启动页、resumeOnReopen、
// 库扫描参数 maxDepth/skipHidden、更新检查、「恢复默认设置」操作项。
//
// 启动页沿用界面设置里的 defaultStartupPage 键（GStorage，两处共享同一
// 存储）；resumeOnReopen / libraryMaxDepth / librarySkipHidden 是
// settings.json behavior 段（1.x AppSettings 字段），改动同步到
// LibraryStore.setScanOptions 让下一次扫描立即生效。
//
// 「恢复默认设置」（施工件 B）是 1.x SettingsService::restoreDefaults 的
// UI 槽位，行为以 test_settings_service.cpp 的 restoreDefaultsKeepsMedia
// AndHistory 为规格：quality/behavior/music 三分区回默认，媒体库、观看
// 历史与 mpv 配置导入决策不动（导入决策的重置在 mpv 配置页有自己的瓦
// 片），确认走 EmoDialog 危险样式对话框；恢复后相关设置页即时刷新——
// 靠把新值推进各会话控制器（reloadFromSettings，它们的镜像只在自家
// setter 里重同步）+ setState 刷新本页。
//
// R7 i18n：第三个迁移到 AppLocalizations 的设置页（沿 audio_settings 先
// 例：页签名直接取 tabHome 等既有键，语义单位不进 arb）。
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/settings/emoplay_settings.dart';
import 'package:emoplay/utils/device.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  late String _defaultPage =
      GStorage.getSetting(SettingsKeys.defaultStartupPage);
  late bool _resumeOnReopen;
  late int _libraryMaxDepth;
  late bool _librarySkipHidden;
  // 原「界面设置」的窗口行为键（GStorage）。
  late int _exitBehavior =
      GStorage.getSetting(SettingsKeys.exitBehavior)
          .clamp(0, 2);

  EmoPlaySettings get _settings => MediaStores.instance.settings;

  // 启动页下拉的选项表：键 = defaultStartupPage 的持久化路由，值 = 当前
  // 语言的显示名（menuTabLabels 同款约定）。
  Map<String, String> _defaultPageOptions(AppLocalizations l10n) =>
      <String, String>{
        '/tab/home/': l10n.tabHome,
        '/tab/library/': l10n.tabLibrary,
        '/tab/player/': l10n.tabPlayer,
        '/tab/plugins/': l10n.tabPlugins,
        '/tab/settings/': l10n.tabSettings,
      };

  // 关闭窗口行为下拉的选项表：键 = SettingsKeys.exitBehavior 的持久化值。
  Map<int, String> _exitBehaviorOptions(AppLocalizations l10n) =>
      <int, String>{
        0: l10n.exitBehaviorExit,
        1: l10n.exitBehaviorTray,
        2: l10n.exitBehaviorAsk,
      };

  @override
  void initState() {
    super.initState();
    _resumeOnReopen = _settings.resumeOnReopen;
    _libraryMaxDepth = _settings.libraryMaxDepth;
    _librarySkipHidden = _settings.librarySkipHidden;
  }

  void _persistBehavior() {
    _settings.resumeOnReopen = _resumeOnReopen;
    _settings.libraryMaxDepth = _libraryMaxDepth;
    _settings.librarySkipHidden = _librarySkipHidden;
    if (!_settings.save()) {
      EmoDialog.showToast(
          context: context,
          message: AppLocalizations.of(context).settingsSaveFailed);
    }
    // 下一次扫描立即采用新参数（1.x main.cpp 的 setScanOptions 时机）。
    MediaStores.instance.library.setScanOptions(ScanOptions(
      maxDepth: _libraryMaxDepth,
      skipHidden: _librarySkipHidden,
    ));
  }

  // 「恢复默认设置」入口：EmoDialog 危险样式确认后执行（1.x 恢复默认的
  // 语义见文件头）。
  Future<void> _confirmRestoreDefaults() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await EmoDialog.show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(
            Icons.settings_backup_restore_rounded,
            color: colors.error,
          ),
          title: Text(l10n.restoreDefaultsDialogTitle),
          content: Text(l10n.restoreDefaultsDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.restoreDefaultsConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _applyRestoreDefaults();
  }

  Future<void> _applyRestoreDefaults() async {
    final l10n = AppLocalizations.of(context);
    final stores = MediaStores.instance;
    final settings = stores.settings;
    // quality/behavior/music 三分区回默认；媒体库、历史与导入决策不动
    // （test_settings_service.cpp restoreDefaultsKeepsMediaAndHistory）。
    settings.restoreDefaults();
    if (!settings.save()) {
      // 写失败照常上报：内存态保持权威（与 _persistBehavior 同契约）。
      EmoDialog.showToast(context: context, message: l10n.settingsSaveFailed);
    }
    // 把复位值推进会话控制器：画质/插值/ICC 的 MobX 镜像与均衡器的
    // ChangeNotifier 状态只在自家 setter 里重同步，不推进则画质页与音频
    // 页在重启前一直显示旧值（恢复后相关设置页即时刷新）。
    stores.quality.quality.reloadFromSettings();
    stores.quality.interpolation.reloadFromSettings();
    stores.quality.icc.reloadFromSettings();
    await stores.music.reloadFromSettings();
    // 下一次扫描采用复位后的扫描参数（本页 _persistBehavior 的契约）。
    stores.library.setScanOptions(ScanOptions(
      maxDepth: settings.libraryMaxDepth,
      skipHidden: settings.librarySkipHidden,
    ));
    if (!mounted) {
      return;
    }
    setState(() {
      _resumeOnReopen = settings.resumeOnReopen;
      _libraryMaxDepth = settings.libraryMaxDepth;
      _librarySkipHidden = settings.librarySkipHidden;
    });
    EmoDialog.showToast(context: context, message: l10n.restoreDefaultsDone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exitBehaviorOptions = _exitBehaviorOptions(l10n);
    return SettingsDetailScaffold(
      title: Text(l10n.generalTitle),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(l10n.generalStartupSection),
            tiles: [
              SettingsDropdownTile<String>(
                leading: Icons.home_rounded,
                title: Text(l10n.startupPageTitle),
                description: Text(l10n.startupPageDescription),
                value: _defaultPage,
                options: _defaultPageOptions(l10n),
                fallbackLabel: l10n.tabHome,
                onChanged: (value) {
                  GStorage.putSetting(SettingsKeys.defaultStartupPage, value);
                  setState(() => _defaultPage = value);
                },
              ),
              SettingsTile.switchTile(
                leading: Icons.history_rounded,
                title: Text(l10n.resumeTitle),
                description: Text(l10n.resumeDescription),
                initialValue: _resumeOnReopen,
                onToggle: (value) {
                  setState(() => _resumeOnReopen = value ?? !_resumeOnReopen);
                  _persistBehavior();
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.libraryScanSection),
            tiles: [
              SettingsSliderTile(
                leading: Icons.folder_copy_outlined,
                title: Text(l10n.scanDepthTitle),
                description: Text(l10n.scanDepthDescription),
                value: _libraryMaxDepth.toDouble(),
                min: 0,
                max: 8,
                divisions: 9,
                valueLabel: _libraryMaxDepth == 0
                    ? l10n.scanDepthUnlimited
                    : l10n.scanDepthLayers(_libraryMaxDepth),
                onChanged: (value) {
                  setState(() => _libraryMaxDepth = value.round());
                  _persistBehavior();
                },
              ),
              SettingsTile.switchTile(
                leading: Icons.visibility_off_outlined,
                title: Text(l10n.skipHiddenTitle),
                description: Text(l10n.skipHiddenDescription),
                initialValue: _librarySkipHidden,
                onToggle: (value) {
                  setState(() => _librarySkipHidden = value ?? !_librarySkipHidden);
                  _persistBehavior();
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.updateSection),
            tiles: [
              SettingsTile(
                leading: Icons.update_rounded,
                title: Text(l10n.updateCheckTitle),
                description: Text(l10n.updateCheckDescription),
                onPressed: (_) => context.pushNamed('/settings/update'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ),
            ],
          ),
          // 原「界面设置」的窗口行为段：SPEC §6 的 11 分类中没有独立界面
          // 分类，启动页与其余应用行为按归类合并进「常规」（Kazumi 现状
          // 兜底，键值不变：SettingsKeys.exitBehavior）。
          if (isDesktop())
            SettingsSection(
              title: Text(l10n.windowBehaviorSection),
              tiles: [
                SettingsDropdownTile<int>(
                  leading: Icons.exit_to_app_rounded,
                  title: Text(l10n.exitBehaviorTitle),
                  description: Text(l10n.exitBehaviorDescription),
                  value: _exitBehavior.clamp(0, exitBehaviorOptions.length - 1),
                  options: exitBehaviorOptions,
                  onChanged: (value) {
                    setState(() => _exitBehavior = value);
                    GStorage.putSetting(SettingsKeys.exitBehavior, value);
                  },
                ),
              ],
            ),
          // 1.x SettingsService::restoreDefaults 的 UI 槽位（施工件 B）：
          // 危险确认后 quality/behavior/music 三分区回默认，媒体库、历史
          // 与导入决策不动，相关设置页即时刷新（_applyRestoreDefaults）。
          SettingsSection(
            title: Text(l10n.generalRestoreSection),
            tiles: [
              SettingsTile(
                leading: Icons.settings_backup_restore_rounded,
                title: Text(l10n.restoreDefaultsTitle),
                description: Text(l10n.restoreDefaultsDescription),
                onPressed: (_) => _confirmRestoreDefaults(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
