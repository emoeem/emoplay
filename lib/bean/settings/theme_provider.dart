import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Application theme state.
///
/// Font (Kazumi convention, docs/SPEC.md §1): default is the system font
/// (fontFamily null + explicit CJK fallback, so fontconfig cannot dump
/// Chinese into a kaiti-style face); settings can switch to the bundled
/// MiSans (`assets/fonts/MiSans-Regular.ttf`, family 'MI_Sans_Regular').
const String kAppFontFamily = 'MI_Sans_Regular';
const List<String> kAppFontFamilyFallback = <String>[
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'sans-serif',
];

class ThemeProvider extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  bool useDynamicColor = false;
  String? currentFontFamily;
  late ThemeData light;
  late ThemeData dark;

  /// Mirrors SettingsKeys.useSystemFont: true → system font (null family).
  void setFontFamily(bool useSystemFont, {bool notify = true}) {
    currentFontFamily = useSystemFont ? null : kAppFontFamily;
    if (notify) {
      notifyListeners();
    }
  }

  /// Returns true if the effective theme is dark mode.
  /// Automatically gets platform brightness when themeMode is ThemeMode.system.
  bool isEffectiveDark() {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    final platformBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  void setTheme(ThemeData light, ThemeData dark, {bool notify = true}) {
    this.light = light;
    this.dark = dark;
    if (notify) notifyListeners();
  }

  void setThemeMode(ThemeMode mode, {bool notify = true}) {
    themeMode = mode;
    if (notify) notifyListeners();
  }

  void setDynamic(bool useDynamicColor, {bool notify = true}) {
    this.useDynamicColor = useDynamicColor;
    if (notify) notifyListeners();
  }
}
