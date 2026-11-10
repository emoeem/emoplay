// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EmoPlay';

  @override
  String get tabHome => 'Home';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabPlayer => 'Player';

  @override
  String get tabPlugins => 'Plugins';

  @override
  String get tabSettings => 'Settings';

  @override
  String get doubleBackToExit => 'Press back again to exit';

  @override
  String get audioTitle => 'Audio';

  @override
  String get equalizerSection => 'Equalizer';

  @override
  String get equalizerEnabledInfo =>
      'Applied to the mpv audio filter chain (whole-chain write; disabling restores the speed-change baseline)';

  @override
  String get equalizerDisabledInfo =>
      'Disabled — the mpv audio filter chain is left untouched';

  @override
  String get equalizerEnableTitle => 'Enable equalizer';

  @override
  String get equalizerEnableDescription =>
      '10-band ISO octave equalizer, written to the mpv af chain';

  @override
  String get equalizerPresetTitle => 'Preset';

  @override
  String get equalizerPresetCustomInfo =>
      'Manually adjusted — currently a custom curve';

  @override
  String get equalizerPresetPickInfo => 'Pick a built-in curve';

  @override
  String get presetFlat => 'Flat';

  @override
  String get presetBass => 'Bass boost';

  @override
  String get presetVocal => 'Vocal';

  @override
  String get presetLive => 'Live';

  @override
  String get equalizerGainSection => 'Band gains (dB)';
}
