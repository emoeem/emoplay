import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/models/playback_args.dart';
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
      child: (context, state) {
        // Kazumi hands playback context over through the route instead of
        // pre-filling a shared controller (kazumi/lib/pages/video/
        // video_module.dart): the child checks the sealed args type and the
        // page plays them on entry. EmoPlay's only concrete kind is a local
        // media file; [startAt] drives the deferred resume seek (SPEC §4.4).
        final args = state.arguments;
        return PlayerPage(
          playerController: context.read<PlayerController>(),
          playerPageController: inject<PlayerPageController>(),
          initialArgs: args is LocalFilePlaybackArgs ? args : null,
        );
      },
    );
  },
);
