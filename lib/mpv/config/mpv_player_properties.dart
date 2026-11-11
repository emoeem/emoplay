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

import 'package:media_kit/media_kit.dart';

import 'package:emoplay/mpv/compat/compat_controller.dart';
import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/services/logging/logger.dart';

class MpvPlayerProperties {
  MpvPlayerProperties._();

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
}
