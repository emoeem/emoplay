import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/appbar/sys_app_bar.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/pages/settings/general_settings.dart';
import 'package:emoplay/utils/constants.dart';

class _SettingsCategory {
  const _SettingsCategory({
    required this.label,
    required this.description,
    required this.icon,
    required this.path,
  });

  final String label;
  final String description;
  final IconData icon;
  final String path;
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.categories});

  final String title;
  final List<_SettingsCategory> categories;
}

// SPEC §6 设置分类法：11 个分类（常规/播放/视频与画质/音频/mpv 配置/
// 着色器管理/外观/快捷键/存储与缓存/诊断/关于），组件与双面板沿用
// Kazumi SettingsList 体系（compact 断点 600×480）。
const List<_SettingsGroup> _settingsGroups = [
  _SettingsGroup(
    title: '常规',
    categories: [
      _SettingsCategory(
        label: '常规',
        description: '启动页、继续播放与库扫描',
        icon: Icons.tune_rounded,
        path: '/settings/general',
      ),
    ],
  ),
  _SettingsGroup(
    title: '播放',
    categories: [
      _SettingsCategory(
        label: '播放',
        description: '解码、渲染与播放行为',
        icon: Icons.display_settings_rounded,
        path: '/settings/player',
      ),
      _SettingsCategory(
        label: '视频与画质',
        description: '画质档位、Anime4K、插帧与 ICC',
        icon: Icons.auto_awesome_rounded,
        path: '/settings/quality',
      ),
      _SettingsCategory(
        label: '音频',
        description: '均衡器预设与 10 段增益',
        icon: Icons.equalizer_rounded,
        path: '/settings/audio',
      ),
      _SettingsCategory(
        label: '快捷键',
        description: '播放器按键映射',
        icon: Icons.keyboard_rounded,
        path: '/settings/keyboard',
      ),
    ],
  ),
  _SettingsGroup(
    title: 'mpv',
    categories: [
      _SettingsCategory(
        label: 'mpv 配置',
        description: '导入向导、决策重置与选项审计',
        icon: Icons.integration_instructions_outlined,
        path: '/settings/mpv',
      ),
      _SettingsCategory(
        label: '着色器管理',
        description: '着色器目录、GLSL 勾选与缓存',
        icon: Icons.auto_fix_high_rounded,
        path: '/settings/shaders',
      ),
    ],
  ),
  _SettingsGroup(
    title: '应用',
    categories: [
      _SettingsCategory(
        label: '外观',
        description: '主题、配色与显示',
        icon: Icons.palette_rounded,
        path: '/settings/theme',
      ),
      _SettingsCategory(
        label: '存储与缓存',
        description: '数据目录、缓存与日志',
        icon: Icons.storage_rounded,
        path: '/settings/storage',
      ),
      // M4-T7（2026-11-12 用户改向纳入）：在线元数据联网兜底的总开关与
      // TMDB API key。SPEC §6 的 11 分类之外的增补项。
      _SettingsCategory(
        label: '在线元数据',
        description: 'TMDB 联网补全与 API key',
        icon: Icons.cloud_sync_outlined,
        path: '/settings/online',
      ),
      _SettingsCategory(
        label: '诊断',
        description: '版本、渲染后端与目录',
        icon: Icons.bug_report_outlined,
        path: '/settings/diagnostics',
      ),
      _SettingsCategory(
        label: '关于',
        description: '版本与开源信息',
        icon: Icons.info_outline_rounded,
        path: '/settings/about',
      ),
    ],
  ),
];

