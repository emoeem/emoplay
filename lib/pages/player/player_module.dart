import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_page.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';

final playerModule = createModule(
  path: '/player',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s
        ..add<PlayerController>(PlayerController.new),
      child: (context, state) => PlayerPage(
        playerController: context.read<PlayerController>(),
        playerPageController: inject<PlayerPageController>(),
      ),
    );
  },
);
