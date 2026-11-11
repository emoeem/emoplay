// Tests for the media_kit integration preset (MpvPlayerProperties): the
// pure-logic half of the 1.x MpvEngine::initialize default table + the
// PluginManager::mergeScriptOptions append semantics, and — since the CI
// runner gained a real libmpv (equalizer_test.dart precedent, R3 7debc83) —
// the apply() half, ported case-for-case from mpv-emo tests/test_mpv_engine.cpp:
//
//   propertyRoundTrip                    -> propertyRoundTripDispatch
//   scriptAutoloadDisabledByDefault      -> applyPresetLandsOnLiveCore
//   observedPropertySignals              -> observedPropertySignalsAvailableAndUnavailable
//   unavailablePropertiesEmitClearedValues -> unavailableIdleCoreReadsClearedValues
//   commandErrorEmitsErrorSignal         -> commandErrorSurfacesThroughLogStream
//   initializeSmoke                      -> absorbed into every live test below
//                                           (Player() + waitForPlayerInitialization
//                                           + the idle-active readback)
//   doubleInitializeRejected             -> not ported: 2.0 has no engine singleton
//                                           to reject a second initialize — the
//                                           bootstrap builds one Player per
//                                           session and MpvPlayerProperties.apply
//                                           is stateless (see pending notes).
//
// The live tests drive a real (idle) libmpv core exactly like 1.x — media_kit's
// native assets resolve the bundled libmpv under flutter_test (probed
// 2026-11-10), so no display or render surface is involved (vo stays at the
// libmpv idle default; the preset deliberately never touches vo/osc/terminal,
// see lib/mpv/config/mpv_player_properties.dart lines 46-63).
//
// Dispatch mapping (1.x MpvEngine::setProperty QMetaType switch -> the fork,
// media_kit real.dart @ 83b7ca6):
//   Bool -> MPV_FORMAT_FLAG          -> Player.pause()/play()
//                                       (fork _setPropertyFlag, real.dart:2353)
//   numbers -> MPV_FORMAT_DOUBLE     -> Player.setVolume/setRate
//                                       (fork _setPropertyDouble, real.dart:2367)
//   default -> MPV_FORMAT_STRING     -> NativePlayer.setProperty
//                                       (fork mpv_set_property_string,
//                                       real.dart:1137)
// The 1.x MPV_FORMAT_STRING crash regression ("passing the char* itself made
// mpv read the first string bytes as a pointer") cannot recur on this path:
// Dart ffi marshals the value through toNativeUtf8() and passes the pointer
// by address.
//
// NONE semantics (1.x MpvEngine::handleEvents turned MPV_FORMAT_NONE
// notifications into cleared mirrors "or stale values from the previous file
// stick around"): on the fork the unavailable-property change event arrives,
// the listener is re-queried via mpv_get_property_string, gets NULL and is
// skipped (real.dart:1863-1873; getProperty's `?? ''` at real.dart:1163), and
// the on-demand adapter reads return '' / 0.0 (native_quality_engine.dart
// "treat as unknown, never a guess"). The stale-mirror hazard 1.x guarded
// against is designed away — 2.0 keeps no cached property mirror; controllers
// re-read at decision time. The tests below lock exactly that behavior on an
// idle core.
import 'dart:io';

