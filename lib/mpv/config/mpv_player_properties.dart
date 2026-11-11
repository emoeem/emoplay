// media_kit integration preset for the mpv compat layer (M5, PORT-MAP
// "src/mpv/MpvEngine.cpp（语义层） -> media_kit NativePlayer + properties").
//
// 1.x applied an option map with mpv_set_option_string BEFORE
// mpv_initialize (MpvEngine::initialize: built-in defaults -> user options ->
// re-assert vo/osc/terminal). The Predidit media-kit fork (commit
// 83b7ca63772856e1ea0158916177e136f7b7b0be, consulted read-only in the pub
// cache) exposes no pre-init hook: PlayerConfiguration has no generic
// properties field, and the only mpv_set_option_string loop happens inside
// NativeEventLoop.create with a map built privately in
// NativePlayer._create(). Everything public therefore lands AFTER
// mpv_initialize via NativePlayer.setProperty — the same mechanism media-kit
// itself and Kazumi use for every mpv option.
//
// Empirical probe of the shipped libmpv (build/native_assets/linux/
// libmpv.so.2 = "mpv v0.41.0-11-gf011d73d5-dirty", probed 2026-11-10 with a
// throwaway dlopen harness):
//   * post-init setProperty("input-conf"/"load-scripts"/"config-dir") is
//     accepted (returns 0) but INERT — client.h documents all three under
//     "options which are only read at initialization time"; a keypress probe
//     confirmed a post-init input-conf set never loads bindings.
//   * under libmpv defaults (config=no) mpv_initialize loads NO input.conf
//     from the default config dir, from MPV_HOME, or from a pre-init
//     config-dir either — and the media-kit fork never sets config=yes on
//     desktop (only its Android libass path does). So the 1.x consent
//     failure mode (user input.conf loaded behind our back) cannot occur
//     through this fork; the pin below keeps the guarantee explicit and
//     covers builds where the gate moves.
//   * the shipped libmpv has no lua/js scripting backend (features string
//     lists neither), so no .lua/.js can execute regardless of load-scripts;
//     auto-load and the explicit scripts list share that limitation.
//   * runtime-settable write paths (watch-later-dir, screenshot-directory,
//     gpu-shader-cache-dir, icc-cache-dir, demuxer-cache-dir) are accepted
//     and effective; the redirects below therefore DO take effect at this
//     layer.
//
// M3-T2 章节属性读取考证（2026-11-11，同一 libmpv + fork 源码，read-only）：
// chapter-list / chapter 不是本预置表的条目（二者是只读运行时属性，无需
// setProperty），读取通道是 NativePlayer.observeProperty —— fork 以
// MPV_FORMAT_NONE 注册观察，事件到达后用 readNativeString（即
// MPV_FORMAT_STRING）回读并把字符串交给监听器（real.dart `_handler`；
// 值不可用时 readNativeString 返回 null，监听器不触发）。字符串形态实测：
//   * chapter-list 序列化为 JSON 节点：`[{"title":"…","time":0.000000},…]`，
//     无章节文件为 `[]`；解析在 lib/pages/player/controller/chapters_model.dart
//     （非该 JSON 形态——例如旧 mpv 的 %len% 转义打印——降级为空章节表）。
//   * chapter 为整数字符串（"0"、"1"，不可用时读回空串；属性本身定义为
//     "not always available" 时为 -1）。
//   * 观察 attach 在 player.open 之后仍可靠：mpv 对每个观察属性都会先发
//     一次初始事件，文件加载完成后的值不丢。
//   * 测试通道注意：fork 预置 vid=no（real.dart `_create`，"prevent
//     redundant video decoding"，VideoController attach 时才恢复 auto），
//     headless 测试里只有视频轨的文件会 "No video or audio streams
//     selected" 直接卸载——live 夹具须带音频轨（或显式 vid=auto）。
//
// M5-T2 音频属性考证（2026-11-12，同一 libmpv + fork 源码，read-only）：
// replaygain 与 gapless-audio 都是 mpv 的常规 runtime 选项（mpv v0.41.0
// 手册 DOCS/man/options.rst 本地留档核验）：
//   * replaygain=<no|track|album>，默认 no。no=不调整；track=按音轨增益；
//     album=优先专辑增益、文件缺专辑标签时回落音轨增益。
//   * gapless-audio=<no|yes|weak>，默认 weak。weak=通常保持音频设备开启，
//     解码输出格式变化时才关闭重开——同参数编码的连播无缝，且不会像 yes
//     档那样把首个文件的输出参数锁死给后续文件（音质陷阱），是 mpv 自己
//     选定的折中默认。
//   * runtime 下发以 shipped libmpv 实测为准（2026-11-12，mpv
//     v0.41.0-11-gf011d73d5-dirty，live 用例见
//     mpv_player_properties_test.dart）：idle core 上 setProperty 被接受
//     且回读一致，untouched 默认回读 replaygain='no'、gapless-audio=
//     'weak'。options.rst 对二者均无 "applied only during (lib)mpv
//     initialization" 标记（手册对 init-only 选项的明示方式，如
//     config-dir）；但按 load-scripts 的同一教训保持克制：接受 + 回读一
//     致不等于行为层已重读，增益/无缝的听感生效属 mpv 选项自身契约，留
//     待 SPEC §9 人工验收。
//   * fork（real.dart `_create`，83b7ca6）的 pre-init options 与 post-init
//     属性表都不含 replaygain / gapless-audio——2.0 改造前的实际行为就是
//     上述 mpv 默认值。
//   * 1.x 从未实现二者：grep mpv-emo 的 src/ qml/ mpv.md 两词零命中；引擎
//     内置默认表（MpvEngine::initialize）只有 terminal/osc/vo/hwdec/
//     keep-open/load-scripts；gapless 是 1.x 明文遗留项（mpv-emo
//     docs/roadmap.md「遗留项：…gapless/loop 行为」、docs/architecture.md
//     音乐模式小节、docs/execution-log.md P7 已知限制；docs/
//     nativeization-plan.md 曾计划以 gapless-audio=weak 配合音乐模式无缝
//     切歌，但未落地）。
//   * replaygain 为 2.0 新增音频偏好（roadmap M5-T2「设置落音频类」）：
//     设置词汇 off/track/album（"off" 风格对齐 §7 qualityTier/debandMode
//     的 2.0 取值域），经 [replaygainMpvValue] 映射到 mpv 的 no/track/
//     album。默认 off 仍显式钉 'no'：与 load-scripts 同理让生效选项表
//     （mpv_settings 审计页）陈述意图，行为与 1.x 现状逐位一致；导入的
//     用户 mpv.conf 显式项依旧后写者胜（compatOptions 在 build() 里最后
//     addAll）。
//   * gapless-audio=weak 钉为全局预置项、不随音乐形态条件化：mpv 默认已是
//     weak（实测），钉住=行为与现状完全一致、意图可见、并防 fork 默认漂
//     移；为它加形态条件逻辑只会引入无行为差异的复杂度。1.x 音乐模式的无
//     缝切歌意图（nativeization-plan.md:67）由此以最小面落地。

