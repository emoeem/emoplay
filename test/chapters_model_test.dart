import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/pages/player/controller/chapters_model.dart';
import 'package:emoplay/pages/player/controller/player_chapters_controller.dart';

// Pure-logic tests for the M3-T2 chapter navigation model: mpv chapter-list
// string parsing (JSON shape probed on the shipped libmpv 0.41, see
// chapters_model.dart), the upper-bound binary search for the active chapter,
// and the jump/next/previous clamping rules of the controller (no engine).
//
// The libmpv-driving cases live in chapters_live_test.dart (equalizer_test
// live mode: a real idle core opened onto an ffmpeg-built 3-chapter mp4).
void main() {
  // Exact string observed 2026-11-11 via NativePlayer observeProperty on
  // "mpv v0.41.0-11-gf011d73d5-dirty" for a 3-chapter mp4 (the live test
  // rebuilds the same fixture).
  const probedThreeChapters =
      '[{"title":"第一章 开场","time":0.000000},'
      '{"title":"Second, Chapter & %50%","time":3.000000},'
      '{"title":"Chapter [3]","time":6.000000}]';

  test('parseMpvChapterList: probed three-chapter JSON', () {
    final chapters = parseMpvChapterList(probedThreeChapters);
    expect(chapters, hasLength(3));
    expect(chapters[0].title, '第一章 开场');
    expect(chapters[0].startTime, Duration.zero);
    // End of a chapter is the start of the next one.
    expect(chapters[0].endTime, const Duration(seconds: 3));
    expect(chapters[1].title, 'Second, Chapter & %50%');
    expect(chapters[1].startTime, const Duration(seconds: 3));
    expect(chapters[1].endTime, const Duration(seconds: 6));
    expect(chapters[2].title, 'Chapter [3]');
    expect(chapters[2].startTime, const Duration(seconds: 6));
    // The last chapter runs until the media ends.
    expect(chapters[2].endTime, isNull);
  });

  test('parseMpvChapterList: empty table for a chapterless file', () {
    expect(parseMpvChapterList('[]'), isEmpty);
    expect(parseMpvChapterList(''), isEmpty);
  });

  test('parseMpvChapterList: non-JSON degrades to empty (no throw)', () {
    // Older mpv builds printed node lists in the %len% option escaping; that
    // shape must never crash the observer — it just yields no chapters.
    expect(parseMpvChapterList('[{title=%12%Chapter One,time=0.000}]'),
        isEmpty);
    expect(parseMpvChapterList('not a chapter table at all'), isEmpty);
  });

  test('parseMpvChapterList: malformed entries are skipped, not fatal', () {
    final chapters = parseMpvChapterList(
      '[{"title":"no time"},'
      '"a plain string entry",'
      '{"time":12.5},'
      '{"title":"fine","time":30}]',
    );
    expect(chapters, hasLength(2));
    expect(chapters[0].title, '');
    expect(chapters[0].startTime, const Duration(seconds: 12, milliseconds: 500));
    expect(chapters[0].endTime, const Duration(seconds: 30));
    expect(chapters[1].title, 'fine');
    expect(chapters[1].endTime, isNull);
  });

  test('parseMpvChapterList: integer times and JSON-escaped titles', () {
    final chapters = parseMpvChapterList(
        '[{"title":"quote \\" inside","time":0},{"title":"后","time":10}]');
    expect(chapters[0].title, 'quote " inside');
    expect(chapters[0].startTime, Duration.zero);
    expect(chapters[1].startTime, const Duration(seconds: 10));
  });

  test('chapterIndexAt: empty table', () {
    expect(chapterIndexAt(const [], Duration.zero), -1);
  });

  test('chapterIndexAt: single chapter covering everything', () {
    final chapters = parseMpvChapterList('[{"title":"all","time":0}]');
    expect(chapterIndexAt(chapters, Duration.zero), 0);
    expect(chapterIndexAt(chapters, const Duration(hours: 2)), 0);
    // Before the first chapter start: -1.
    expect(chapterIndexAt(chapters, const Duration(milliseconds: -1)), -1);
  });

  test('chapterIndexAt: first chapter not at zero', () {
    final chapters = parseMpvChapterList(
        '[{"title":"intro","time":5},{"title":"main","time":10}]');
    expect(chapterIndexAt(chapters, const Duration(seconds: 4, milliseconds: 999)), -1);
    expect(chapterIndexAt(chapters, const Duration(seconds: 5)), 0);
    expect(chapterIndexAt(chapters, const Duration(seconds: 9)), 0);
    expect(chapterIndexAt(chapters, const Duration(seconds: 10)), 1);
  });

  test('chapterIndexAt: binary search hits exact boundaries', () {
    final chapters = parseMpvChapterList(
      '[{"title":"a","time":0},'
      '{"title":"b","time":60},'
      '{"title":"c","time":120},'
      '{"title":"d","time":180},'
      '{"title":"e","time":240}]',
    );
    for (var i = 0; i < chapters.length; i++) {
      expect(chapterIndexAt(chapters, chapters[i].startTime), i,
          reason: 'exact start of chapter $i must select chapter $i');
    }
    expect(chapterIndexAt(chapters, const Duration(seconds: 59)), 0);
    expect(chapterIndexAt(chapters, const Duration(minutes: 3, seconds: 1)), 3);
    // Past the last start stays on the last chapter (no upper bound).
    expect(chapterIndexAt(chapters, const Duration(hours: 1)), 4);
  });

  test('chapterIndexAt: double rounding at the millisecond boundary', () {
    final chapters = parseMpvChapterList(
        '[{"title":"a","time":0},{"title":"b","time":2.9999999}]');
    expect(
      chapterIndexAt(chapters, const Duration(milliseconds: 3000)),
      1,
      reason: 'mpv 2.9999999 rounds to a 3000ms Duration; an exact hit counts',
    );
  });

  /// Builds the real controller for the observable-accessor surface; the
  /// mpv-facing jump mechanics are exercised by chapters_live_test.dart
  /// (a chapter-property write cannot be meaningfully stubbed here).
  PlayerChaptersController makeController({
    required List<MediaChapter> chapters,
    required Duration position,
  }) {
    final controller = PlayerChaptersController(
      seek: (_) async {},
      position: () => position,
    );
    controller.chapters = chapters;
    return controller;
  }

  test('current chapter accessors', () {
    final controller = makeController(
      chapters: parseMpvChapterList(probedThreeChapters),
      position: Duration.zero,
    );
    expect(controller.hasChapters, isTrue);
    expect(controller.currentChapter, isNull);
    controller.currentIndex = 2;
    expect(controller.currentChapter!.title, 'Chapter [3]');
    expect(controller.currentChapter!.endTime, isNull);

    final empty = makeController(chapters: const [], position: Duration.zero);
    expect(empty.hasChapters, isFalse);
    expect(empty.currentChapter, isNull);
  });

  test('resolveChapterTarget: steps from the mpv-reported index', () {
    final chapters = parseMpvChapterList(probedThreeChapters);
    int? step(int from, int delta) => resolveChapterTarget(
          chapters: chapters,
          currentIndex: from,
          position: Duration.zero,
          delta: delta,
        );
    expect(step(0, 1), 1);
    expect(step(1, 1), 2);
    // Clamped at the last chapter.
    expect(step(2, 1), isNull);
    expect(step(1, -1), 0);
    // Clamped at the first chapter.
    expect(step(0, -1), isNull);
  });

  test('resolveChapterTarget: falls back to the position lookup at index -1',
      () {
    final chapters = parseMpvChapterList(probedThreeChapters);
    int? stepAt(Duration position, int delta) => resolveChapterTarget(
          chapters: chapters,
          currentIndex: -1,
          position: position,
          delta: delta,
        );
    // t=4s sits in chapter 1 (3s..6s).
    expect(stepAt(const Duration(seconds: 4), 1), 2);
    expect(stepAt(const Duration(seconds: 4), -1), 0);
    // Position in chapter 0 (its start is 0): next enters chapter 1,
    // previous has nowhere to go.
    expect(stepAt(Duration.zero, 1), 1);
    expect(stepAt(Duration.zero, -1), isNull);
  });

  test('resolveChapterTarget: no chapters is always a no-op', () {
    expect(
      resolveChapterTarget(
        chapters: const [],
        currentIndex: 0,
        position: Duration.zero,
        delta: 1,
      ),
      isNull,
    );
    expect(
      resolveChapterTarget(
        chapters: const [],
        currentIndex: -1,
        position: Duration.zero,
        delta: -1,
      ),
      isNull,
    );
  });
}
