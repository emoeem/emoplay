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
}
