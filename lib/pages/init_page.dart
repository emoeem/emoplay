import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/shaders/shader_asset_service.dart';
import 'package:emoplay/services/platform/windows_shortcut.dart';
import 'package:emoplay/services/platform/platform_environment_service.dart';
import 'package:emoplay/services/platform/app_exit.dart';

/// Startup page: runs pre-flight initialization, then hands over to the
/// startup tab (docs/SPEC.md §5).
class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    _loadShaders();

    await _checkRunningOnX11();
    await _showShortcutDialog();

    if (!mounted) {
      return;
    }
    context.navigate(GStorage.getSetting(SettingsKeys.defaultStartupPage));
  }

  Future<void> _loadShaders() async {
    try {
      final shaderAssetService = inject<ShaderAssetService>();
      await shaderAssetService.copyShadersToExternalDirectory();
    } catch (e) {
      EmoLogger().w('InitPage: failed to load shaders', error: e);
    }
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await EmoDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，EmoPlay在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用EmoPlay？'),
              actions: [
                TextButton(
                  onPressed: AppExit.quit,
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    EmoDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await EmoDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 EmoPlay 的快捷方式？'),
        actions: [
          TextButton(
            onPressed: () => EmoDialog.dismiss(popWith: false),
            child: Text('暂不创建',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => EmoDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      EmoDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
