// M5-T1 循环/队列验收测试（docs/EMOPLAY-3.0-ROADMAP.md §五 M5-T1：
// 「test/music_queue_test.dart ≥5：模式切换持久化、audio 队列续播、切
// video 形态语义」）。
//
// 三层覆盖：
//  1. 模式切换持久化 —— settings.json behavior.playlistMode 新键（§四红线：
//     默认值 + 往返，配套用例另见 test/emoplay_settings_test.dart）。
//  2. audio 队列续播 —— resolveQueueNextIndex 纯决策函数（lib/music/
//     music_queue.dart），none 顺序推进/队尾停止、playlist 队尾回卷、single
//     交给引擎原生 loop-file、autoPlayNext 总闸。决策收口在
//     PlayerProgressPipeline 的 completed 分支。
//  3. 切 video 形态语义 —— 循环模式是全局设置：video 会话
//     （PlaybackSession.isMusic = false）与 music 会话共用同一策略，形态只
//     切换 UI（音乐队列面板 vs 播放列表面板），不改变续播语义。
//
// 面板用例挂在真实 MediaStores 下（fake path provider，music_lyrics_page_test
// 同款 bootstrap）；引擎侧映射（QueueLoopMode → media_kit PlaylistMode）
// 需要 libmpv 实例，超出无头测试范围，映射正确性由 applyPlaylistMode/_playlistModeFor
// 的注释考证（media_kit real.dart open(): open(Media) 只装一 entry 的内部
// playlist）与真机冒烟承担。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/models/media_item.dart';
import 'package:emoplay/models/playback_session.dart';
import 'package:emoplay/music/music_queue.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/music_queue_panel.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-music-queue-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String file(String name) => '${tempDir.path}/$name';

  // ---- 1. 模式切换持久化 -----------------------------------------------------

  test('loopModeSwitchPersistsAcrossInstances', () {
    // 面板/设置页切换 → settings.json 落盘 → 新实例（下次启动）读回同值。
    final path = file('settings.json');
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isFalse); // 全新文件：nothing persisted yet
      expect(settings.playlistMode, QueueLoopMode.none); // 默认 = 1.x 行为
      settings.playlistMode = QueueLoopMode.single;
      expect(settings.save(), isTrue);
    }
    {
      final settings = EmoPlaySettings(path);
      expect(settings.load(), isTrue);
      expect(settings.playlistMode, QueueLoopMode.single);
      settings.playlistMode = QueueLoopMode.playlist;
      expect(settings.save(), isTrue);
    }
    final settings = EmoPlaySettings(path);
    expect(settings.load(), isTrue);
    expect(settings.playlistMode, QueueLoopMode.playlist);
    // 持久化词汇即三态字符串（behavior 段 JSON 键值可直接人工核对）。
    final document = jsonDecode(File(path).readAsStringSync()) as Map;
    final behavior = document['behavior']! as Map;
    expect(behavior['playlistMode'], 'playlist');
  });

  test('loopModeStorageRoundTripCoversAllThreeStates', () {
    // 三态词汇与解析契约：storageValue ↔ fromStorageValue 恒等；未知值回落
    // none（默认值语义，老文件/手改文件安全）。
    for (final mode in QueueLoopMode.values) {
      expect(QueueLoopMode.fromStorageValue(mode.storageValue), mode);
    }
    expect(QueueLoopMode.fromStorageValue(null), QueueLoopMode.none);
    expect(QueueLoopMode.fromStorageValue(''), QueueLoopMode.none);
    expect(QueueLoopMode.fromStorageValue('bogus'), QueueLoopMode.none);
    expect(QueueLoopMode.fromStorageValue(42), QueueLoopMode.none);
    // 切换次序固定：none → single → playlist → none。
    expect(queueLoopModeCycle(QueueLoopMode.none), QueueLoopMode.single);
    expect(queueLoopModeCycle(QueueLoopMode.single), QueueLoopMode.playlist);
    expect(queueLoopModeCycle(QueueLoopMode.playlist), QueueLoopMode.none);
  });

  // ---- 2. audio 队列续播 ------------------------------------------------------

  /// 五首音频的队列（music 会话语义），路径/标题不重要，数量才是变量。
  List<MediaItem> audioQueue([int count = 5]) => [
        for (var i = 0; i < count; i++)
          MediaItem(
            path: '/home/emo/Music/track${i + 1}.flac',
            title: 'Track ${i + 1}',
            type: 'audio',
          ),
      ];

  test('audioQueueContinuesThroughNoneModeAndStopsAtEnd', () {
    // none（默认）：顺序续播每一首，队尾停止 —— 与 1.x autoPlayNext 行为
    // 逐点一致（原 inline `nextIndex < length && autoPlayNext`）。
    for (var current = 0; current < 4; current++) {
      expect(
        resolveQueueNextIndex(
          currentIndex: current,
          count: 5,
          mode: QueueLoopMode.none,
          autoPlayNext: true,
        ),
        current + 1,
      );
    }
    expect(
      resolveQueueNextIndex(
        currentIndex: 4,
        count: 5,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      isNull,
    );
    // 空队列 / 越界 index（-1 空闲哨兵）：null。
    expect(
      resolveQueueNextIndex(
        currentIndex: 0,
        count: 0,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      isNull,
    );
    expect(
      resolveQueueNextIndex(
        currentIndex: -1,
        count: 5,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      isNull,
    );
  });

  test('audioQueueContinuesAndWrapsInPlaylistMode', () {
    // 列表循环：顺序推进，末尾回卷到第 0 首；单曲目队列同样自续。
    for (var current = 0; current < 5; current++) {
      expect(
        resolveQueueNextIndex(
          currentIndex: current,
          count: 5,
          mode: QueueLoopMode.playlist,
          autoPlayNext: true,
        ),
        (current + 1) % 5,
      );
    }
    expect(
      resolveQueueNextIndex(
        currentIndex: 0,
        count: 1,
        mode: QueueLoopMode.playlist,
        autoPlayNext: true,
      ),
      0,
    );
    // 对照：none 模式的单曲目队列播完即停。
    expect(
      resolveQueueNextIndex(
        currentIndex: 0,
        count: 1,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      isNull,
    );
  });

  test('singleLoopDefersToTheEngineAndAutoPlayNextGatesEveryMode', () {
    // 单曲循环：应用层永不推进（引擎原生 loop-file 重复当前文件；completed
    // 到不了应用层，此为双保险语义）。
    expect(
      resolveQueueNextIndex(
        currentIndex: 0,
        count: 5,
        mode: QueueLoopMode.single,
        autoPlayNext: true,
      ),
      isNull,
    );
    // 「自动连播」是总闸：关掉后任何模式都不自动续播（列表循环也不例外，
    // 与 1.x autoPlayNext 门一致）。
    for (final mode in QueueLoopMode.values) {
      expect(
        resolveQueueNextIndex(
          currentIndex: 0,
          count: 5,
          mode: mode,
          autoPlayNext: false,
        ),
        isNull,
        reason: 'mode $mode must not advance with autoPlayNext off',
      );
    }
  });

  // ---- 3. 切 video 形态语义 ---------------------------------------------------

  test('videoFormSessionSharesTheSameLoopPolicy', () {
    // 循环模式是全局设置：video 会话（isMusic=false，M1-M3 起的现状）与
    // music 会话走同一 resolveQueueNextIndex —— 形态只决定 UI（音乐队列
    // 面板 vs 播放列表面板），不改续播语义。三态在 video 会话上逐条复核。
    final session = PlaybackSession(
      items: [
        const MediaItem(path: '/movies/a.mkv', title: 'A', type: 'video'),
        const MediaItem(path: '/movies/b.mkv', title: 'B', type: 'video'),
        const MediaItem(path: '/movies/c.mkv', title: 'C', type: 'video'),
      ],
      startIndex: 0,
    );
    expect(session.isMusic, isFalse); // 视频形态标记（§四统一模型）
    final count = session.items.length;
    expect(
      resolveQueueNextIndex(
        currentIndex: 1,
        count: count,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      2,
    );
    expect(
      resolveQueueNextIndex(
        currentIndex: 2,
        count: count,
        mode: QueueLoopMode.none,
        autoPlayNext: true,
      ),
      isNull,
    ); // video 会话队尾同样停止
    expect(
      resolveQueueNextIndex(
        currentIndex: 2,
        count: count,
        mode: QueueLoopMode.playlist,
        autoPlayNext: true,
      ),
      0,
    ); // video 会话列表循环同样回卷
    expect(
      resolveQueueNextIndex(
        currentIndex: 1,
        count: count,
        mode: QueueLoopMode.single,
        autoPlayNext: true,
      ),
      isNull,
    );
  });

  // ---- 4. 面板（真实 MediaStores）---------------------------------------------

  testWidgets('musicQueuePanelSwitchesModePersistsAndSelects',
      (tester) async {
    // music 形态队列面板：底板 = 视频形态播放列表面板同源
    // （showAdaptiveBottomSheet + Observer 列表），加三态循环模式头部。
    // 覆盖：渲染队列行与当前高亮、循环切换落盘 + 回调、点选回调。
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });
    final settings = MediaStores.instance.settings;
    expect(settings.playlistMode, QueueLoopMode.none);

    final pageController = PlayerPageController();
    pageController.setPlaylist(
      [
        for (final item in audioQueue(3))
          PlayerPlaylistItem(path: item.path, title: item.title),
      ],
      initialIndex: 1,
    );

    QueueLoopMode? reportedMode;
    var selectedIndex = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MusicQueuePanel(
          playerPageController: pageController,
          onSelectItem: (index) async {
            selectedIndex = index;
          },
          onLoopModeChanged: (mode) => reportedMode = mode,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 队列行渲染 + 当前项高亮语义（底板结构复用：Observer 派生视图）。
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 3'), findsOneWidget);

    // 三态切换头部：点「单曲循环」→ 持久化 + 回调（引擎即时下发由调用方
    // 接 applyPlaylistMode，这里记录回调即接缝被调）。
    await tester.tap(find.text('单曲循环'));
    await tester.pumpAndSettle();
    expect(settings.playlistMode, QueueLoopMode.single);
    expect(reportedMode, QueueLoopMode.single);
    // 落盘断言：全新实例从磁盘读回 single（重启后仍是单曲循环）。
    final reloaded = EmoPlaySettings(file('settings.json'));
    expect(reloaded.load(), isTrue);
    expect(reloaded.playlistMode, QueueLoopMode.single);

    // 点选动线与视频形态面板一致：点 Track 3 → onSelectItem(2)。
    await tester.tap(find.text('Track 3'));
    await tester.pump();
    expect(selectedIndex, 2);
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
