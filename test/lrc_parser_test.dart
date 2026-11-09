import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/music/lrc_parser.dart';

// Pure-logic tests for the .lrc parser: no mpv, no GUI, no real HOME.
//
// Case-for-case port of mpv-emo tests/test_lrc_parser.cpp; assertion values
// are the behavioural contract and are copied verbatim.
void main() {
  test('basicTimestamps', () {
    final data = LrcParser.parse('[00:12.00]first\n[01:05]second\n');
    expect(data.lines.length, 2);
    expect(data.lines[0].time, 12.0);
    expect(data.lines[0].text, 'first');
    expect(data.lines[1].time, 65.0);
    expect(data.lines[1].text, 'second');
  });

  test('multiTimestampLine', () {
    final data = LrcParser.parse('[00:12.00][00:45.50]chorus\n');
    expect(data.lines.length, 2);
    expect(data.lines[0].time, 12.0);
    expect(data.lines[1].time, 45.5);
    expect(data.lines[0].text, 'chorus');
    expect(data.lines[1].text, 'chorus');
  });

  test('metadataTags', () {
    final data = LrcParser.parse(
        '[ti:Song Title]\n[ar:The Artist]\n[al:The Album]\n[00:01.00]line\n');
    expect(data.title, 'Song Title');
    expect(data.artist, 'The Artist');
    expect(data.album, 'The Album');
    expect(data.lines.length, 1);
  });

  test('bomStripped', () {
    // UTF-8 BOM decoded to U+FEFF before the first tag.
    final data = LrcParser.parse('\uFEFF[ti:T]\n[00:01.00]line\n');
    expect(data.title, 'T');
    expect(data.lines.length, 1);
    expect(data.lines[0].text, 'line');
  });

  test('crlfLineEndings', () {
    final data =
        LrcParser.parse('[ti:T]\r\n[00:01.00]one\r\n[00:02.00]two\r\n');
    expect(data.title, 'T');
    expect(data.lines.length, 2);
    // The \r must not leak into the text.
    expect(data.lines[0].text, 'one');
    expect(data.lines[1].text, 'two');
  });

  test('fractionDigitVariants', () {
    final data = LrcParser.parse(
        '[00:01.5]a\n[00:02.25]b\n[00:03.250]c\n[00:04]d\n');
    expect(data.lines.length, 4);
    expect(data.lines[0].time, 1.5);
    expect(data.lines[1].time, 2.25);
    expect(data.lines[2].time, 3.25);
    expect(data.lines[3].time, 4.0);
  });

  test('unsortedInputSortedByTime', () {
    final data = LrcParser.parse('[00:20.00]later\n[00:10.00]earlier\n');
    expect(data.lines.length, 2);
    expect(data.lines[0].text, 'earlier');
    expect(data.lines[1].text, 'later');
  });

  test('unknownTagsAndPlainLinesIgnored', () {
    final data = LrcParser.parse(
        '[by:Tool]\n[offset:+500]\njust some text\n\n[00:01.00]real\n');
    expect(data.lines.length, 1);
    expect(data.lines[0].text, 'real');
    expect(data.title, isEmpty);
  });

  test('emptyTextLinesKept', () {
    // Timestamp-only lines are common interlude markers; they stay.
    final data = LrcParser.parse('[00:05.00]\n[00:10.00]after\n');
    expect(data.lines.length, 2);
    expect(data.lines[0].text, '');
    expect(data.lines[0].time, 5.0);
    expect(data.lines[1].text, 'after');
  });

  test('parseFileMissingReturnsEmpty', () {
    final dir = Directory.systemTemp.createTempSync('emoplay-lrc-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final data = LrcParser.parseFile('${dir.path}/missing.lrc');
    expect(data.lines, isEmpty);
    expect(data.title, isEmpty);
  });

  test('lrcCandidates', () {
    final candidates = LrcParser.lrcCandidates('/music/artist/song.mp3');
    expect(candidates.length, 2);
    expect(candidates[0], '/music/artist/song.lrc');
    expect(candidates[1], '/music/artist/song.LRC');
    // Multi-part extensions: only the last one is replaced.
    expect(LrcParser.lrcCandidates('/m/a.b.flac')[0], '/m/a.b.lrc');
    expect(LrcParser.lrcCandidates(''), isEmpty);
  });
}
