// Dart port of mpv-emo tests/test_mpv_key_name.cpp — headless tests for the
// key event -> mpv key name mapping, the piece that lets imported input.conf
// bindings fire in the embedded UI. Qt::Key values map onto their
// LogicalKeyboardKey equivalents; assertion values copied verbatim.
import 'package:emoplay/mpv/compat/mpv_key_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('printableTextBecomesKeyName', () {
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.keyA, text: 'a'), 'a');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.digit0, text: '0'), '0');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.period, text: '.'), '.');
    // Text takes precedence over the code-based name for punctuation.
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.comma, text: ','), ',');
  });

  test('namedKeys', () {
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.arrowLeft), 'left');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.arrowRight), 'right');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.pageUp), 'PGUP');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.pageDown), 'PGDWN');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.f5), 'f5');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.f12), 'f12');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.home), 'HOME');
  });

  test('shiftedLetter', () {
    // Capital A is mpv's "shift+a" (same binding as input.conf "A").
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.keyA,
            shift: true, text: 'A'),
        'shift+a');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.arrowLeft, shift: true),
        'shift+left');
  });

  test('shiftedPunctuationPrefersText', () {
    // Shifted punctuation uses the canonical modifier form: mpv parses
    // "shift+." exactly like the ">" key name in an input.conf binding.
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.period,
            shift: true, text: '>'),
        'shift+.');
  });

  test('ctrlCombination', () {
    // Ctrl+letter: event text is a control character, so the name comes from
    // the key code.
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.keyS,
            ctrl: true, text: '\x03'),
        'ctrl+s');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.keyS,
            ctrl: true, shift: true),
        'ctrl+shift+s');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.arrowLeft, ctrl: true),
        'ctrl+left');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.comma, ctrl: true),
        'ctrl+,');
  });

  test('altAndMetaCombinations', () {
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.keyH, alt: true), 'alt+h');
    expect(
        MpvKeyName.fromFlutter(LogicalKeyboardKey.keyH,
            ctrl: true, alt: true),
        'ctrl+alt+h');
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.keyA, meta: true),
        'meta+a');
  });

  test('unmappableKeysReturnEmpty', () {
    // Qt::Key_MediaTogglePlayPause etc. have no mpv equivalent here.
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.mediaPlayPause), '');
    // Qt::Key_unknown: Flutter has no "unknown" constant, so the test uses a
    // synthetic keyId no mapped table contains (same semantics: no base key).
    const unknown = LogicalKeyboardKey(0x7fffdeadbeef);
    expect(MpvKeyName.fromFlutter(unknown), '');
    // Modifier-only events have no text and no base key.
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.shift, shift: true), '');
  });

  test('spaceIsNamedNotLiteral', () {
    // Space must map to mpv's named key, not a literal ' '.
    expect(MpvKeyName.fromFlutter(LogicalKeyboardKey.space, text: ' '),
        'SPACE');
  });
}
