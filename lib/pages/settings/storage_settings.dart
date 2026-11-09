import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path_provider/path_provider.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/services/logging/logger.dart';

/// Storage diagnostics.
///
/// EmoPlay keeps media data in JSON stores under the application support
/// directory (docs/SPEC.md §7); Kazumi's image cache management was removed
/// with the bangumi image pipeline.
class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late Future<int> _cacheSize = _sizeInBytes();
  bool _clearing = false;

  Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/emoplay_cache')
      ..create(recursive: true);
  }

  Future<int> _sizeInBytes() async {
    final dir = await _cacheDir();
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  void _message(String message) {
    EmoDialog.showToast(context: context, message: message);
  }

  Future<void> _confirmClear() async {
    if (_clearing) return;
    final confirmed = await EmoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded),
        title: const Text('清除缓存？'),
        content: const Text('临时缓存会在下次使用时重建。视频、记录和设置不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      EmoLogger().i('StorageSettings: cache cleared');
      if (!mounted) return;
      _message('缓存已清除');
      _refreshSize();
    } catch (_) {
      if (mounted) _message('清除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _refreshSize() => setState(() => _cacheSize = _sizeInBytes());

  String _cacheDescription(AsyncSnapshot<int> snapshot) {
    if (_clearing) return '正在清除…';
    if (snapshot.connectionState != ConnectionState.done) return '正在统计…';
    if (snapshot.hasError) return '统计失败';
    return '${(snapshot.requireData / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('存储与日志'),
        body: FutureBuilder<int>(
          future: _cacheSize,
          builder: (context, snapshot) => SettingsList(
            sections: [
              SettingsSection(
                title: const Text('数据目录'),
                tiles: [
                  // SPEC §6 category 9（数据目录、缓存大小、清理按钮）：所有
                  // JSON 存储 / 插件状态 / 缩略图缓存都在应用支持目录下。
                  FutureBuilder<Directory>(
                    future: getApplicationSupportDirectory(),
                    builder: (context, support) => SettingsTile(
                      leading: Icons.folder_rounded,
                      title: const Text('数据目录'),
                      description: Text(support.hasData
                          ? support.requireData.path
                          : '解析中…'),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('缓存'),
                tiles: [
                  SettingsTile(
                    leading: Icons.image_outlined,
                    title: const Text('清除临时缓存'),
                    description: Text(_cacheDescription(snapshot)),
                    enabled: snapshot.connectionState == ConnectionState.done &&
                        !_clearing,
                    onPressed: (_) => _confirmClear(),
                    trailing:
                        snapshot.connectionState == ConnectionState.done &&
                                snapshot.hasError &&
                                !_clearing
                            ? IconButton(
                                tooltip: '重新统计',
                                onPressed: _refreshSize,
                                icon: const Icon(Icons.refresh_rounded),
                              )
                            : const Icon(Icons.cleaning_services_rounded),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('诊断'),
                tiles: [
                  SettingsTile(
                    leading: Icons.receipt_long_rounded,
                    title: const Text('错误日志'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onPressed: (_) =>
                        context.pushNamed('/settings/storage/logs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
