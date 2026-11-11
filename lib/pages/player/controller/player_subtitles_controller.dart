import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/pages/player/controller/player_subtitles_model.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/utils/async_serial_queue.dart';

part 'player_subtitles_controller.g.dart';

/// Subtitle-track state for the current playback (M3 字幕管理).
///
/// Owns the NativePlayer subscription of the fork's parsed `track-list`
/// ([Player.stream.tracks]) plus the observation of mpv's `sid` property —
/// the selection truth. `Player.state.track.subtitle` is NOT used: the fork
/// only updates it inside [Player.setSubtitleTrack], so a selection made
/// through the raw `sub-add` command (the external-subtitle loader below)
/// leaves it stale (probed 2026-11-11 against the shipped fork,
/// "mpv v0.41.0-11-gf011d73d5-dirty": sub-add select reports sid=1 while
/// state.track.subtitle stays 'auto'). mpv's `sid` tracks every path:
/// 'no' after disabling, the track id after any explicit selection, and the
/// fork pre-inits it to 'no' (same probe).
///
/// One instance lives on [PlayerController]; it attaches to each freshly
/// created player after `open` (same order as the chapters controller — the
/// state snapshot covers events fired before attach, the stream covers the
/// rest) and detaches in the shared release path.
class PlayerSubtitlesController = _PlayerSubtitlesController
    with _$PlayerSubtitlesController;

abstract class _PlayerSubtitlesController with Store {
  NativePlayer? _platform;
  StreamSubscription<Tracks>? _tracksSubscription;
  final AsyncSerialQueue _delayWrites = AsyncSerialQueue();

  /// mpv `sub-add` flags (mpv manual #sub-add): `select` loads the external
  /// subtitle AND activates it, `auto` loads it and leaves the selection to
  /// mpv's normal track selection.
  static const String subAddFlagSelect = 'select';
  static const String subAddFlagAuto = 'auto';

  /// Subtitle tracks of the current media, mpv `track-list` order. The
  /// fork's synthetic 'auto'/'no' entries (its empty-state defaults) are
  /// filtered out; the panel renders its own 关闭字幕 row instead.
  @observable
  List<SubtitleTrack> tracks = const [];

  /// mpv's `sid`: 'no' = subtitles disabled, 'auto'/'' = no explicit
  /// selection (mpv's auto pick may still be playing), otherwise the id of
  /// the selected track.
  @observable
  String currentSubId = 'no';

  /// Current `sub-delay` in seconds (+ = subtitles show later). Mirrors the
  /// engine for the HUD; the engine stays the source of truth.
  @observable
  double subDelay = 0;

  @computed
  bool get hasTracks => tracks.isNotEmpty;

  /// The track matching [currentSubId], or null when disabled/auto.
  @computed
  SubtitleTrack? get currentTrack {
    for (final track in tracks) {
      if (track.id == currentSubId) {
        return track;
      }
    }
    return null;
  }

  @action
  void _setTracks(List<SubtitleTrack> value) => tracks = value;

  @action
  void _setCurrentSubId(String value) => currentSubId = value;

  @action
  void _setSubDelay(double value) => subDelay = value;

  /// Starts observing on [player] (idempotent: re-attach first detaches).
  Future<void> attach(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    await detach();
    _platform = platform;
    _tracksSubscription = player.stream.tracks.listen(_onTracksChanged);
    try {
      await platform.observeProperty(
        'sid',
        _onSidChanged,
        waitForInitialization: false,
      );
    } catch (e) {
      EmoLogger().w(
        'PlayerSubtitlesController: failed to observe sid',
        error: e,
      );
    }
    // The track-list event may have fired before this attach (attach happens
    // after open); the fork keeps the parsed list in its state, so snapshot
    // it. Later updates arrive through the stream above.
    _onTracksChanged(player.state.tracks);
    // sid is pre-initialized by the fork ('no') and by stock mpv ('auto');
    // reading it back covers a media that auto-selected nothing yet.
    try {
      final sid =
          await platform.getProperty('sid', waitForInitialization: false);
      _setCurrentSubId(_normalizeSid(sid));
      final delay = await platform
          .getProperty('sub-delay', waitForInitialization: false);
      _setSubDelay(double.tryParse(delay.trim()) ?? 0);
    } catch (e) {
      EmoLogger().w(
        'PlayerSubtitlesController: failed to read initial subtitle state',
        error: e,
      );
    }
  }

