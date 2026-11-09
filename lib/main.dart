import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:emoplay/app_module.dart';
import 'package:emoplay/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:emoplay/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:emoplay/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:emoplay/utils/device.dart';
import 'package:emoplay/services/platform/desktop_window_config.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/navigation.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // JSON data layer (library/history/thumbnails/settings, docs/SPEC.md §7):
  // built before runApp so pages read a fully-initialized MediaStores.
  // Failure leaves it unready (pages surface their empty states) instead of
  // blocking startup — unlike the Hive bootstrap, no single JSON store is
  // required to render the shell.
  try {
    await MediaStores.init();
  } catch (e) {
    EmoLogger().e('MediaStores initialization failed', error: e);
  }
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [EmoDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );

  // P9 update check: one background GET of the GitHub releases API per
  // launch (mpv-emo src/main.cpp:315-321 semantics — delayed so it never
  // competes with startup; the result is only ever reported, never
  // downloaded or installed, and every failure stays silent). Gated on the
  // settings-center toggle (Kazumi SettingsKeys.autoUpdate, default on).
  Timer(const Duration(seconds: 3), () {
    if (!GStorage.getSetting(SettingsKeys.autoUpdate)) return;
    UpdateChecker.instance.check();
  });
}
