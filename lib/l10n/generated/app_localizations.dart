import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  /// 应用名，与 lib/utils/constants.dart 的 appName 常量一致（1.x 约定：应用名不翻译）。
  ///
  /// In zh, this message translates to:
  /// **'EmoPlay'**
  String get appTitle;

  /// 主导航页签一（lib/pages/menu/menu.dart:171，SPEC §5 五页签）。
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// 主导航页签二（lib/pages/menu/menu.dart:176）。
  ///
  /// In zh, this message translates to:
  /// **'媒体库'**
  String get tabLibrary;

  /// 主导航页签三（lib/pages/menu/menu.dart:181）。
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get tabPlayer;

  /// 主导航页签四（lib/pages/menu/menu.dart:186）。
  ///
  /// In zh, this message translates to:
  /// **'插件'**
  String get tabPlugins;

  /// 主导航页签五（lib/pages/menu/menu.dart:191）。
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get tabSettings;

  /// 页签壳上连按两次返回退出时的提示 toast（lib/pages/menu/menu.dart _handleSystemBack）。
  ///
  /// In zh, this message translates to:
  /// **'再按一次退出应用'**
  String get doubleBackToExit;

  /// 设置中心「音频」分类页标题（lib/pages/settings/audio_settings.dart SettingsDetailScaffold，SPEC §6 category 4）。
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get audioTitle;

  /// 音频页均衡器分组标题（audio_settings.dart SettingsSection）。
  ///
  /// In zh, this message translates to:
  /// **'均衡器'**
  String get equalizerSection;

  /// 音频页分组脚注：EQ 开启时的 af 链状态说明（audio_settings.dart bottomInfo）。
  ///
  /// In zh, this message translates to:
  /// **'已应用于 mpv 音频滤镜链（整链写入；关闭时恢复变速基线）'**
  String get equalizerEnabledInfo;

  /// 音频页分组脚注：EQ 关闭时的 af 链状态说明（audio_settings.dart bottomInfo）。
  ///
  /// In zh, this message translates to:
  /// **'已停用 — mpv 音频滤镜链保持不动'**
  String get equalizerDisabledInfo;

  /// 音频页 EQ 开关瓦片标题（audio_settings.dart SettingsTile.switchTile）。
  ///
  /// In zh, this message translates to:
  /// **'启用均衡器'**
  String get equalizerEnableTitle;

  /// 音频页 EQ 开关瓦片描述（audio_settings.dart SettingsTile.switchTile）。
  ///
  /// In zh, this message translates to:
  /// **'10 段 ISO 倍频程均衡，写入 mpv af 链'**
  String get equalizerEnableDescription;

  /// 音频页预设下拉标题（audio_settings.dart SettingsDropdownTile）。
  ///
  /// In zh, this message translates to:
  /// **'预设'**
  String get equalizerPresetTitle;

  /// 音频页预设下拉描述：用户移动过频段后（equalizerPreset == 'custom'）。
  ///
  /// In zh, this message translates to:
  /// **'已手动调整 — 当前为自定义曲线'**
  String get equalizerPresetCustomInfo;

  /// 音频页预设下拉描述：未移动频段时的默认提示。
  ///
  /// In zh, this message translates to:
  /// **'选择一个内置曲线'**
  String get equalizerPresetPickInfo;

  /// 均衡器预设 flat 的显示名（audioEqualizerPresetLabels，键对齐 music/equalizer.dart 的 kPresetNames）。
  ///
  /// In zh, this message translates to:
  /// **'平坦'**
  String get presetFlat;

  /// 均衡器预设 bass 的显示名（audioEqualizerPresetLabels）。
  ///
  /// In zh, this message translates to:
  /// **'低音增强'**
  String get presetBass;

  /// 均衡器预设 vocal 的显示名（audioEqualizerPresetLabels）。
  ///
  /// In zh, this message translates to:
  /// **'人声'**
  String get presetVocal;

  /// 均衡器预设 live 的显示名（audioEqualizerPresetLabels）。
  ///
  /// In zh, this message translates to:
  /// **'现场'**
  String get presetLive;

  /// 音频页频段增益分组标题（audio_settings.dart 第二个 SettingsSection；频点数值与 Hz/dB 为通用记号，不进 arb）。
  ///
  /// In zh, this message translates to:
  /// **'频段增益（dB）'**
  String get equalizerGainSection;

  /// 音频页 replaygain 等全局播放属性分组标题（audio_settings.dart M5-T2 新增 SettingsSection）。
  ///
  /// In zh, this message translates to:
  /// **'音频属性'**
  String get audioPropertiesSection;

  /// replaygain 下拉瓦片标题（audio_settings.dart；ReplayGain 为 mpv 选项与音乐软件通用专有名词，保留原文）。
  ///
  /// In zh, this message translates to:
  /// **'ReplayGain 响度均衡'**
  String get audioReplaygainTitle;

  /// replaygain 下拉瓦片描述（audio_settings.dart）。
  ///
  /// In zh, this message translates to:
  /// **'按文件内 ReplayGain 标签自动调整增益（mpv replaygain 属性）'**
  String get audioReplaygainDescription;

  /// replaygain=off 的显示名（audioReplaygainLabels；mpv 侧映射为 no，映射考证见 mpv_player_properties.dart 文件头）。
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get replaygainOff;

  /// replaygain=track 的显示名（audioReplaygainLabels；按单曲增益标签调整）。
  ///
  /// In zh, this message translates to:
  /// **'按音轨'**
  String get replaygainTrack;

  /// replaygain=album 的显示名（audioReplaygainLabels；优先专辑增益标签，缺标签时 mpv 回落音轨增益）。
  ///
  /// In zh, this message translates to:
  /// **'按专辑'**
  String get replaygainAlbum;

  /// 设置中心「常规」分类页标题（lib/pages/settings/general_settings.dart SettingsDetailScaffold，SPEC §6 category 1）。
  ///
  /// In zh, this message translates to:
  /// **'常规'**
  String get generalTitle;

  /// 常规页「启动」分组标题。
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get generalStartupSection;

  /// 常规页启动页下拉瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'启动页'**
  String get startupPageTitle;

  /// 常规页启动页下拉瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'应用开启时的默认页面'**
  String get startupPageDescription;

  /// 常规页继续播放开关瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'继续播放'**
  String get resumeTitle;

  /// 常规页继续播放开关瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'打开看过的文件时从上次位置继续（关闭则从头播放）'**
  String get resumeDescription;

  /// 常规页媒体库扫描分组标题。
  ///
  /// In zh, this message translates to:
  /// **'媒体库扫描'**
  String get libraryScanSection;

  /// 常规页扫描深度滑块瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'扫描深度'**
  String get scanDepthTitle;

  /// 常规页扫描深度滑块瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'媒体根目录之下允许下钻的目录层数（0 = 不限）'**
  String get scanDepthDescription;

  /// 扫描深度为 0 时的取值标签。
  ///
  /// In zh, this message translates to:
  /// **'不限'**
  String get scanDepthUnlimited;

  /// 扫描深度取值标签（n ≥ 1）。
  ///
  /// In zh, this message translates to:
  /// **'{n} 层'**
  String scanDepthLayers(int n);

  /// 常规页跳过隐藏文件开关瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'跳过隐藏文件'**
  String get skipHiddenTitle;

  /// 常规页跳过隐藏文件开关瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'扫描时不进入隐藏目录、不收录隐藏文件'**
  String get skipHiddenDescription;

  /// 常规页更新分组标题。
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updateSection;

  /// 常规页更新检查瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'更新检查'**
  String get updateCheckTitle;

  /// 常规页更新检查瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'启动时检查应用更新'**
  String get updateCheckDescription;

  /// 常规页窗口行为分组标题（仅桌面端）。
  ///
  /// In zh, this message translates to:
  /// **'窗口行为'**
  String get windowBehaviorSection;

  /// 常规页关闭窗口行为下拉瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时'**
  String get exitBehaviorTitle;

  /// 常规页关闭窗口行为下拉瓦片描述。
  ///
  /// In zh, this message translates to:
  /// **'设置点击窗口关闭按钮后的行为'**
  String get exitBehaviorDescription;

  /// 关闭窗口行为选项一（原「界面设置」键值不变：SettingsKeys.exitBehavior = 0）。
  ///
  /// In zh, this message translates to:
  /// **'退出 EmoPlay'**
  String get exitBehaviorExit;

  /// 关闭窗口行为选项二（SettingsKeys.exitBehavior = 1）。
  ///
  /// In zh, this message translates to:
  /// **'最小化至托盘'**
  String get exitBehaviorTray;

  /// 关闭窗口行为选项三（SettingsKeys.exitBehavior = 2）。
  ///
  /// In zh, this message translates to:
  /// **'每次都询问'**
  String get exitBehaviorAsk;

  /// 常规页恢复默认设置分组标题（施工件 B：1.x SettingsService::restoreDefaults 的 UI 槽位）。
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get generalRestoreSection;

  /// 恢复默认设置瓦片标题。
  ///
  /// In zh, this message translates to:
  /// **'恢复默认设置'**
  String get restoreDefaultsTitle;

  /// 恢复默认设置瓦片描述：作用域为 settings.json 的 quality/behavior/music 三分区。
  ///
  /// In zh, this message translates to:
  /// **'将画质、常规与音频偏好重置为默认值'**
  String get restoreDefaultsDescription;

  /// 恢复默认设置危险确认对话框标题（EmoDialog + AlertDialog）。
  ///
  /// In zh, this message translates to:
  /// **'恢复默认设置？'**
  String get restoreDefaultsDialogTitle;

  /// 恢复默认设置确认对话框正文：对齐 1.x 语义（test_settings_service.cpp restoreDefaultsKeepsMediaAndHistory——媒体库、历史与导入决策不动）。
  ///
  /// In zh, this message translates to:
  /// **'画质、常规（继续播放与扫描参数）与音频均衡器将回到默认值。媒体库与观看历史不会删除；mpv 配置导入决策不受影响。'**
  String get restoreDefaultsDialogContent;

  /// 确认对话框的危险确认按钮文字（error 色 FilledButton）。
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get restoreDefaultsConfirm;

  /// 确认对话框取消按钮文字。
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// settings.json 写失败 toast（_persistBehavior / 恢复默认共用的页面侧契约）。
  ///
  /// In zh, this message translates to:
  /// **'设置保存失败，请检查磁盘'**
  String get settingsSaveFailed;

  /// 恢复默认设置成功 toast。
  ///
  /// In zh, this message translates to:
  /// **'已恢复默认设置'**
  String get restoreDefaultsDone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
