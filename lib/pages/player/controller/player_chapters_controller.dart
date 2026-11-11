import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

import 'package:emoplay/pages/player/controller/chapters_model.dart'
    show MediaChapter, parseMpvChapterList, resolveChapterTarget;
import 'package:emoplay/services/logging/logger.dart';

part 'player_chapters_controller.g.dart';

/// Chapter navigation state for the current playback (M3-T2 章节导航).
///
/// Owns the NativePlayer observation of mpv's `chapter-list` (the chapter
/// table) and `chapter` (the active chapter index, -1 when unavailable)
/// properties. The fork delivers both as strings (MPV_FORMAT_NONE observe ->
/// `readNativeString` dispatch, see chapters_model.dart) — the same channel
/// the resume seek uses for `playback-time`
/// (player_playback_controller.dart `_armResumeSeek`).
///
/// One instance lives on [PlayerController]; it is attached to each freshly
/// created player after `open` (an mpv observation always fires an initial
/// event, so attaching post-load still receives the table) and detached in
/// the shared release path.
class PlayerChaptersController = _PlayerChaptersController
    with _$PlayerChaptersController;

abstract class _PlayerChaptersController with Store {
  _PlayerChaptersController({
    required Future<void> Function(Duration) seek,
    required Duration Function() position,
  })  : _seek = seek,
        _position = position;

  final Future<void> Function(Duration) _seek;
  final Duration Function() _position;

  NativePlayer? _platform;

  /// Chapters of the current media; empty while the media has none (files
  /// without chapters simply hide the panel section).
  @observable
  List<MediaChapter> chapters = const [];

  /// mpv's `chapter` property: 0-based active chapter, or -1 when it is not
  /// available (no file / property not valid).
  @observable
  int currentIndex = -1;

  @computed
  bool get hasChapters => chapters.isNotEmpty;

  @computed
  MediaChapter? get currentChapter =>
      currentIndex >= 0 && currentIndex < chapters.length
          ? chapters[currentIndex]
          : null;

  @action
  void _setChapters(List<MediaChapter> value) => chapters = value;

  @action
  void _setCurrentIndex(int value) => currentIndex = value;

  /// Starts observing on [player] (idempotent: re-attach first detaches).
  Future<void> attach(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    await detach();
    _platform = platform;
    try {
      await platform.observeProperty(
        'chapter-list',
        _onChapterListChanged,
        waitForInitialization: false,
      );
      await platform.observeProperty(
        'chapter',
        _onChapterChanged,
        waitForInitialization: false,
      );
    } catch (e) {
      EmoLogger().w(
        'PlayerChaptersController: failed to observe chapter properties',
        error: e,
      );
    }
  }

  /// Stops observing and clears state. Safe to call repeatedly and after the
  /// player has already been disposed (the unobserve calls are guarded).
  Future<void> detach() async {
    final platform = _platform;
    _platform = null;
    _setChapters(const []);
    _setCurrentIndex(-1);
    if (platform == null) {
      return;
    }
    for (final property in const ['chapter-list', 'chapter']) {
      try {
        await platform.unobserveProperty(property);
      } catch (_) {
        // Already unobserved or the player is gone — nothing left to clean.
      }
    }
  }

  Future<void> _onChapterListChanged(String value) async {
    // Events can still be in flight right after detach; only an attached
    // player may update the store.
    if (_platform == null) {
      return;
    }
    _setChapters(parseMpvChapterList(value));
  }

  Future<void> _onChapterChanged(String value) async {
    if (_platform == null) {
      return;
    }
    final index = int.tryParse(value.trim()) ?? -1;
    _setCurrentIndex(index);
  }

  /// Jumps to the start of [index]: writes mpv's `chapter` property.
  ///
  /// Why not a plain seek to the chapter start: probed 2026-11-11 against the
  /// shipped libmpv — `seek <start>` lands 23µs short of the boundary
  /// (playback-time 5.999977 for a chapter starting at 6.0) and mpv then
  /// keeps reporting the PREVIOUS chapter, so a seek-jump would highlight the
  /// wrong chapter after every click. Writing the `chapter` property is
  /// mpv's native chapter seek (the same channel Haruna/Celluloid drive):
  /// it lands on the chapter start and reports exactly the target chapter.
  /// No-op without chapters, out of range, or without an attached player.
  Future<void> jumpToChapter(int index) async {
    if (index < 0 || index >= chapters.length) {
      return;
    }
    final platform = _platform;
    if (platform == null) {
      return;
    }
    try {
      await platform.setProperty('chapter', '$index');
    } catch (e) {
      EmoLogger().w(
        'PlayerChaptersController: chapter property write failed, '
        'falling back to a plain seek',
        error: e,
      );
      await _seek(chapters[index].startTime);
    }
  }

  /// Seeks to the start of the chapter after the active one (clamped at the
  /// last chapter). Falls back to the position lookup when mpv's `chapter`
  /// property has not reported yet.
  Future<void> nextChapter() => _stepBy(1);

  /// Seeks to the start of the chapter before the active one (clamped at the
  /// first chapter).
  Future<void> previousChapter() => _stepBy(-1);

  Future<void> _stepBy(int delta) async {
    final target = resolveChapterTarget(
      chapters: chapters,
      currentIndex: currentIndex,
      position: _position(),
      delta: delta,
    );
    if (target == null) {
      return;
    }
    await jumpToChapter(target);
  }
}
