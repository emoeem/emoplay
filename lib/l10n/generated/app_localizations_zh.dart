// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'EmoPlay';

  @override
  String get tabHome => '首页';

  @override
  String get tabLibrary => '媒体库';

  @override
  String get tabPlayer => '播放';

  @override
  String get tabPlugins => '插件';

  @override
  String get tabSettings => '设置';

  @override
  String get doubleBackToExit => '再按一次退出应用';

  @override
  String get audioTitle => '音频';

  @override
  String get equalizerSection => '均衡器';

  @override
  String get equalizerEnabledInfo => '已应用于 mpv 音频滤镜链（整链写入；关闭时恢复变速基线）';

  @override
  String get equalizerDisabledInfo => '已停用 — mpv 音频滤镜链保持不动';

  @override
  String get equalizerEnableTitle => '启用均衡器';

  @override
  String get equalizerEnableDescription => '10 段 ISO 倍频程均衡，写入 mpv af 链';

  @override
  String get equalizerPresetTitle => '预设';

  @override
  String get equalizerPresetCustomInfo => '已手动调整 — 当前为自定义曲线';

  @override
  String get equalizerPresetPickInfo => '选择一个内置曲线';

  @override
  String get presetFlat => '平坦';

  @override
  String get presetBass => '低音增强';

  @override
  String get presetVocal => '人声';

  @override
  String get presetLive => '现场';

  @override
  String get equalizerGainSection => '频段增益（dB）';
}
