// M5-T3 常驻迷你条验收（docs/EMOPLAY-3.0-ROADMAP.md §五 M5-T3：
// 「新增 mini bar 测试 ≥2（可见性条件、点击回播放页）」）。
//
// 挂真实 MusicMiniBar 于一个最小 modular 壳（与 pages/menu/menu.dart 竖屏
// 挂载同构：壳 route child + RouterOutlet + bottomNavigationBar），控制器
// 用真身（PlayerPageController/PlayerController 都是 tab 单例，构造无引擎
// 依赖；播放态直接写 @observable 字段模拟，playOrPause 无引擎时是安全
// 空操作——player_controller.dart pause()/play() 的 null-guard）。
//
// 导航动词用缺省路径：MusicMiniBar 无 onOpenPlayer 时走
// context.navigate('/tab/player/')（music_mini_bar.dart 文件头），点击后根
// delegate 把壳换到 /tab/player/——这正是「点击回播放页」的独立可验证语义；
// 生产挂载传 shell 的 _selectDestination（同一条 tab 切换路径，另行真机
// 冒烟覆盖）。
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' show runInAction;

import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/music_mini_bar.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/services/player/audio_controller.dart';
import 'package:emoplay/services/shaders/shader_asset_service.dart';

void main() {
  testWidgets('miniBarVisibilityConditions', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump(); // build seed page
    await tester.pumpAndSettle(); // post-frame navigate -> shell at /tab/home/

    // Idle (currentIndex == -1): nothing to show.
    expect(find.byKey(const ValueKey('music_mini_bar')), findsNothing);
    expect(find.text('HOME'), findsOneWidget);

    final page = inject<PlayerPageController>();
    final player = inject<PlayerController>();

    // A live entry with playback state: the bar shows title, clock and the
    // pause glyph (playing = true).
    runInAction(() {
      page.setPlaylist(
        const [PlayerPlaylistItem(path: '/tmp/probe.flac', title: 'Probe Song')],
        initialIndex: 0,
      );
      player.playback.playing = true;
      player.playback.currentPosition = const Duration(seconds: 42);
      player.playback.duration = const Duration(seconds: 200);
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('music_mini_bar')), findsOneWidget);
    expect(find.text('Probe Song'), findsOneWidget);
    expect(find.text('0:42 / 3:20'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // On the player page itself the bar hides (pageCurrent).
    runInAction(() => page.setPageCurrent(true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('music_mini_bar')), findsNothing);

    // And the pause glyph follows a manual pause.
    runInAction(() {
      page.setPageCurrent(false);
      player.playback.playing = false;
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('music_mini_bar')), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('miniBarTapReturnsToPlayerPage', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pumpAndSettle();

    final page = inject<PlayerPageController>();
    runInAction(() {
      page.setPlaylist(
        const [PlayerPlaylistItem(path: '/tmp/probe.flac', title: 'Probe Song')],
        initialIndex: 0,
      );
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('music_mini_bar')), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);

    // Tapping the bar (not the play/pause button) lands the outlet on the
    // player route.
    await tester.tap(find.byKey(const ValueKey('music_mini_bar')));
    await tester.pumpAndSettle();

    expect(find.text('PLAYER-ROUTE'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    // The tap target excludes the play/pause button: that one only toggles
    // playback (null-engine safe no-op), never navigates.
    expect(find.byKey(const ValueKey('music_mini_bar')), findsOneWidget);
  });
}

/// Minimal shell mirroring the real portrait chrome (menu.dart
/// _bottomMenu): shell route child + RouterOutlet + the mini bar in
/// bottomNavigationBar, seeded at /tab/home/ like InitPage does. The outlet
/// stays unkeyed: the root-level navigate below replaces the shell route,
/// and a GlobalKey would collide with itself across the swap frame.
Widget _harness() {
  var seeded = false;

  final playerModule = createModule(
    path: '/player',
    register: (c) => c.route(
      '/',
      child: (context, state) => const Text('PLAYER-ROUTE'),
    ),
  );
  final tabModule = createModule(
    path: '/tab',
    register: (c) => c.route(
      '/',
      child: (context, state) => Scaffold(
        body: RouterOutlet(),
        bottomNavigationBar: const MusicMiniBar(),
      ),
      children: (sub) => sub
        ..route(
          '/home',
          child: (context, state) => const Text('HOME'),
        )
        ..module(playerModule),
    ),
  );
  final appModule = createModule(
    register: (c) {
      c
        // The real singletons' dependency set (index_module.dart): both
        // controllers construct without an engine; play/pause null-guard.
        ..addSingleton<ShaderAssetService>(ShaderAssetService.new)
        ..addSingleton<AudioController>(AudioController.new)
        ..addSingleton<PlayerController>(PlayerController.new)
        ..addSingleton<PlayerPageController>(PlayerPageController.new)
        ..route(
          '/',
          child: (context, state) {
            if (!seeded) {
              seeded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.navigate('/tab/home/');
              });
            }
            return const SizedBox.shrink();
          },
        )
        ..module(tabModule);
    },
  );

  return ModularApp(
    module: appModule,
    child: Builder(
      builder: (context) =>
          MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context)),
    ),
  );
}