  /// Stops observing and clears state. Safe to call repeatedly and after the
  /// player has already been disposed.
  Future<void> detach() async {
    await _tracksSubscription?.cancel();
    _tracksSubscription = null;
    final platform = _platform;
    _platform = null;
    if (platform != null) {
      try {
        await platform.unobserveProperty('sid');
      } catch (_) {
        // Already unobserved or the player is gone — nothing left to clean.
      }
    }
    _setTracks(const []);
    _setCurrentSubId('no');
    _setSubDelay(0);
  }

  void _onTracksChanged(Tracks value) {
    // Events can still be in flight right after detach; only an attached
    // player may update the store.
    if (_platform == null) {
      return;
    }
    _setTracks(List.unmodifiable(
      value.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ));
  }

  Future<void> _onSidChanged(String value) async {
    if (_platform == null) {
      return;
    }
    _setCurrentSubId(_normalizeSid(value));
  }

  /// mpv delivers property values as native strings; trim whitespace and
  /// treat an unavailable value ('') as 'no' (no subtitles displayed).
  String _normalizeSid(String raw) {
    final value = raw.trim();
    return value.isEmpty ? 'no' : value;
  }

  /// Loads an external subtitle file (srt/ass/ssa/vtt/sub) into the current
  /// media via mpv's `sub-add` command.
  ///
  /// Ported from mpv-emo `PlaybackController::addSubtitle`
  /// (src/mpv/PlaybackController.cpp:233), extended with the mpv manual's
  /// flag set: [select] = `select` (load AND activate, the picker/drop
  /// semantics) vs `auto` (load, let mpv decide). The track title is passed
  /// explicitly so the switching panel shows the file name regardless of how
  /// mpv titles external tracks. No-op without a live player or an empty
  /// path; a failing command (e.g. no media loaded) propagates to the caller.
  Future<void> loadExternal(String path, {bool select = true}) async {
    if (path.isEmpty) {
      return;
    }
    final platform = _platform;
    if (platform == null) {
      return;
    }
    final normalised = MediaClassifier.normalise(path);
    await platform.command([
      'sub-add',
      normalised,
      select ? subAddFlagSelect : subAddFlagAuto,
      MediaClassifier.fileNameOf(normalised),
    ]);
  }

  /// Selects a subtitle track from [tracks] (mpv writes `sid`, the fork's
  /// [Player.setSubtitleTrack] for external uri/data tracks falls back to
  /// its own sub-add path). No-op without a live player.
  Future<void> select(SubtitleTrack track) async {
    final platform = _platform;
    if (platform == null) {
      return;
    }
    try {
      await platform.setSubtitleTrack(track);
    } catch (e) {
      EmoLogger().w(
        'PlayerSubtitlesController: failed to select subtitle track',
        error: e,
      );
    }
  }

  /// Disables subtitle display (mpv `sid=no`).
  Future<void> selectNone() => select(const SubtitleTrack('no', null, null));

  /// Steps `sub-delay` by ±[kSubDelayStep] seconds ([direction] +1/-1).
  ///
  /// Reads the property fresh each step (the engine is the source of truth —
  /// the value may have been set by an earlier session of this controller or
  /// by a startup preset), computes the next value with the pure
  /// [nextSubDelay] rule and writes it back. Writes are serialized so rapid
  /// key presses cannot reorder read-modify-write pairs; the observable is
  /// updated with the written value for the HUD.
  ///
  /// Returns whether the step reached the engine (false without a live
  /// player or on a failed property write) so the UI can suppress the HUD
  /// feedback for no-ops.
  Future<bool> adjustSubDelay(int direction) async {
    final platform = _platform;
    if (platform == null || direction == 0) {
      return false;
    }
    return _delayWrites.run(() async {
      try {
        final raw = await platform
            .getProperty('sub-delay', waitForInitialization: false);
        final current = double.tryParse(raw.trim()) ?? subDelay;
        final next = nextSubDelay(current, direction);
        await platform.setProperty('sub-delay', '$next');
        _setSubDelay(next);
        return true;
      } catch (e) {
        EmoLogger().w(
          'PlayerSubtitlesController: failed to adjust sub-delay',
          error: e,
        );
        return false;
      }
    });
  }
}
