import 'package:flutter/services.dart';
import 'package:emoplay/services/logging/logger.dart';

enum LinuxExternalPlayerResult {
  launched,
  cancelled,
  unavailable,
  failed,
}

class ExternalPlayer {
  ExternalPlayer._();

  static const _platform = MethodChannel('com.emoplay.emoplay/intent');

  static Future<bool> launchUrlWithMime(String url, String mimeType) async {
    try {
      await _platform.invokeMethod(
          'openWithMime', <String, String>{'url': url, 'mimeType': mimeType});
      return true;
    } on PlatformException catch (e) {
      EmoLogger().e("ExternalPlayer: failed to open with mime", error: e);
      return false;
    }
  }

  static Future<bool> launchUrl(String url) async {
    try {
      await _platform.invokeMethod(
          'openWithMime', <String, String>{'url': url, 'mimeType': 'video/*'});
      return true;
    } on PlatformException catch (e) {
      EmoLogger().e("ExternalPlayer: failed to open url", error: e);
      return false;
    }
  }

  static Future<LinuxExternalPlayerResult> launchLinuxDesktopPlayer(
      String url) async {
    try {
      final result = await _platform.invokeMethod<String>(
        'openWithDesktopPlayer',
        <String, String>{'url': url},
      );
      return switch (result) {
        'launched' => LinuxExternalPlayerResult.launched,
        'cancelled' => LinuxExternalPlayerResult.cancelled,
        'unavailable' => LinuxExternalPlayerResult.unavailable,
        _ => LinuxExternalPlayerResult.failed,
      };
    } on PlatformException catch (e) {
      EmoLogger().e(
        "ExternalPlayer: failed to open Linux desktop player",
        error: e,
      );
      return LinuxExternalPlayerResult.failed;
    }
  }
}
