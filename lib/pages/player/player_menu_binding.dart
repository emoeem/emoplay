import 'dart:async';

import 'package:emoplay/pages/player/player_keyboard_shortcuts.dart';
import 'package:emoplay/services/platform/player_menu_service.dart';

/// Native (macOS) player menu binding extracted from player_item.dart (M3-T0
/// god-class split; pure move, no behavior change).
///
/// Tracks how many player menus are open so [PlayerKeyboardShortcuts] can
/// park shortcuts while a menu owns the keys.
class PlayerMenuBinding {
  int _openPlayerMenuCount = 0;

  /// Non-zero while any player menu is open (keyboard isBlocked check).
  int get openCount => _openPlayerMenuCount;

  void init(Map<String, PlayerShortcutAction> actions) {
    unawaited(PlayerMenuService.initialize(actions));
  }

  void dispose() {
    unawaited(PlayerMenuService.dispose());
  }

  void handleVisibilityChanged(bool isOpen) {
    if (isOpen) {
      _openPlayerMenuCount++;
    } else if (_openPlayerMenuCount > 0) {
      _openPlayerMenuCount--;
    }
  }
}
