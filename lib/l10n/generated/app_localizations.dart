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
