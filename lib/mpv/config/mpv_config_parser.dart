// Dart port of mpv-emo src/config/MpvConfigParser.{h,cpp} (A-class, pure
// value logic). Line-for-line translation; the mpv v0.37 behavior notes from
// the C++ headers/comments are kept verbatim where they describe the parser
// contract.
//
// Parser for mpv's native configuration formats. Pure value logic with no
// mpv or GUI dependency, so it is unit-testable in isolation. This backs the
// mpv compatibility layer: scan the user's mpv config dir, map it into
// editable models, and re-apply it to libmpv at startup.

/// Data model for a parsed mpv.conf line (1.x struct MpvConfEntry).
enum MpvConfEntryKind {
  /// key=value
  option,

  /// [profile-name]
  profileHeader,

  /// anything else (kept for round-trip fidelity)
  unknown,
}

class MpvConfEntry {
  const MpvConfEntry({
    required this.kind,
    this.key = '',
    this.value = '',
    this.profileName = '',
    required this.lineNumber,
  });

  final MpvConfEntryKind kind;
  // option name (Option only)
  final String key;
  // option value, inline '#' preserved (Option only)
  final String value;
  // profile name (ProfileHeader only)
  final String profileName;
  // 1-based
  final int lineNumber;
}

/// Data model for a parsed input.conf binding (1.x struct MpvInputBinding).
class MpvInputBinding {
  const MpvInputBinding({
    required this.key,
    required this.command,
    required this.comment,
    required this.lineNumber,
  });

  // e.g. "Ctrl+p"
  final String key;

  // tokenized command words, quotes removed
  final List<String> command;

  // trailing comment without the '#'
  final String comment;

  // 1-based
  final int lineNumber;
}

class MpvConfigParser {
  MpvConfigParser._();

  // Split on '\n' and drop a single trailing '\r' per line (C++ splitLines:
  // CRLF files parse like LF files).
  static List<String> _splitLines(String text) {
    return [
      for (final line in text.split('\n'))
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
  }

  /// Parse mpv.conf content. mpv.conf has no inline comments: '#' only
  /// starts a comment at the beginning of a line, and may appear inside
  /// values (e.g. color codes), where it is preserved.
  static List<MpvConfEntry> parseMpvConf(String text) {
    final entries = <MpvConfEntry>[];
    final lines = _splitLines(text);

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      final lineNumber = i + 1;

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        entries.add(MpvConfEntry(
          kind: MpvConfEntryKind.profileHeader,
          profileName: trimmed.substring(1, trimmed.length - 1),
          lineNumber: lineNumber,
        ));
        continue;
      }

      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        entries.add(MpvConfEntry(
          kind: MpvConfEntryKind.option,
          key: trimmed.substring(0, eq).trim(),
          // Inline '#' is part of the value: mpv.conf has no inline comments.
          value: trimmed.substring(eq + 1).trim(),
          lineNumber: lineNumber,
        ));
      } else {
        // Missing '=': kept as Unknown (round-trip fidelity, 1.x behavior).
        entries.add(MpvConfEntry(
          kind: MpvConfEntryKind.unknown,
          lineNumber: lineNumber,
        ));
      }
    }
    return entries;
  }

  /// Parse input.conf content. Here '#' does start a comment when it is at
  /// the start of a line or preceded by whitespace.
  static List<MpvInputBinding> parseInputConf(String text) {
    final bindings = <MpvInputBinding>[];
    final lines = _splitLines(text);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      final lineNumber = i + 1;

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      // Find a '#' that starts a real comment: position 0 of the trimmed
      // line was handled above, so look for '#' preceded by whitespace.
      var commentStart = -1;
      for (var pos = trimmed.indexOf('#');
          pos >= 0;
          pos = trimmed.indexOf('#', pos + 1)) {
        if (pos == 0) {
          continue;
        }
        if (_isSpace(trimmed.codeUnitAt(pos - 1))) {
          commentStart = pos;
          break;
        }
      }

      var code = trimmed;
      var comment = '';
      if (commentStart >= 0) {
        code = trimmed.substring(0, commentStart).trim();
        comment = trimmed.substring(commentStart + 1).trim();
      }

      // 1.x splits on the literal space only (QString::indexOf(' ')); a
      // tab-separated line has no usable binding and is skipped the same way.
      final firstSpace = code.indexOf(' ');
      if (firstSpace < 0) {
        continue; // "key" alone has no command: not a usable binding
      }

      final command = tokenizeCommand(code.substring(firstSpace + 1).trim());
      if (command.isEmpty) {
        continue;
      }
      bindings.add(MpvInputBinding(
        key: code.substring(0, firstSpace),
        command: command,
        comment: comment,
        lineNumber: lineNumber,
      ));
    }
    return bindings;
  }

  /// Split a command string into tokens on whitespace, honoring double
  /// quotes for tokens containing spaces. An unterminated quote extends to
  /// the end of the string (lenient, matches practical usage).
  static List<String> tokenizeCommand(String command) {
    final tokens = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < command.length; i++) {
      final ch = command[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (_isSpace(command.codeUnitAt(i)) && !inQuotes) {
        if (current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
        }
      } else {
        current.write(ch);
      }
    }
    if (current.isNotEmpty) {
      tokens.add(current.toString());
    }
    return tokens;
  }

  // QChar::isSpace() for the characters this parser meets: ASCII whitespace
  // (space, tab, LF, VT, FF, CR) plus NBSP. Unicode exotic separators do not
  // occur in mpv's own config files, so the C++/Dart difference is moot.
  static bool _isSpace(int codeUnit) {
    const space = 0x20;
    const tab = 0x09;
    const cr = 0x0D;
    const nbsp = 0xA0;
    return codeUnit == space ||
        (codeUnit >= tab && codeUnit <= cr) ||
        codeUnit == nbsp;
  }
}