import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/quality/native_quality_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  late Directory appData;

  setUp(() async {
    appData = await Directory.systemTemp.createTemp('emoplay_props_');
  });

  tearDown(() async {
    await appData.delete(recursive: true);
  });

  test('presetCarriesEngineDefaultsAndRedirects', () {
    final properties = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
    );

    // load-scripts forced off (1.x MpvEngine::initialize; see the module
    // header for the media_kit init-time-only caveat and the probe results).
    expect(properties['load-scripts'], 'no');
    // All five write paths land in EmoPlay's app data, from the same table
    // the import pass uses (redirectTargetSharesTheStartupTable).
    final redirects = MpvImportRules.redirectTargetsFor(appData.path);
    expect(redirects, hasLength(5));
    redirects.forEach((key, value) {
      expect(properties[key], value);
    });
    expect(properties['watch-later-dir'], '${appData.path}/watch_later');
    expect(properties['screenshot-directory'], '${appData.path}/screenshots');
    expect(properties['gpu-shader-cache-dir'], '${appData.path}/shader_cache');
    expect(properties['icc-cache-dir'], '${appData.path}/icc_cache');
    expect(properties['demuxer-cache-dir'], '${appData.path}/demuxer_cache');
  });

  test('compatOptionsOverridePresetDefaults', () {
    // CompatController.startupOptions() pins input-conf to EmoPlay's own
    // empty file; an imported input.conf replaces it. The preset must let
    // compat options win over the defaults.
    final properties = MpvPlayerProperties.build(
      compatOptions: {
        'input-conf': '/user/mpv/input.conf',
        'volume': '80',
      },
      appDataDir: appData.path,
    );

    expect(properties['input-conf'], '/user/mpv/input.conf');
    expect(properties['volume'], '80');
    // Redirects survive (the import rules redirect them to the same table
    // values; compat values win but are identical here).
    expect(properties['watch-later-dir'], '${appData.path}/watch_later');
  });

  test('pluginScriptsAppendWithoutReplacingImportedScripts', () {
    // 1.x PluginManager::mergeScriptOptions: append-only; the user's
    // imported script list keeps its position; no empty "scripts" value is
    // ever created.
    final separator = Platform.isWindows ? ';' : ':';

    final merged = MpvPlayerProperties.build(
      compatOptions: const {'scripts': '/user/mpv/scripts/a.lua'},
      appDataDir: appData.path,
      pluginScripts: const ['/plugins/uosc/uosc.lua', '/plugins/anime4k.lua'],
    );
    expect(merged['scripts'],
        '/user/mpv/scripts/a.lua$separator/plugins/uosc/uosc.lua$separator/plugins/anime4k.lua');

    final created = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
      pluginScripts: const ['/plugins/uosc/uosc.lua'],
    );
    expect(created['scripts'], '/plugins/uosc/uosc.lua');

    final untouched = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
      pluginScripts: const [],
    );
    expect(untouched.containsKey('scripts'), isFalse);
  });

  test('replaygainMappingAndPresetPlacement', () {
    // M5-T2（纯逻辑半）：设置词汇 off/track/album → mpv replaygain 属性值
    // no/track/album 的映射（考证见 mpv_player_properties.dart 文件头
    // M5-T2 块：mpv v0.41.0 options.rst 手册 + shipped libmpv live 回读）。
    expect(MpvPlayerProperties.replaygainValues, ['off', 'track', 'album']);
    expect(
      MpvPlayerProperties
          .replaygainMpvValue(MpvPlayerProperties.replaygainOff),
      'no',
    );
    expect(
      MpvPlayerProperties
          .replaygainMpvValue(MpvPlayerProperties.replaygainTrack),
      'track',
    );
    expect(
      MpvPlayerProperties
          .replaygainMpvValue(MpvPlayerProperties.replaygainAlbum),
      'album',
    );
    // 未知值回落 'no'（1.x 行为）：与 QueueLoopMode.fromStorageValue 同型
    // 的存储契约——臆测一个增益档比拒绝更危险。
    expect(MpvPlayerProperties.replaygainMpvValue('bogus-gain'), 'no');

    // 预置位置：默认 build() 钉 replaygain='no'（1.x 现状，审计表陈述意
    // 图）与 gapless-audio='weak'（mpv 自身默认的显式钉，考证注释随行：
    // 行为与改造前逐位一致，见文件头）。
    final defaults = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
    );
    expect(defaults['replaygain'], 'no');
    expect(defaults['gapless-audio'], 'weak');

    // 用户词汇透传到预置。
    final track = MpvPlayerProperties.build(
      compatOptions: const {},
      appDataDir: appData.path,
      replaygain: MpvPlayerProperties.replaygainTrack,
    );
    expect(track['replaygain'], 'track');

    // 导入的用户 mpv.conf 显式项后写者胜（与 load-scripts 等默认项同一优
    // 先级）：compat 层的同名键覆盖预置默认。
    final compatWins = MpvPlayerProperties.build(
      compatOptions: const {
        'replaygain': 'album',
        'gapless-audio': 'no',
      },
      appDataDir: appData.path,
    );
    expect(compatWins['replaygain'], 'album');
    expect(compatWins['gapless-audio'], 'no');
  });

  // ---------------------------------------------------------------------------
  // apply() half — a real (idle) libmpv core per test, same pattern as
  // test/equalizer_test.dart. Every readback below was probed against the
  // shipped libmpv (mpv v0.41.0-11-gf011d73d5-dirty) on 2026-11-10.
  // ---------------------------------------------------------------------------

  test('applyPresetLandsOnLiveCore', () async {
    // Port of scriptAutoloadDisabledByDefault plus the live half of
    // presetCarriesEngineDefaultsAndRedirects: build() output applied to a
    // freshly created core, then read back.
    //
    // 1.x set load-scripts=no pre-init (MpvEngine.cpp:98) and asserted the
    // readback; 2.0 sets it post-init where the set is accepted but INERT
    // (init-time-only option — module header probe), so this asserts the
    // option-table half of the guarantee: the effective option table states
    // the intent, and no scripting backend ships in this libmpv build
    // regardless (mpv_player_properties.dart lines 29-31). The behavioral
    // half is unchanged from 1.x: scripts enter only via the explicit
    // "scripts" option.
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    // mpv defaults load-scripts to yes (options.c) and libmpv's builtin
    // profile does not disable it — read back from the untouched core.
    expect(await native.getProperty('load-scripts'), 'yes');
    // The core is up and idle (1.x initializeSmoke's handle() != nullptr).
    expect(await native.getProperty('idle-active'), 'yes');

    final properties = MpvPlayerProperties.build(
      compatOptions: const {'volume': '65'},
      appDataDir: appData.path,
    );
    expect(properties, isNot(contains('scripts')));
    await MpvPlayerProperties.apply(native, properties);

    expect(await native.getProperty('load-scripts'), 'no');

    // All five write paths land in EmoPlay's app data — the redirect
    // invariant "never write the user's mpv directory" holds on the live
    // core, not just in the built map.
    expect(await native.getProperty('watch-later-dir'), '${appData.path}/watch_later');
    expect(await native.getProperty('screenshot-directory'), '${appData.path}/screenshots');
    expect(await native.getProperty('gpu-shader-cache-dir'), '${appData.path}/shader_cache');
    expect(await native.getProperty('icc-cache-dir'), '${appData.path}/icc_cache');
    expect(await native.getProperty('demuxer-cache-dir'), '${appData.path}/demuxer_cache');

    // A compat option (imported user option) reaches the core too; volume is
    // a double slot, so mpv normalizes the readback to '65.000000' — assert
    // the numeric value, not the serialization.
    expect(double.tryParse(await native.getProperty('volume')), 65.0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('propertyRoundTripDispatch', () async {
    // Port of propertyRoundTrip: set -> read back across the three format
    // paths the 1.x engine dispatched on (MpvEngine.cpp:303-333). The 1.x
    // typed readbacks (toDouble/toBool/toString) become mpv's string
    // serialization of each slot: doubles come back %f-normalized, flags as
    // yes/no, strings verbatim (all probed 2026-11-10).
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    // DOUBLE path (1.x: setProperty volume 42.0 / speed 1.5 -> MPV_FORMAT_DOUBLE).
    await player.setVolume(42.0);
    expect(double.tryParse(await native.getProperty('volume')), 42.0);
    await player.setRate(1.5);
    expect(double.tryParse(await native.getProperty('speed')), 1.5);
    // The fork mirrors volume into state from its own internal observation
    // (real.dart:1498-1504) — the 2.0 stand-in for the typed getProperty.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.state.volume, 42.0);
    expect(player.state.rate, 1.5);

    // FLAG path (1.x: setProperty pause true -> MPV_FORMAT_FLAG); the fork's
    // typed setters write the same flag slot (real.dart:2353).
    await player.pause();
    expect(await native.getProperty('pause'), 'yes');
    await player.play();
    expect(await native.getProperty('pause'), 'no');

    // STRING path (1.x default branch -> MPV_FORMAT_STRING; the set expects
    // the ADDRESS of a char* — a regression that cannot recur through Dart
    // ffi, see the file header). String-valued properties round-trip
    // verbatim, exactly like the 1.x toString() equality.
    await native.setProperty('tone-mapping', 'bt.2390');
    expect(await native.getProperty('tone-mapping'), 'bt.2390');
    await native.setProperty('scale', 'ewa_lanczossharp');
    expect(await native.getProperty('scale'), 'ewa_lanczossharp');

    // String forms of the numeric properties parse through mpv's option
    // parser into the same double slots (the 1.x int->double conversion is
    // subsumed: every Dart-side numeric set is a string parse here).
    await native.setProperty('volume', '80');
    expect(double.tryParse(await native.getProperty('volume')), 80.0);
    await native.setProperty('speed', '0.75');
    expect(double.tryParse(await native.getProperty('speed')), 0.75);
    await native.setProperty('pause', 'yes');
    expect(await native.getProperty('pause'), 'yes');

    // The typed volume write also fires the stream (1.x volumeChanged's
    // closest 2.0 analog; asserted here so the mirror is covered from the
    // property-write side, not only the typed-setter side below).
    final volumeEvents = <double>[];
    final subscription = player.stream.volume.listen(volumeEvents.add);
    await native.setProperty('volume', '55');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subscription.cancel();
    expect(volumeEvents, contains(55.0));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('observedPropertySignalsAvailableAndUnavailable', () async {
    // Port of observedPropertySignals + the observation half of
    // unavailablePropertiesEmitClearedValues, on a real idle core:
    //
    //  * available properties (pause/volume) deliver change notifications
    //    through the fork's observeProperty — the 2.0 analog of the 1.x
    //    pausedChanged/volumeChanged signals, including mpv's initial
    //    notification per observed property (1.x handleEvents comment);
    //  * unavailable properties (container-fps/current-vo — nothing is
    //    playing) NEVER deliver a value on the idle core: mpv's initial
    //    notification arrives as MPV_FORMAT_NONE, the fork re-queries, gets
    //    NULL and skips the listener (real.dart:1863-1873). 1.x turned those
    //    events into cleared mirrors; 2.0 drops the delivery and re-reads on
    //    demand (see unavailableIdleCoreReadsClearedValues) — either way no
    //    guessed value ever reaches the controller layer.
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    final pauseEvents = <String>[];
    final volumeEvents = <String>[];
    final fpsEvents = <String>[];
    final voEvents = <String>[];
    await native.observeProperty('pause', (v) async => pauseEvents.add(v));
    await native.observeProperty('volume', (v) async => volumeEvents.add(v));
    await native.observeProperty('container-fps', (v) async => fpsEvents.add(v));
    await native.observeProperty('current-vo', (v) async => voEvents.add(v));
    addTearDown(() async {
      await native.unobserveProperty('pause').catchError((_) {});
      await native.unobserveProperty('volume').catchError((_) {});
      await native.unobserveProperty('container-fps').catchError((_) {});
      await native.unobserveProperty('current-vo').catchError((_) {});
    });

    // Initial notifications flush (1.x QTest::qWait(200) equivalents).
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(pauseEvents, isNotEmpty);
    expect(volumeEvents, isNotEmpty);
    expect(fpsEvents, isEmpty);
    expect(voEvents, isEmpty);
    // The initial notification carries the current value (1.x handleEvents
    // comment: "mpv always sends an initial change notification per
    // observed property").
    final currentPause = await native.getProperty('pause');
    expect(pauseEvents.first, currentPause);
    final currentVolume = double.tryParse(await native.getProperty('volume'));

    // Our own writes flow through as change events (1.x QTRY_VERIFY asserts).
    // mpv only notifies on an ACTUAL value change (found empirically:
    // rewriting the identical value stays silent), so flip the current flag
    // instead of rewriting it.
    final flippedPause = currentPause == 'yes' ? 'no' : 'yes';
    final nextVolume = currentVolume == 42.0 ? 43.0 : 42.0;
    pauseEvents.clear();
    volumeEvents.clear();
    await native.setProperty('pause', flippedPause);
    await native.setProperty('volume', '$nextVolume');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(pauseEvents, contains(flippedPause));
    expect(
      volumeEvents.map(double.tryParse),
      contains(nextVolume),
    );

    // The event pump is provably live (both observers above just fired);
    // the unavailable observers stayed silent across both windows, so the
    // empty fps/vo lists are a real negative, not a dead pump.
    expect(fpsEvents, isEmpty);
    expect(voEvents, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('unavailableIdleCoreReadsClearedValues', () async {
    // Port of the readback half of unavailablePropertiesEmitClearedValues:
    // on an idle core the P5 properties are unavailable and every read
    // returns CLEARED values — mpv_get_property_string yields NULL, the
    // fork's getProperty maps that to '' (real.dart:1163), and the quality
    // adapter parses '' into 0.0 / empty (native_quality_engine.dart
    // "treat as unknown, never a guess"). 1.x asserted the same cleared
    // contract against the NONE events: empty map / 0.0 / 0 / ''.
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    expect(await native.getProperty('container-fps'), isEmpty);
    expect(await native.getProperty('frame-drop-count'), isEmpty);
    expect(await native.getProperty('current-vo'), isEmpty);
    expect(await native.getProperty('video-format'), isEmpty);

    // The adapter the quality controllers actually drive applies the same
    // rule: an idle core reports containerFps() 0.0 and empty strings —
    // never a guess (the 1.x containerFpsChanged(NONE) -> 0.0 rule).
    final engine = NativeQualityEngine(player);
    addTearDown(engine.dispose);
    expect(await engine.containerFps(), 0.0);
    expect(await engine.mediaTitle(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('commandErrorSurfacesThroughLogStream', () async {
    // Port of commandErrorEmitsErrorSignal: a bogus command must surface an
    // error, never vanish. 1.x emitted errorOccurred("... failed: ...") from
    // the mpv_command return code; the fork logs the same failure into
    // player.stream.log — 'media_kit' prefix with mpv_error_string text
    // ("error: invalid parameter _command(...)"), plus mpv's own
    // "Command '...' not found." entry (both probed 2026-11-10).
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    final errorLogs = <String>[];
    final subscription = player.stream.log.listen((entry) {
      if (entry.level == 'error') {
        errorLogs.add('${entry.prefix}: ${entry.text}');
      }
    });
    await native.command(['this-command-does-not-exist']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await subscription.cancel();

    expect(
      errorLogs.where((line) => line.contains('this-command-does-not-exist')),
      isNotEmpty,
    );
    // The fork's own mpv_command return-code report carries the mpv error
    // string, exactly the content 1.x wrapped into "... failed: ...".
    expect(
      errorLogs.where((line) => line.startsWith('media_kit:')),
      isNotEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('replaygainThreeStatesAndGaplessApplyToLiveCore', () async {
    // M5-T2 live 半（本文件 apply() 半的同一先例：真实 idle libmpv，无渲
    // 染面）。两件事：
    //   1. replaygain 三态经 apply 通道下发后逐态被核心接受且回读一致
    //      （行为层的增益听感属 mpv 选项自身契约，留待人工验收，见
    //      mpv_player_properties.dart 文件头 M5-T2 考证块的克制声明）。
    //   2. gapless 注释与行为一致：untouched core 回读 'weak'（mpv 默认，
    //      probed 2026-11-12；options.rst "Default: weak"）——预置把
    //      'weak' 钉出来只是显式化默认，行为与改造前逐位一致；apply 后回
    //      读不变。
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as NativePlayer;
    await native.waitForPlayerInitialization;

    // Untouched-core defaults（probe）: replaygain 'no'（options.rst:
    // "With --replaygain=no (the default), perform no adjustment"）、
    // gapless-audio 'weak'。
    expect(await native.getProperty('replaygain'), 'no');
    expect(await native.getProperty('gapless-audio'), 'weak');

    // 三态 apply：off→no、track→track、album→album 逐态下发 + 回读。
    final states = <String, String>{
      MpvPlayerProperties.replaygainOff: 'no',
      MpvPlayerProperties.replaygainTrack: 'track',
      MpvPlayerProperties.replaygainAlbum: 'album',
    };
    for (final state in states.entries) {
      final properties = MpvPlayerProperties.build(
        compatOptions: const {},
        appDataDir: appData.path,
        replaygain: state.key,
      );
      await MpvPlayerProperties.apply(native, properties);
      expect(
        await native.getProperty('replaygain'),
        state.value,
        reason: 'replaygain=${state.key} must land as ${state.value}',
      );
    }
    // gapless 钉在整轮 apply 之后依旧 'weak'（注释与行为一致）。
    expect(await native.getProperty('gapless-audio'), 'weak');

    // 设置页切换动线用的单键通道（applyReplaygain）同样落核——它就是
    // apply() 的单键形态，失败走同一逐键日志。
    await MpvPlayerProperties.applyReplaygain(
        native, MpvPlayerProperties.replaygainTrack);
    expect(await native.getProperty('replaygain'), 'track');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
