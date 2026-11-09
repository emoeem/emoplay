import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/about/about_module.dart';
import 'package:emoplay/pages/logs/logs_page.dart';
import 'package:emoplay/pages/settings/decoder_settings.dart';
import 'package:emoplay/pages/settings/displaymode_settings.dart';
import 'package:emoplay/pages/settings/interface_settings.dart';
import 'package:emoplay/pages/settings/keyboard_settings.dart';
import 'package:emoplay/pages/settings/player_settings.dart';
import 'package:emoplay/pages/settings/renderer_settings.dart';
import 'package:emoplay/pages/settings/settings_page.dart';
import 'package:emoplay/pages/settings/storage_settings.dart';
import 'package:emoplay/pages/settings/super_resolution_settings.dart';
import 'package:emoplay/pages/settings/theme_settings_page.dart';
import 'package:emoplay/pages/settings/update_settings.dart';
import 'package:emoplay/utils/constants.dart';

final settingsModule = createModule(
  path: '/settings',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => SettingsPage(location: state.uri.path),
      children: (sub) {
        sub
          ..route('/', child: (context, state) => const SettingsIndexPage())
          ..route(
            '/update',
            child: (context, state) => const UpdateSettingsPage(),
          )
          ..route('/storage',
              child: (context, state) => const StorageSettingsPage())
          ..route('/storage/logs', child: (context, state) => const LogsPage())
          ..route('/theme',
              child: (context, state) => const ThemeSettingsPage())
          ..route(
            '/theme/display',
            child: (context, state) => const SetDisplayMode(),
          )
          ..route(
            '/keyboard',
            child: (context, state) => const KeyboardSettingsPage(),
          )
          ..route('/player',
              child: (context, state) => const PlayerSettingsPage())
          ..route(
            '/player/decoder',
            child: (context, state) => const DecoderSettings(),
          )
          ..route(
            '/player/renderer',
            child: (context, state) => const RendererSettings(),
          )
          ..route(
            '/interface',
            child: (context, state) => const InterfaceSettingsPage(),
          )
          ..route(
            '/player/super',
            child: (context, state) => const SuperResolutionSettings(),
          )
          ..module(aboutModule);
      },
    );
    // Root route: the license browser must cover the settings shell.
    c.route(
      '/about/license',
      child: (context, state) => LicensePage(
        applicationName: appName,
        applicationVersion: appVersion,
        applicationLegalese: 'EmoPlay · GNU General Public License v3.0',
      ),
    );
  },
);
