// 设置中心「着色器管理」分类页 (SPEC §6 category 6)：着色器目录、已装
// GLSL 列表勾选、缓存清理。
//
// 勾选走 M6 QualityController.setShaderMounted（持久化 manualShaderList 并
// 对在播引擎重挂 glsl-shaders 链）；缓存清理针对 mpv 写路径重定向表
// （MpvImportRules.redirectTarget，单一事实源）指向的 shader_cache/ 与
// icc_cache/ 目录——只清缓存，绝不动用户的 mpv 目录（SPEC §4.2）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/compat/mpv_import_rules.dart';

class ShaderSettingsPage extends StatefulWidget {
  const ShaderSettingsPage({super.key});

  @override
  State<ShaderSettingsPage> createState() => _ShaderSettingsPageState();
}

class _ShaderSettingsPageState extends State<ShaderSettingsPage> {
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    // availableShaders 由引擎 attach 时的 startup() 扫描填充；设置页在无
    // 播放会话时也可能被打开，这里补一次目录扫描（幂等，M6 公开方法）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final quality = MediaStores.instance.quality.quality;
      if (quality.availableShaders.isEmpty) {
        quality.scanAvailableShaders();
      }
    });
  }

  String get _shaderCacheDir => MpvImportRules.redirectTarget(
      'gpu-shader-cache-dir', MediaStores.instance.quality.appDataDir);

  String get _iccCacheDir => MpvImportRules.redirectTarget(
      'icc-cache-dir', MediaStores.instance.quality.appDataDir);

  Future<void> _clearCaches() async {
    if (_clearing) return;
    final confirmed = await EmoDialog.show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded),
        title: const Text('清空着色器/ICC 缓存？'),
        content: Text('删除以下目录内容（随后按需重建）：\n$_shaderCacheDir\n$_iccCacheDir'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      for (final path in [_shaderCacheDir, _iccCacheDir]) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
        Directory(path).createSync(recursive: true);
      }
      if (mounted) {
        EmoDialog.showToast(context: context, message: '缓存已清除');
      }
    } catch (_) {
      if (mounted) {
        EmoDialog.showToast(context: context, message: '清除失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stores = MediaStores.instance.quality;
    return SettingsDetailScaffold(
      title: const Text('着色器管理'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('目录'),
            tiles: [
              SettingsTile(
                leading: Icons.folder_open_rounded,
                title: const Text('着色器目录'),
                description: Text(stores.shadersDir),
              ),
            ],
          ),
          Observer(
            builder: (_) {
              final quality = stores.quality;
              final available = quality.availableShaders;
              return SettingsSection(
                title: const Text('已装 GLSL（勾选即挂载）'),
                bottomInfo: Text(available.isEmpty
                    ? '目录中没有 .glsl 文件 — Anime4K 等着色器可经插件中心安装，'
                        '或把 GLSL 文件放进上面的目录'
                    : '勾选的着色器写入 manualShaderList，画质引擎开启时挂载到 glsl-shaders 链'),
                tiles: [
                  if (available.isEmpty)
                    SettingsTile(
                      leading: Icons.info_outline_rounded,
                      title: const Text('暂无已装着色器'),
                    ),
                  for (final relative in available)
                    SettingsTile.switchTile(
                      leading: Icons.auto_awesome_rounded,
                      title: Text(relative),
                      initialValue: quality.manualShaders
                          .contains(p.join(stores.shadersDir, relative)),
                      onToggle: (value) => quality.setShaderMounted(
                          relative, value ?? false),
                    ),
                ],
              );
            },
          ),
          SettingsSection(
            title: const Text('缓存'),
            tiles: [
              SettingsTile(
                leading: Icons.cleaning_services_rounded,
                title: const Text('清空着色器 / ICC 缓存'),
                description: Text(_clearing
                    ? '正在清除…'
                    : 'shader_cache 与 icc_cache（mpv 写路径重定向目录）'),
                onPressed: _clearing ? null : (_) => _clearCaches(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
