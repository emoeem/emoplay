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

  @override
  String get generalTitle => 'General';

  @override
  String get generalStartupSection => 'Startup';

  @override
  String get startupPageTitle => 'Startup page';

  @override
  String get startupPageDescription => 'The page shown when the app launches';

  @override
  String get resumeTitle => 'Resume playback';

  @override
  String get resumeDescription =>
      'Reopening a watched file continues at the last position (off: start over)';

  @override
  String get libraryScanSection => 'Library scan';

  @override
  String get scanDepthTitle => 'Scan depth';

  @override
  String get scanDepthDescription =>
      'How many directory levels below a media root are descended (0 = unlimited)';

  @override
  String get scanDepthUnlimited => 'Unlimited';

  @override
  String scanDepthLayers(int n) {
    return '$n levels';
  }

  @override
  String get skipHiddenTitle => 'Skip hidden files';

  @override
  String get skipHiddenDescription =>
      'Hidden directories are not entered and hidden files are not indexed';

  @override
  String get updateSection => 'Updates';

  @override
  String get updateCheckTitle => 'Update check';

  @override
  String get updateCheckDescription => 'Check for app updates at startup';

  @override
  String get windowBehaviorSection => 'Window behavior';

  @override
  String get exitBehaviorTitle => 'When closing the window';

  @override
  String get exitBehaviorDescription =>
      'What happens when the window close button is clicked';

  @override
  String get exitBehaviorExit => 'Exit EmoPlay';

  @override
  String get exitBehaviorTray => 'Minimize to tray';

  @override
  String get exitBehaviorAsk => 'Ask every time';

  @override
  String get generalRestoreSection => 'Restore';

  @override
  String get restoreDefaultsTitle => 'Restore default settings';

  @override
  String get restoreDefaultsDescription =>
      'Reset picture-quality, general and audio preferences to their defaults';

  @override
  String get restoreDefaultsDialogTitle => 'Restore default settings?';

  @override
  String get restoreDefaultsDialogContent =>
      'Picture quality, general (resume playback and scan options) and the audio equalizer return to their defaults. The media library and watch history are kept; the mpv config import decision is not touched.';

  @override
  String get restoreDefaultsConfirm => 'Restore defaults';

  @override
  String get cancel => 'Cancel';

  @override
  String get settingsSaveFailed => 'Failed to save settings — check your disk';

  @override
  String get restoreDefaultsDone => 'Default settings restored';
}
