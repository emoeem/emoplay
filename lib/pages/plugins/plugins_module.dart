import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/plugins/plugins_page.dart';

final pluginsModule = createModule(
  path: '/plugins',
  register: (c) {
    c.route('/', child: (context, state) => const PluginsPage());
  },
);