import 'package:media_kit/media_kit.dart';

import 'package:emoplay/mpv/compat/compat_controller.dart';
import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/services/logging/logger.dart';

class MpvPlayerProperties {
  MpvPlayerProperties._();

  /// settings.json `audio.replaygain` 的持久化词汇（M5-T2，§四红线允许的
  /// 键追加）。"off" 风格对齐 §7 qualityTier/debandMode 的 2.0 取值域；
  /// mpv 侧的对应值由 [replaygainMpvValue] 映射（off→no）。
  static const String replaygainOff = 'off';
  static const String replaygainTrack = 'track';
  static const String replaygainAlbum = 'album';

  /// 三个设置词汇的表，供设置页与测试枚举（单一事实来源）。
  static const List<String> replaygainValues = <String>[
    replaygainOff,
    replaygainTrack,
    replaygainAlbum,
  ];

  /// 设置词汇 → mpv replaygain 属性值：off→no、track→track、album→album；
  /// 未知值回落 'no'（1.x 行为）——与 QueueLoopMode.fromStorageValue 的
  /// 存储契约同型：手改/损坏的取值永远落回不启用，绝不臆测一个增益档。
  static String replaygainMpvValue(String setting) {
    switch (setting) {
      case replaygainTrack:
        return 'track';
      case replaygainAlbum:
        return 'album';
      default:
        return 'no';
    }
  }

