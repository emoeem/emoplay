// Dart port of mpv-emo src/compat/MpvKeyName.{h,cpp} (A-class). The Qt::Key
// enumeration becomes Flutter's LogicalKeyboardKey; the "ctrl+shift+PGDWN"
// grammar and every mapped key/value are unchanged.
//
// Maps Flutter key events to mpv key names, so key presses that EmoPlay's own
// shortcuts do not consume can be fed to mpv's input layer ("keypress"
// command). This is what makes bindings imported from a user's input.conf
// actually fire in the embedded UI (key names verified against mpv v0.37
// DOCS/man/input.rst by the 1.x implementation).
//
// Pure logic, unit-testable. Returns an empty string for keys that cannot be
// represented in mpv's key grammar (the caller then simply does not forward).

import 'package:flutter/services.dart';

class MpvKeyName {
  MpvKeyName._();

  // Qt::Key -> mpv base key name (without modifiers). Null for unmappable.
  // 1.x note: Qt::Key_Backtab also mapped to "TAB"; Flutter's key map has no
  // separate backtab constant (Shift+Tab surfaces as LogicalKeyboardKey.tab),
  // so the tab entry covers it.
  static final Map<LogicalKeyboardKey, String> _namedKeys = {
    LogicalKeyboardKey.escape: 'ESC',
    LogicalKeyboardKey.tab: 'TAB',
    LogicalKeyboardKey.backspace: 'BS',
    LogicalKeyboardKey.enter: 'ENTER',
    LogicalKeyboardKey.numpadEnter: 'ENTER',
    LogicalKeyboardKey.insert: 'INS',
    LogicalKeyboardKey.delete: 'DEL',
    LogicalKeyboardKey.home: 'HOME',
    LogicalKeyboardKey.end: 'END',
    LogicalKeyboardKey.arrowLeft: 'left',
    LogicalKeyboardKey.arrowUp: 'up',
    LogicalKeyboardKey.arrowRight: 'right',
    LogicalKeyboardKey.arrowDown: 'down',
    LogicalKeyboardKey.pageUp: 'PGUP',
    LogicalKeyboardKey.pageDown: 'PGDWN',
    LogicalKeyboardKey.space: 'SPACE',
  };

  // Qt::Key_F1..F24 -> "f1".."f24".
  static final Map<LogicalKeyboardKey, String> _functionKeys = {
    for (var i = 0; i < _functionKeyConstants.length; i++)
      _functionKeyConstants[i]: 'f${i + 1}',
  };
  static const List<LogicalKeyboardKey> _functionKeyConstants = [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
    LogicalKeyboardKey.f13,
    LogicalKeyboardKey.f14,
    LogicalKeyboardKey.f15,
    LogicalKeyboardKey.f16,
    LogicalKeyboardKey.f17,
    LogicalKeyboardKey.f18,
    LogicalKeyboardKey.f19,
    LogicalKeyboardKey.f20,
    LogicalKeyboardKey.f21,
    LogicalKeyboardKey.f22,
    LogicalKeyboardKey.f23,
    LogicalKeyboardKey.f24,
  ];

  // Letters (Key_A..Key_Z are ASCII 'A'..'Z' in Qt) and digits ('0'..'9')
  // map to their literal character, matching mpv's grammar.
  static final Map<LogicalKeyboardKey, String> _letterKeys = {
    for (var i = 0; i < 26; i++)
      _letterKeyConstants[i]: String.fromCharCode('a'.codeUnitAt(0) + i),
  };
  static const List<LogicalKeyboardKey> _letterKeyConstants = [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyG,
    LogicalKeyboardKey.keyH,
    LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyP,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyT,
    LogicalKeyboardKey.keyU,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyY,
    LogicalKeyboardKey.keyZ,
  ];

  static final Map<LogicalKeyboardKey, String> _digitKeys = {
    for (var i = 0; i < 10; i++)
      _digitKeyConstants[i]: String.fromCharCode('0'.codeUnitAt(0) + i),
  };
  static const List<LogicalKeyboardKey> _digitKeyConstants = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  // Punctuation that can appear under Ctrl in imported bindings (1.x table,
  // same values).
  static final Map<LogicalKeyboardKey, String> _punctuationKeys = {
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.quote: "'",
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.backslash: '\\',
    LogicalKeyboardKey.backquote: '`',
  };

  static String? _baseKeyName(LogicalKeyboardKey key) {
    return _namedKeys[key] ??
        _functionKeys[key] ??
        _letterKeys[key] ??
        _digitKeys[key] ??
        _punctuationKeys[key];
  }

  static String _withModifiers(
    String base,
    bool ctrl,
    bool alt,
    bool meta,
    bool shift,
  ) {
    var name = '';
    if (ctrl) name += 'ctrl+';
    if (alt) name += 'alt+';
    if (meta) name += 'meta+';
    if (shift) name += 'shift+';
    return '$name$base';
  }

  /// |key| is the event's [LogicalKeyboardKey], |ctrl|/|alt|/|meta|/|shift|
  /// the pressed modifiers (HardwareKeyboard.instance.isControlPressed and
  /// friends at the call site), |text| the event's character (used for
  /// printable punctuation like ">").
  static String fromFlutter(
    LogicalKeyboardKey key, {
    bool ctrl = false,
    bool alt = false,
    bool meta = false,
    bool shift = false,
    String text = '',
  }) {
    // Plain key with printable text: prefer the text so punctuation keeps
    // its literal form (">", ";", "0", "a", ...). Space is a named mpv key.
    if (!ctrl && !alt && !meta) {
      // 1.x checked text.size() == 1 in UTF-16 code units — a surrogate pair
      // (emoji, astral character) did not take the text path. Dart
      // String.length is also UTF-16 code units, so the check ports as-is.
      if (!shift && text.length == 1 && _isPrintable(text)) {
        return text;
      }
      final base = _baseKeyName(key);
      if (base == null) {
        return '';
      }
      return _withModifiers(base, false, false, false, shift);
    }

    // Modified key: build "ctrl+alt+meta+shift+<base>" from the key code;
    // the event text is a control character in this case and must not be
    // used.
    final base = _baseKeyName(key);
    if (base == null) {
      return '';
    }
    return _withModifiers(base, ctrl, alt, meta, shift);
  }

  // QChar::isPrint() && !isSpace() for the single-character case: anything
  // with a visible glyph. Control characters, DEL and whitespace are
  // excluded (they must take the named-key path instead).
  static bool _isPrintable(String text) {
    final code = text.codeUnitAt(0);
    if (code < 0x20 || code == 0x7F) {
      return false;
    }
    return text.trim().isNotEmpty;
  }
}
