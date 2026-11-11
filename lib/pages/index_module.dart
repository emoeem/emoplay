import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/bean/widget/error_widget.dart';
import 'package:emoplay/pages/home/home_module.dart';
import 'package:emoplay/pages/index_page.dart';
import 'package:emoplay/pages/init_page.dart';
import 'package:emoplay/pages/library/library_module.dart';
import 'package:emoplay/pages/player/player_module.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/plugins/plugins_module.dart';
import 'package:emoplay/pages/settings/settings_module.dart';
import 'package:emoplay/pages/settings/settings_page.dart';
import 'package:emoplay/services/storage/storage.dart';

final _tabTransition = CustomTransition(
  duration: const Duration(milliseconds: 70),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

/// The five EmoPlay tabs (docs/SPEC.md §5): 首页 / 媒体库 / 播放 / 插件 / 设置.
final tabModule = createModule(
  path: '/tab',
  register: (c) {
    c
      // Tab state survives tab switches, but is released with the whole shell.
      ..addSingleton<PlayerPageController>(PlayerPageController.new)
      // M5-T3 迷你条（docs/EMOPLAY-3.0-ROADMAP.md §五）: the player
      // controller joins the tab singletons. It used to be a player-route
      // `provide:` bind, which flutter_modular disposes when the outlet
      // leaves /tab/player/ — switching tabs stopped playback, leaving
      // nothing for the non-player-page mini bar to show. As a tab singleton
      // playback keeps running across tab switches (background audio; the
      // mini bar controls it, _handleBack still stops explicitly). Same
      // release contract as PlayerPageController: gone with the whole shell.
      ..addSingleton<PlayerController>(PlayerController.new)
      ..route(
        '/',
        child: (context, state) => IndexPage(location: state.uri.path),
        transition: _tabTransition,
        children: (sub) {
          sub
            ..route(
              '/',
              guards: [
                (state) => GStorage.getSetting(SettingsKeys.defaultStartupPage),
              ],
              child: (context, state) => const SizedBox.shrink(),
            )
            ..module(homeModule)
            ..module(libraryModule)
            ..module(playerModule)
            ..module(pluginsModule)
            ..route(
              '/settings',
              child: (context, state) => const SettingsTabHome(),
            );
        },
      );
  },
);

final indexModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const InitPage(),
        transition: TransitionType.none,
      )
      ..route(
        '/error',
        child: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('EmoPlay')),
          body: const GeneralErrorWidget(
            title: '初始化失败',
            errMsg: '请重新启动应用后再试。',
          ),
        ),
      )
      ..module(tabModule)
      ..module(settingsModule);
  },
);
