// 设置中心「常规」分类页 (SPEC §6 category 1)：启动页、resumeOnReopen、
// 库扫描参数 maxDepth/skipHidden、更新检查。
//
// 启动页沿用界面设置里的 defaultStartupPage 键（GStorage，两处共享同一
// 存储）；resumeOnReopen / libraryMaxDepth / librarySkipHidden 是
// settings.json behavior 段（1.x AppSettings 字段），改动同步到
// LibraryStore.setScanOptions 让下一次扫描立即生效。
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
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
  static const _exitBehaviorTitles = ['退出 EmoPlay', '最小化至托盘', '每次都询问'];
  late int _exitBehavior =
      GStorage.getSetting(SettingsKeys.exitBehavior)
          .clamp(0, _exitBehaviorTitles.length - 1);

  static const Map<String, String> _defaultPageMap = {
    '/tab/home/': '首页',
    '/tab/library/': '媒体库',
    '/tab/player/': '播放',
    '/tab/plugins/': '插件',
    '/tab/settings/': '设置',
  };

  EmoPlaySettings get _settings => MediaStores.instance.settings;

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
      EmoDialog.showToast(message: '设置保存失败，请检查磁盘');
    }
    // 下一次扫描立即采用新参数（1.x main.cpp 的 setScanOptions 时机）。
    MediaStores.instance.library.setScanOptions(ScanOptions(
      maxDepth: _libraryMaxDepth,
      skipHidden: _librarySkipHidden,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('常规'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('启动'),
            tiles: [
              SettingsDropdownTile<String>(
                leading: Icons.home_rounded,
                title: const Text('启动页'),
                description: const Text('应用开启时的默认页面'),
                value: _defaultPage,
                options: _defaultPageMap,
                fallbackLabel: '首页',
                onChanged: (value) {
                  GStorage.putSetting(SettingsKeys.defaultStartupPage, value);
                  setState(() => _defaultPage = value);
                },
              ),
              SettingsTile.switchTile(
                leading: Icons.history_rounded,
                title: const Text('继续播放'),
                description:
                    const Text('打开看过的文件时从上次位置继续（关闭则从头播放）'),
                initialValue: _resumeOnReopen,
                onToggle: (value) {
                  setState(() => _resumeOnReopen = value ?? !_resumeOnReopen);
                  _persistBehavior();
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('媒体库扫描'),
            tiles: [
              SettingsSliderTile(
                leading: Icons.folder_copy_outlined,
                title: const Text('扫描深度'),
                description: const Text('媒体根目录之下允许下钻的目录层数（0 = 不限）'),
                value: _libraryMaxDepth.toDouble(),
                min: 0,
                max: 8,
                divisions: 9,
                valueLabel: _libraryMaxDepth == 0 ? '不限' : '$_libraryMaxDepth 层',
                onChanged: (value) {
                  setState(() => _libraryMaxDepth = value.round());
                  _persistBehavior();
                },
              ),
              SettingsTile.switchTile(
                leading: Icons.visibility_off_outlined,
                title: const Text('跳过隐藏文件'),
                description: const Text('扫描时不进入隐藏目录、不收录隐藏文件'),
                initialValue: _librarySkipHidden,
                onToggle: (value) {
                  setState(() => _librarySkipHidden = value ?? !_librarySkipHidden);
                  _persistBehavior();
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('更新'),
            tiles: [
              SettingsTile(
                leading: Icons.update_rounded,
                title: const Text('更新检查'),
                description: const Text('启动时检查应用更新'),
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
              title: const Text('窗口行为'),
              tiles: [
                SettingsDropdownTile<int>(
                  leading: Icons.exit_to_app_rounded,
                  title: const Text('关闭窗口时'),
                  description: const Text('设置点击窗口关闭按钮后的行为'),
                  value: _exitBehavior.clamp(0, _exitBehaviorTitles.length - 1),
                  options: {
                    for (var i = 0; i < _exitBehaviorTitles.length; i++)
                      i: _exitBehaviorTitles[i],
                  },
                  onChanged: (value) {
                    setState(() => _exitBehavior = value);
                    GStorage.putSetting(SettingsKeys.exitBehavior, value);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