String _normalizePath(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

bool _isWithinPath(String location, String path) =>
    location == path || location.startsWith('$path/');

String _categoryPath(String location) {
  if (location == '/settings') {
    return '/settings/general';
  }
  for (final group in _settingsGroups) {
    for (final category in group.categories) {
      if (_isWithinPath(location, category.path)) {
        return category.path;
      }
    }
  }
  return location;
}

class _SettingsCategorySelected extends Notification {
  const _SettingsCategorySelected(this.path);

  final String path;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.location});

  final String location;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _outletKey = GlobalKey<RouterOutletState>();
  Object? _categoryNavigation;
  late String _location = _normalizePath(widget.location);

  String get _selectedCategoryPath => _categoryPath(_location);
  bool get _isSecondaryRoute =>
      _location != '/settings' && _location != _selectedCategoryPath;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _categoryNavigation = null;
      _location = _normalizePath(widget.location);
    }
  }

  void _replaceCategory(String path) {
    final outlet = _outletKey.currentState!;
    // Nested pushes leave _location unchanged, so check the stack as well.
    if (!outlet.canPop &&
        !_isSecondaryRoute &&
        _selectedCategoryPath == path) {
      return;
    }
    _categoryNavigation = null;
    outlet.navigate(path);
    setState(() => _location = path);
  }

  Future<void> _pushCategory(String path) async {
    if (_categoryNavigation != null) return;
    final navigation = Object();
    final previousLocation = _location;
    _categoryNavigation = navigation;
    setState(() => _location = path);
    await _outletKey.currentState!.push<void>(path);
    // Ignore completions from history replaced by a rail selection.
    if (!mounted || _categoryNavigation != navigation) return;
    setState(() {
      _categoryNavigation = null;
      _location = previousLocation;
    });
  }

  void _goBack() {
    if (_outletKey.currentState?.maybePop() ?? false) return;
    _exitSettings();
  }

  void _exitSettings() {
    if (!context.maybePop()) context.navigate('/tab/home');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > LayoutBreakpoint.compact['width']!;
      return NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _goBack(),
        child: Scaffold(
          appBar: wide
              ? SysAppBar(
                  title: const Text('设置'),
                  leading: BackButton(onPressed: _exitSettings),
                )
              : null,
          body: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Keep the outlet at the same tree position on resize.
                SizedBox(
                  width: wide ? 280 : 0,
                  child: Offstage(
                    offstage: !wide,
                    child: _SettingsMenu(
                      wide: true,
                      selectedPath: _selectedCategoryPath,
                      onSelect: _replaceCategory,
                    ),
                  ),
                ),
                Expanded(
                  child: SettingsPaneScope(
                    embedded: wide,
                    showBackButton: _isSecondaryRoute,
                    onBack: _goBack,
                    child: NotificationListener<_SettingsCategorySelected>(
                      onNotification: (notification) {
                        _pushCategory(notification.path);
                        return true;
                      },
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          pageTransitionsTheme: settingsPageTransitionsTheme,
                        ),
                        child: RouterOutlet(key: _outletKey),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class SettingsIndexPage extends StatelessWidget {
  const SettingsIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (SettingsPaneScope.of(context)?.embedded ?? false) {
      return const GeneralSettingsPage();
    }
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('设置'),
        leading: BackButton(onPressed: () {
          if (!context.maybePop()) context.navigate('/tab/home');
        }),
      ),
      body: _SettingsMenu(
        wide: false,
        onSelect: (path) => _SettingsCategorySelected(path).dispatch(context),
      ),
    );
  }
}

/// 设置 Tab 的入口页.
///
/// The settings route tree stays mounted at the top-level `/settings` path so
/// deep links keep working; this tab entry pushes the corresponding category
/// onto the root stack, mirroring Kazumi's behavior.
class SettingsTabHome extends StatelessWidget {
  const SettingsTabHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: false,
      ),
      body: _SettingsMenu(
        wide: false,
        onSelect: (path) => context.pushNamed(path),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.wide,
    this.selectedPath,
    required this.onSelect,
  });

  final bool wide;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: wide
            ? const EdgeInsets.fromLTRB(4, 0, 0, 12)
            : const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final group in _settingsGroups)
            if (wide) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
                child: SectionHeader(title: Text(group.title)),
              ),
              for (final category in group.categories)
                _RailDestination(
                  category: category,
                  selected: selectedPath == category.path,
                  onTap: () => onSelect(category.path),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ContentSection.group(
                  title: group.title,
                  children: [
                    for (final category in group.categories)
                      SettingsCategoryTile(
                        icon: category.icon,
                        title: category.label,
                        description: category.description,
                        onTap: () => onSelect(category.path),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(category.icon, size: 24, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.label,
                    style: textTheme.labelLarge?.copyWith(color: foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