  /// The 1.x engine built-in defaults that survive the media_kit port.
  ///
  /// Embedding-critical forced values (SPEC §4.3 "media_kit 场景下映射为
  /// 等价属性") and where each now lives:
  ///   vo=libmpv   -> VideoController default `vo` on desktop
  ///                  (VideoControllerConfiguration doc: "Windows, GNU/Linux,
  ///                  macOS & iOS: libmpv"); the player page may override it
  ///                  (Android picks gpu/gpu-next).
  ///   osc=no      -> PlayerConfiguration(osc: false) at player creation; the
  ///                  fork additionally sets the option pre-init in
  ///                  NativePlayer._create when !configuration.osc.
  ///   terminal=no -> inherent to libmpv (client.h: "stdin/stdout/stderr and
  ///                  the terminal will never be accessed").
  ///   keep-open=yes -> the fork's own property map already sets it
  ///                  (NativePlayer._create: 'keep-open': 'yes').
  /// None of them are set here: re-setting them post-init would either be
  /// inert (osc is not a property at all — probe: "property not found") or
  /// race the render-context setup that owns vo.
  static Map<String, String> build({
    required Map<String, String> compatOptions,
    required String appDataDir,
    List<String> pluginScripts = const [],
    // M5-T2：settings.json `audio.replaygain`（off/track/album）。默认 off
    // = 1.x 现状（从未写过该属性）；MediaStores 组装预置时传入当前设置值。
    String replaygain = replaygainOff,
  }) {
    final properties = <String, String>{};

    // load-scripts=no (1.x MpvEngine::initialize, mpv v0.37考证: mpv
    // defaults to yes and would auto-load every script in the config dir's
    // scripts/ subdirectory — player/scripting.c mp_load_scripts — even
    // under libmpv; load-scripts=no only disables directory auto-loading,
    // not the explicit scripts list). Post-init the set is inert (see file
    // header); kept in the audit so the effective-option table states the
    // intent, and so the value is already correct for any future pre-init
    // path in the fork.
    properties['load-scripts'] = 'no';

    // Write paths land in EmoPlay's app data, never in the user's mpv
    // directory (SPEC §4.2). Built from MpvImportRules' single redirect
    // table so the startup pass and this preset can never disagree on the
    // sub-directory names (1.x invariant: one redirectTarget function for
    // startup AND runtime). demuxer-cache-dir may be refined afterwards by
    // the player bootstrap (media-kit's dual-cache directory) — that target
    // is EmoPlay-owned storage too, so the invariant "never write the user's
    // mpv directory" still holds.
    properties.addAll(MpvImportRules.redirectTargetsFor(appDataDir));

    // M5-T2 audio properties (考证见文件头 M5-T2 块)。post-init setProperty
    // 被接受且回读一致（live 用例实测；行为层听感留待人工验收）。放在默
    // 认半区：用户导入的 mpv.conf 显式项在下方 addAll(compatOptions) 里
    // 后写者胜。
    //
    // gapless-audio=weak：钉住 mpv 自身的默认（实测 idle core 回读 weak）
    // ——行为与改造前逐位一致，意图进审计表，防 fork 默认漂移；1.x 明文
    // 遗留的音乐模式无缝切歌意图以最小面兑现。
    properties['gapless-audio'] = 'weak';
    // replaygain：设置词汇 off/track/album 映射为 mpv 的 no/track/album；
    // off 钉 'no'（等价 1.x 现状，审计表陈述意图）。
    properties['replaygain'] = replaygainMpvValue(replaygain);

    // Compat options (imported user options + the input-conf pin from
    // CompatController.startupOptions) win over the defaults above: an
    // imported input.conf deliberately replaces the pinned empty file.
    properties.addAll(compatOptions);

    // Plugin scripts are APPENDED to the scripts option the compat layer
    // assembled — the user's imported script list is never replaced (1.x
    // PluginManager::mergeScriptOptions; main.cpp assembly order: compat
    // options -> plugin scripts append -> player initialization).
    _mergeScriptOptions(properties, pluginScripts);

    return properties;
  }

  // 1.x PluginManager::mergeScriptOptions: never create an empty "scripts"
  // value; append-only (whatever the user imported keeps its position).
  // The --scripts option is a PATH list (':' Unix / ';' Windows, mpv
  // options.rst), NOT the ',' of ordinary list options.
  static void _mergeScriptOptions(
    Map<String, String> options,
    List<String> entryPaths,
  ) {
    if (entryPaths.isEmpty) {
      return;
    }
    final addition = entryPaths.join(CompatController.scriptSeparator);
    final existing = options['scripts'];
    if (existing != null && existing.isNotEmpty) {
      options['scripts'] = '$existing${CompatController.scriptSeparator}$addition';
      return;
    }
    options['scripts'] = addition;
  }

  /// Applies the preset to a freshly created NativePlayer (the 1.x
  /// MpvEngine::initialize step). Every entry goes through
  /// NativePlayer.setProperty; failures are logged per-key and never abort
  /// player startup — the 1.x engine ignored per-option
  /// mpv_set_option_string failures the same way (options newer than the
  /// libmpv build are silently refused, per option).
  static Future<void> apply(
    NativePlayer player,
    Map<String, String> properties,
  ) async {
    final logger = EmoLogger();
    for (final entry in properties.entries) {
      try {
        await player.setProperty(entry.key, entry.value);
      } catch (e) {
        logger.w(
          'MpvPlayerProperties: failed to set ${entry.key}=${entry.value}',
          error: e,
        );
      }
    }
  }

  /// M5-T2 音频设置页切换动线的即时下发（对存活的当前 Player）：单键走同
  /// 一个 [apply] 通道，逐键失败日志的语义原样保留。下一 Player 由预置覆
  /// 盖（MediaStores 在设置保存后重排 startupMpvProperties）。
  static Future<void> applyReplaygain(NativePlayer player, String setting) {
    return apply(
      player,
      <String, String>{'replaygain': replaygainMpvValue(setting)},
    );
  }
}
