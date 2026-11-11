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
      child: (context, state) {
        // Kazumi hands playback context over through the route instead of
        // pre-filling a shared controller (kazumi/lib/pages/video/
        // video_module.dart): the child checks the sealed args type and the
        // page plays them on entry. EmoPlay's only concrete kind is a local
        // media file; [startAt] drives the deferred resume seek (SPEC §4.4).
        //
        // M5-T3: PlayerController moved to the tab singletons
        // (index_module.dart) so playback survives tab switches for the mini
        // bar; both controllers resolve through the tab injector here.
        final args = state.arguments;
        return PlayerPage(
          playerController: inject<PlayerController>(),
          playerPageController: inject<PlayerPageController>(),
          initialArgs: args is LocalFilePlaybackArgs ? args : null,
        );
      },
    );
  },
);
