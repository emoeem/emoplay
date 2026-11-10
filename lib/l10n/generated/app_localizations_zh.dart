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

  @override
  String get generalTitle => '常规';

  @override
  String get generalStartupSection => '启动';

  @override
  String get startupPageTitle => '启动页';

  @override
  String get startupPageDescription => '应用开启时的默认页面';

  @override
  String get resumeTitle => '继续播放';

  @override
  String get resumeDescription => '打开看过的文件时从上次位置继续（关闭则从头播放）';

  @override
  String get libraryScanSection => '媒体库扫描';

  @override
  String get scanDepthTitle => '扫描深度';

  @override
  String get scanDepthDescription => '媒体根目录之下允许下钻的目录层数（0 = 不限）';

  @override
  String get scanDepthUnlimited => '不限';

  @override
  String scanDepthLayers(int n) {
    return '$n 层';
  }

  @override
  String get skipHiddenTitle => '跳过隐藏文件';

  @override
  String get skipHiddenDescription => '扫描时不进入隐藏目录、不收录隐藏文件';

  @override
  String get updateSection => '更新';

  @override
  String get updateCheckTitle => '更新检查';

  @override
  String get updateCheckDescription => '启动时检查应用更新';

  @override
  String get windowBehaviorSection => '窗口行为';

  @override
  String get exitBehaviorTitle => '关闭窗口时';

  @override
  String get exitBehaviorDescription => '设置点击窗口关闭按钮后的行为';

  @override
  String get exitBehaviorExit => '退出 EmoPlay';

  @override
  String get exitBehaviorTray => '最小化至托盘';

  @override
  String get exitBehaviorAsk => '每次都询问';

  @override
  String get generalRestoreSection => '恢复';

  @override
  String get restoreDefaultsTitle => '恢复默认设置';

  @override
  String get restoreDefaultsDescription => '将画质、常规与音频偏好重置为默认值';

  @override
  String get restoreDefaultsDialogTitle => '恢复默认设置？';

  @override
  String get restoreDefaultsDialogContent =>
      '画质、常规（继续播放与扫描参数）与音频均衡器将回到默认值。媒体库与观看历史不会删除；mpv 配置导入决策不受影响。';

  @override
  String get restoreDefaultsConfirm => '恢复默认';

  @override
  String get cancel => '取消';

  @override
  String get settingsSaveFailed => '设置保存失败，请检查磁盘';

  @override
  String get restoreDefaultsDone => '已恢复默认设置';
}
