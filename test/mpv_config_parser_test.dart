// Dart port of mpv-emo tests/test_config_parser.cpp (one C++ private slot =
// one test(); assertion values copied verbatim — they are the behavior spec).
import 'package:emoplay/mpv/config/mpv_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMpvConf', () {
    test('mpvConfBasicOptions', () {
      final entries = MpvConfigParser.parseMpvConf(
          'vo=gpu-next\nhwdec=auto-safe\nfullscreen=yes\n');

      expect(entries, hasLength(3));
      expect(entries[0].kind, MpvConfEntryKind.option);
      expect(entries[0].key, 'vo');
      expect(entries[0].value, 'gpu-next');
      expect(entries[0].lineNumber, 1);
      expect(entries[1].key, 'hwdec');
      expect(entries[1].value, 'auto-safe');
      expect(entries[2].key, 'fullscreen');
      expect(entries[2].value, 'yes');
      expect(entries[2].lineNumber, 3);
    });

    test('mpvConfCommentsAndBlanks', () {
      const text = '# leading comment\n\n   \n\tvolume=50\n  # indented comment\n';
      final entries = MpvConfigParser.parseMpvConf(text);

      expect(entries, hasLength(1));
      expect(entries[0].key, 'volume');
      expect(entries[0].value, '50');
      expect(entries[0].lineNumber, 4);
    });

    test('mpvConfProfiles', () {
      const text = '[fast]\nprofile-cond=get("video-bitrate") > 10000\nvo=gpu-next\n';
      final entries = MpvConfigParser.parseMpvConf(text);

      expect(entries, hasLength(3));
      expect(entries[0].kind, MpvConfEntryKind.profileHeader);
      expect(entries[0].profileName, 'fast');
      expect(entries[1].kind, MpvConfEntryKind.option);
    });

    test('mpvConfHashInsideValue', () {
      // mpv.conf has no inline comments: '#' inside a value is preserved.
      final entries = MpvConfigParser.parseMpvConf('background-color=#000000\n');

      expect(entries, hasLength(1));
      expect(entries[0].value, '#000000');
    });

    test('mpvConfMissingEquals', () {
      final entries = MpvConfigParser.parseMpvConf('not-an-option-line\n');

      expect(entries, hasLength(1));
      expect(entries[0].kind, MpvConfEntryKind.unknown);
    });

    test('mpvConfCrlfLineEndings', () {
      final entries = MpvConfigParser.parseMpvConf('vo=gpu-next\r\nvolume=80\r\n');

      expect(entries, hasLength(2));
      expect(entries[0].value, 'gpu-next');
      expect(entries[1].value, '80');
    });
  });

  group('parseInputConf', () {
    test('inputConfBasicBinding', () {
      final bindings = MpvConfigParser.parseInputConf('Space cycle pause\n');

      expect(bindings, hasLength(1));
      expect(bindings[0].key, 'Space');
      expect(bindings[0].command, ['cycle', 'pause']);
      expect(bindings[0].comment, '');
      expect(bindings[0].lineNumber, 1);
    });

    test('inputConfQuotedArgs', () {
      final bindings =
          MpvConfigParser.parseInputConf('a loadfile "my file.mkv"\n');

      expect(bindings, hasLength(1));
      expect(bindings[0].command, ['loadfile', 'my file.mkv']);
    });

    test('inputConfInlineComment', () {
      // '#' starts a comment when preceded by whitespace.
      final bindings =
          MpvConfigParser.parseInputConf('Ctrl+s screenshot # take a shot\n');

      expect(bindings, hasLength(1));
      expect(bindings[0].key, 'Ctrl+s');
      expect(bindings[0].command, ['screenshot']);
      expect(bindings[0].comment, 'take a shot');
    });

    test('inputConfHashWithoutSpaceIsPartOfToken', () {
      final bindings = MpvConfigParser.parseInputConf('a#b stop\n');

      expect(bindings, hasLength(1));
      expect(bindings[0].key, 'a#b');
      expect(bindings[0].command, ['stop']);
    });

    test('inputConfKeyOnlyLineIsSkipped', () {
      final bindings = MpvConfigParser.parseInputConf('x\n');
      expect(bindings, isEmpty);
    });
  });

  test('tokenizeEdgeCases', () {
    expect(MpvConfigParser.tokenizeCommand(''), isEmpty);
    expect(MpvConfigParser.tokenizeCommand('one'), ['one']);
    expect(MpvConfigParser.tokenizeCommand('  spaced   out  '),
        ['spaced', 'out']);
    expect(MpvConfigParser.tokenizeCommand('"quoted arg" tail'),
        ['quoted arg', 'tail']);
    // Unterminated quote extends to the end of the string.
    expect(MpvConfigParser.tokenizeCommand('"open arg'), ['open arg']);
  });

  test('emptyInputYieldsNothing', () {
    expect(MpvConfigParser.parseMpvConf(''), isEmpty);
    expect(MpvConfigParser.parseInputConf(''), isEmpty);
    expect(MpvConfigParser.parseMpvConf('\n\n# only comments\n'), isEmpty);
  });

  group('runtimeOptionValue', () {
    test('stripsWhitespacePrecededInlineComments', () {
      // Verbatim line shapes from a real user mpv.conf (2026-11-12
      // no-sound report): numeric/string options annotated with ` # `.
      expect(MpvConfigParser.runtimeOptionValue(
          'auto                     # 此项用于指定启动时的音频输出设备'),
          'auto');
      expect(MpvConfigParser.runtimeOptionValue(
          'auto-safe        # <默认值 auto-safe|auto|layouts|stereo>，如果双声道系统播放多声道影片时有的声道声音没出现，尝试强制设定为双声道'),
          'auto-safe');
      expect(MpvConfigParser.runtimeOptionValue(
          'float                     # 使用32位浮点音频格式，全功能版本支持更高精度的音频处理'),
          'float');
      expect(MpvConfigParser.runtimeOptionValue(
          '24 # 更改 OSD 字体大小（全局，影响多个功能显示的文本）（默认值：38）'),
          '24');
    });

    test('keepsColorHashGluedToValue', () {
      // '#F8F8F2' follows '=' directly: part of the value (color code),
      // only the whitespace-preceded trailing comment is stripped.
      expect(MpvConfigParser.runtimeOptionValue(
          '#F8F8F2 # Dracula Foreground，与 OSD 配色统一'),
          '#F8F8F2');
      expect(MpvConfigParser.runtimeOptionValue('#191A21'), '#191A21');
    });

    test('commentFreeValuesPassThroughTrimmed', () {
      expect(MpvConfigParser.runtimeOptionValue('auto'), 'auto');
      expect(MpvConfigParser.runtimeOptionValue('  gpu-next  '), 'gpu-next');
      expect(MpvConfigParser.runtimeOptionValue(''), '');
    });

    test('fullLineCommentsNeverReachHere', () {
      // parseMpvConf already drops full-line comments; the runtime value
      // helper only ever sees the value part after '='.
      final entries = MpvConfigParser.parseMpvConf(
          '# full comment\nvolume=50\n');
      expect(entries.single.value, '50');
      expect(MpvConfigParser.runtimeOptionValue(entries.single.value), '50');
    });
  });
}
