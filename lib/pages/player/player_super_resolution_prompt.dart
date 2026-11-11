import 'dart:io';

import 'package:flutter/material.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_super_resolution.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/services/storage/storage.dart';

/// Super-resolution confirmation prompts extracted from player_item.dart
/// (M3-T0 god-class split; pure move, no behavior change).
///
/// [mode] resolution entry point used by the player panel callback: guards
/// the MediaCodec renderer limitation on Android and asks once before the
/// quality preset, then applies the shader via [PlayerController.setShader].
/// [isMounted] replaces the original state `mounted` checks.
Future<void> resolveSuperResolutionChange({
  required PlayerController playerController,
  required SuperResolutionMode mode,
  required bool Function() isMounted,
}) async {
  if (!isMounted()) return;

  // The mediacodec_embed renderer cannot apply super-resolution shaders.
  if (Platform.isAndroid && mode != SuperResolutionMode.off) {
    final String androidVideoRenderer =
        GStorage.getSetting(SettingsKeys.androidVideoRenderer);

    if (androidVideoRenderer == 'mediacodec_embed') {
      await EmoDialog.show(builder: (context) {
        return AlertDialog(
          title: const Text('兼容性提示'),
          content: const Text('MediaCodec 渲染器不支持超分辨率功能。\n\n'
              '如需使用超分辨率，请在播放设置中将视频渲染器切换为 gpu 或 gpu-next。'),
          actions: [
            TextButton(
              onPressed: () {
                EmoDialog.dismiss(context: context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      });
      return;
    }
  }

  final bool requiresPerformanceWarning = mode == SuperResolutionMode.quality;
  final bool warningDisabled = GStorage.getSetting(
    SettingsKeys.disableSuperResolutionWarning,
  );

  if (requiresPerformanceWarning && !warningDisabled) {
    bool confirmed = false;

    await EmoDialog.show(builder: (context) {
      bool dontAskAgain = false;

      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('性能提示'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: dontAskAgain,
                    onChanged: (value) =>
                        setState(() => dontAskAgain = value ?? false),
                  ),
                  const Text('下次不再询问'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (dontAskAgain) {
                  await GStorage.putSetting(
                    SettingsKeys.disableSuperResolutionWarning,
                    true,
                  );
                }
                if (!context.mounted) return;
                EmoDialog.dismiss(context: context);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                confirmed = true;
                if (dontAskAgain) {
                  await GStorage.putSetting(
                    SettingsKeys.disableSuperResolutionWarning,
                    true,
                  );
                }
                if (!context.mounted) return;
                EmoDialog.dismiss(context: context);
              },
              child: const Text('确认'),
            ),
          ],
        );
      });
    });

    if (confirmed && isMounted()) {
      playerController.setShader(mode);
    }
  } else {
    playerController.setShader(mode);
  }
}
