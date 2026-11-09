import 'dart:io';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/services/player/external_player.dart';

/// Hands the current media URL to an external player, when the platform
/// allows launching one. EmoPlay plays local files, so no referer handling.
class ExternalPlaybackLauncher {
  final String Function() videoUrl;

  ExternalPlaybackLauncher({
    required this.videoUrl,
  });

  Future<void> launch() async {
    final currentVideoUrl = videoUrl();
    if (Platform.isAndroid || Platform.isWindows) {
      if (await ExternalPlayer.launchUrlWithMime(
          currentVideoUrl, 'video/mp4')) {
        EmoDialog.showToast(
          message: '尝试唤起外部播放器',
        );
      } else {
        EmoDialog.showToast(
          message: '唤起外部播放器失败',
        );
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      if (await ExternalPlayer.launchUrl(currentVideoUrl)) {
        EmoDialog.showToast(
          message: '尝试唤起外部播放器',
        );
      } else {
        EmoDialog.showToast(
          message: '唤起外部播放器失败',
        );
      }
    } else if (Platform.isLinux) {
      final result =
          await ExternalPlayer.launchLinuxDesktopPlayer(currentVideoUrl);
      switch (result) {
        case LinuxExternalPlayerResult.launched:
          EmoDialog.showToast(message: '尝试唤起外部播放器');
        case LinuxExternalPlayerResult.cancelled:
          break;
        case LinuxExternalPlayerResult.unavailable:
          EmoDialog.showToast(message: '系统应用选择器不可用');
        case LinuxExternalPlayerResult.failed:
          EmoDialog.showToast(message: '唤起外部播放器失败');
      }
    } else {
      EmoDialog.showToast(
        message: '暂不支持该设备',
      );
    }
  }
}
