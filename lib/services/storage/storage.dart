import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

import 'package:emoplay/services/storage/settings_keys.dart';
export 'package:emoplay/services/storage/settings_keys.dart';

/// Application settings storage.
///
/// EmoPlay 2.0 keeps only the typed settings box here; media data lives in
/// JSON stores under the application support directory (see docs/SPEC.md §7).
class GStorage {
  static late final Box<dynamic> _setting;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  static Future init() async {
    _hivePath = '${(await getApplicationSupportDirectory()).path}/hive';

    // Open each box with automatic recovery on corruption
    _setting = await _openBoxSafe<dynamic>('setting');
  }

  /// Open a Hive box with automatic recovery on corruption.
  /// If the box is corrupted, delete it and create a new empty one.
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      EmoLogger().e(
          'GStorage: Box "$boxName" corrupted, attempting recovery',
          error: e);

      // Delete the corrupted box files
      await _deleteBoxFiles(boxName);

      // Try to open again (will create a new empty box)
      try {
        final box = await Hive.openBox<T>(boxName);
        EmoLogger()
            .i('GStorage: Box "$boxName" recovered successfully (data lost)');
        return box;
      } catch (e2) {
        EmoLogger()
            .e('GStorage: Failed to recover box "$boxName"', error: e2);
        rethrow;
      }
    }
  }

  /// Delete Hive box files for a given box name
  static Future<void> _deleteBoxFiles(String boxName) async {
    if (_hivePath == null) return;

    final boxFile = File('$_hivePath/$boxName.hive');
    final lockFile = File('$_hivePath/$boxName.lock');

    try {
      if (await boxFile.exists()) {
        await boxFile.delete();
        EmoLogger().i('GStorage: Deleted corrupted box file: $boxName.hive');
      }
      if (await lockFile.exists()) {
        await lockFile.delete();
        EmoLogger().i('GStorage: Deleted lock file: $boxName.lock');
      }
    } catch (e) {
      EmoLogger()
          .e('GStorage: Failed to delete box files for "$boxName"', error: e);
    }
  }

  static T getSetting<T>(
    SettingKey<T> key, {
    SettingContext context = const SettingContext(),
  }) {
    final defaultValue = key.resolveDefault(context);
    final storedValue = _setting.get(key.name);
    if (storedValue is T) {
      return storedValue;
    }
    return defaultValue;
  }

  static Future<void> putSetting<T>(SettingKey<T> key, T value) async {
    await _setting.put(key.name, value);
  }

  static Stream<void> watchSettings(Iterable<SettingKey<Object?>> keys) {
    final names = keys.map((key) => key.name).toSet();
    return _setting.watch().where((event) => names.contains(event.key)).map((_) {});
  }

  static List<String> getStringListSettingByName(
    String key, {
    List<String> defaultValue = const [],
  }) {
    final storedValue = _setting.get(key);
    if (storedValue is List) {
      return storedValue.whereType<String>().toList();
    }
    return defaultValue;
  }

  static Future<void> putStringListSettingByName(
    String key,
    List<String> value,
  ) async {
    await _setting.put(key, value);
  }

  static Future<void> resetSettings(Iterable<SettingKey<Object?>> keys) async {
    await _setting.deleteAll(keys.map((key) => key.name));
    await _setting.flush();
  }

  static Future<void> resetPlayerSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.player));
  }

  GStorage._();
}
