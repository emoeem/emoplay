import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/utils/constants.dart';

// Pins the keyLabel identity of the M3 施工件 C「A-B 循环 + 逐帧」 default
// bindings. PlayerKeyboardShortcuts dispatches on
// `event.logicalKey.keyLabel` (player_keyboard_shortcuts.dart _keyIdentity),
// so if Flutter ever renamed these labels the mpv-convention keys
// (L = ab-loop, '.' = frame-step, ',' = frame-back-step) would silently stop
// matching — the same failure mode the subdelay z/Z note in constants.dart
// guards against.
void main() {
  testWidgets('defaultShortcuts labels match Flutter key identities',
      (tester) async {
    final labels = <String, String>{
      for (final entry in defaultShortcuts.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };

    expect(labels['abloop'], 'L');
    expect(labels['framestep'], '.');
    expect(labels['framebackstep'], ',');
    expect(LogicalKeyboardKey.keyL.keyLabel, 'L');
    expect(LogicalKeyboardKey.period.keyLabel, '.');
    expect(LogicalKeyboardKey.comma.keyLabel, ',');

    // The three new actions are registered for the settings page and the
    // player action map (same-name entries in both Chinese-label tables).
    expect(defaultShortcuts.keys, containsAll(['abloop', 'framestep',
        'framebackstep']));
    for (final action in const ['abloop', 'framestep', 'framebackstep']) {
      expect(shortcutsChineseName[action], isNotNull,
          reason: '$action must have a Chinese label for the settings page');
    }
  });

  testWidgets('new keys do not collide with existing single-key bindings',
      (tester) async {
    final taken = <String, String>{};
    defaultShortcuts.forEach((action, keys) {
      for (final key in keys) {
        final previous = taken[key];
        // Long-press pairs (forward/volume) reuse their own keys legitimately;
        // the ones we add here must be fresh.
        expect(previous, isNull,
            reason: "key '$key' is bound to both $previous and $action");
        taken[key] = action;
      }
    });
  });
}
