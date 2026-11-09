// Dart port of mpv-emo src/music/MusicController.{h,cpp} engine glue
// (B-class: QObject signals → ChangeNotifier + media_kit streams; the pure
// decision/EQ functions it called live in music/equalizer.dart).
//
// Music-mode service (P7 v1). Patterned after HistoryStore/QualityController:
// a passive ChangeNotifier driven by engine streams plus on-demand property
// reads (docs/architecture.md decision 7 — no cached play state). Owns no
// mpv state of its own: it decides when the player is effectively a music
// player, resolves/parses the .lrc next to the audio file, mirrors the
// current lyric line from position updates, and manages the 10-band
// equalizer (mpv af chain).
//
// Responsibilities:
//
//   - audio detection: the current media is "music mode" material when the
//     track-list has no video track AND the media filename has an audio
//     extension. Pure rules in equalizer.dart isAudioMedia()/isAudioExtension()
//     so the tests run without an engine. Cover art attached to audio files
//     shows up as a video track with the "albumart" flag (mpv 0.37 input.rst
//     track-list/N/albumart, MPV_FORMAT_FLAG) — those tracks do NOT
//     disqualify, or every mp3/flac with an embedded cover would be
//     classified as video.
//   - lyrics: resolves the same-name .lrc next to the audio file
//     (LrcParser.lrcCandidates), parses it and exposes the lines plus the
//     current line index, recomputed on each position update from the engine.
//   - equalizer v1: 10 fixed bands -> mpv's af option as a chain of peaking
//     "equalizer" filters; built-in presets plus user values persisted in
//     settings.json's "music" section (equalizerEnabled/equalizerPreset/
//     equalizerGains).
//
// 2.0 lifetime adaptation (same as the M6 quality controllers): 1.x held
// ONE engine for the whole app session; the 2.0 player bootstrap creates a
// media_kit Player per file, so [attachPlayer]/[detachPlayer] drive the
// session and the one-shot [startup] happens on the first attach.
//
// af sole-manager semantics, narrowed for 2.0: 1.x wrote af as a WHOLE-chain
// replacement (documented limitation: an af imported from the user's
// mpv.conf is clobbered while the EQ is enabled). The 2.0 player bootstrap
// additionally mounts `scaletempo2=max-speed=8` on every player (speed
// pitch preservation, Kazumi behavior), so the writes here compose the
// equalizer chain BEHIND that baseline instead of dropping it: enabled ->
// baseline + chain (baseline alone when the chain is inert), disabled-after-
// enabled -> baseline. The inert-when-never-enabled rule is unchanged: a
// session that never engages the EQ never touches af at all.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/lrc_parser.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

/// The af value the 2.0 player bootstrap mounts for speed pitch preservation
/// (player_playback_controller.dart). Single source of truth for the music
/// controller's composed writes.
const String kPlaybackAfBaseline = 'scaletempo2=max-speed=8';

class MusicController extends ChangeNotifier {
  /// [settings] must outlive this controller; null (tests) keeps every
  /// mutation in memory only, exactly like the 1.x null-AppSettings path.
  MusicController({EmoPlaySettings? settings, void Function(String)? onError})
      : _settings = settings,
        _onError = onError {
    _loadPersistedEqualizer();
  }

  final EmoPlaySettings? _settings;
  final void Function(String)? _onError;

  Player? _player;
  NativePlayer? get _platform {
    final player = _player;
    if (player == null) {
      return null;
    }
    return player.platform is NativePlayer
        ? player.platform as NativePlayer
        : null;
  }

  final List<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>[];
  // Properties observed through NativePlayer.observeProperty (throws on a
  // duplicate observation, so each is registered at most once per player and
  // unobserved on detach).
  final List<String> _observedProperties = <String>[];

  bool _audioMode = false;
  List<LrcLine> _lines = const <LrcLine>[];
  List<Map<String, Object?>> _lyrics = const <Map<String, Object?>>[];
  int _lyricIndex = -1;
  Map<String, String> _lrcMetadata = const <String, String>{};
  // The .lrc currently parsed and exposed (first existing candidate of the
  // playing file); repeated reevaluate() runs skip re-parsing it.
  String _lrcPath = '';
  Map<String, String> _mediaMetadata = const <String, String>{};
  // mpv's media-title, mirrored for the music page header (1.x read it
  // straight off MpvItem; media_kit exposes no equivalent field).
  String _mediaTitle = '';

  bool _equalizerEnabled = false;
  String _equalizerPreset = 'flat';
  List<double> _gains = List<double>.filled(kBandCount, 0.0);
  // True while this controller owns the af write (enabled at least once in
  // the current session) — the disable path may only restore the baseline
  // when it actually mounted something.
  bool _mountedAf = false;
  bool _startupDone = false;

  // True while the current media is pure audio; the player page shows the
  // music overlay when this is set.
  bool get audioMode => _audioMode;

  /// Parsed lyrics as [{time: double seconds, text: String}]; empty when
  /// none loaded (no .lrc next to the file, or not audio).
  List<Map<String, Object?>> get lyrics => _lyrics;

  /// Index of the line at the current position; -1 before the first line.
  int get lyricIndex => _lyricIndex;

  /// [ti]/[ar]/[al] values of the loaded .lrc (missing keys absent).
  Map<String, String> get lrcMetadata => _lrcMetadata;

  /// Relay of mpv's "metadata" property (fallback artist/album display when
  /// the .lrc has no tags).
  Map<String, String> get mediaMetadata => _mediaMetadata;

  /// mpv's media-title for the music page header.
  String get mediaTitle => _mediaTitle;

  bool get equalizerEnabled => _equalizerEnabled;

  /// "flat"/"bass"/"vocal"/"live", or "custom" once the user moved a band.
  String get equalizerPreset => _equalizerPreset;

  /// 10 per-band gains in dB, clamped to ±12.
  List<double> get equalizerGains => List<double>.unmodifiable(_gains);

  /// Constants for the pages (1.x bandCount/maxGain properties).
  static int get bandCount => kBandCount;
  static double get maxGain => kMaxGain;

  // ---- session wiring --------------------------------------------------------

  /// Attaches the per-file player (the 1.x constructor's engine connects).
  Future<void> attachPlayer(Player player) async {
    await detachPlayer();
    _player = player;
    _startupDone = false;
    final platform = _platform;
    if (platform == null) {
      return;
    }
    // The 1.x connects: fileLoaded / idleActiveChanged / trackListChanged →
    // reevaluate; positionChanged → onPositionChanged; metadataChanged →
    // onMetadataChanged. media_kit offers playlist/track/position streams;
    // 'metadata' and 'path' have no stream counterpart and are handled by
    // observation / on-demand reads (see _onMetadataPropertyChanged).
    _subscriptions.add(player.stream.playlist.listen((_) => reevaluate()));
    _subscriptions.add(player.stream.track.listen((_) => reevaluate()));
    _subscriptions.add(player.stream.position.listen((position) =>
        _onPositionChanged(position.inMilliseconds / 1000.0)));
    await _observe(platform, 'metadata', _onMetadataPropertyChanged);
  }

  Future<void> _observe(
    NativePlayer platform,
    String property,
    Future<void> Function(String value) listener,
  ) async {
    try {
      await platform.observeProperty(property, listener);
      _observedProperties.add(property);
    } catch (e) {
      // A property missing from this libmpv build only degrades the
      // corresponding 1.x signal to "never fires".
      EmoLogger().w('music: cannot observe $property', error: e);
    }
  }

  // The shipped libmpv prints the metadata node map as JSON
  // (empirical probe, build/native_assets/linux/libmpv.so.2 "mpv
  // v0.41.0-11-gf011d73d5-dirty", probed 2026-11-10):
  //   {"title":"Probe Song","artist":"Probe Artist",...}
  // Parse it into the 1.x metadata-map relay; anything unparsable keeps the
  // previous map (the .lrc tags stay the primary source anyway).
  Future<void> _onMetadataPropertyChanged(String value) async {
    if (value.isEmpty) {
      _onMetadataChanged(const <String, String>{});
      return;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        _onMetadataChanged(<String, String>{
          for (final entry in decoded.entries)
            if (entry.value is String)
              entry.key.toString(): entry.value as String,
        });
      }
    } catch (_) {
      // Not JSON (future mpv print-form change): degrade to an empty relay
      // rather than showing garbage.
      _onMetadataChanged(const <String, String>{});
    }
  }

  /// Detaches the engine when playback ends.
  Future<void> detachPlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final platform = _platform;
    for (final property in _observedProperties) {
      try {
        await platform?.unobserveProperty(property);
      } catch (_) {}
    }
    _observedProperties.clear();
    _player = null;
    _startupDone = false;
    setAudioMode(false);
    _clearLyrics();
    if (_mediaTitle.isNotEmpty) {
      _mediaTitle = '';
      notifyListeners();
    }
  }

  /// Startup seeding: mount the persisted EQ chain when it was enabled
  /// (never touches af when disabled — imported options stay untouched).
  Future<void> startup() async {
    if (_startupDone) {
      return;
    }
    _startupDone = true;
    if (_equalizerEnabled) {
      await _applyEqualizerToEngine();
    }
  }

  // ---- evaluation --------------------------------------------------------------

  /// Re-runs detection + lyric resolution for the current media.
  Future<void> reevaluate() async {
    final platform = _platform;
    if (platform == null) {
      setAudioMode(false);
      _clearLyrics();
      return;
    }

    final tracks = _trackList();
    final path = await _localMediaPath(platform);
    final audio = isAudioMedia(tracks, path);
    setAudioMode(audio);

    final title = await _readProperty(platform, 'media-title');
    if (_mediaTitle != title) {
      _mediaTitle = title;
      notifyListeners();
    }

    if (audio) {
      await _loadLyrics(path);
    } else {
      _clearLyrics();
    }
  }

  // player.state.tracks → the [{type, albumart?}] shapes the pure
  // isAudioMedia() rule consumes.
  List<Map<String, Object?>> _trackList() {
    final player = _player;
    if (player == null) {
      return const [];
    }
    final tracks = player.state.tracks;
    return <Map<String, Object?>>[
      for (final track in tracks.video)
        <String, Object?>{
          'type': 'video',
          'albumart': track.albumart == true,
        },
      for (final _ in tracks.audio) <String, Object?>{'type': 'audio'},
      for (final _ in tracks.subtitle) <String, Object?>{'type': 'sub'},
    ];
  }

  // getProperty("path") returns a local path for files and a URL string for
  // network streams; normalize file:// the same way as the 1.x toMediaPath.
  Future<String> _localMediaPath(NativePlayer platform) async {
    String raw;
    try {
      raw = await platform.getProperty('path');
    } catch (e) {
      EmoLogger().w('music: cannot read path', error: e);
      return '';
    }
    if (raw.startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  void setAudioMode(bool mode) {
    if (_audioMode == mode) {
      return;
    }
    _audioMode = mode;
    notifyListeners();
  }

  Future<void> _loadLyrics(String path) async {
    final platform = _platform;
    final position =
        platform == null ? 0.0 : await _readPosition(platform);
    for (final candidate in LrcParser.lrcCandidates(path)) {
      if (!File(candidate).existsSync()) {
        continue;
      }
      if (candidate == _lrcPath) {
        // Already parsed and exposed (track-list updates re-run reevaluate()
        // several times per file while mpv probes). Rebuilding the exposed
        // list would reset the scrolling ListView and drop the scroll
        // position, and _setLyricIndex stays silent when the line did not
        // move — so only refresh the index here.
        _setLyricIndex(lyricIndexAt(_lines, position));
        return;
      }
      final data = LrcParser.parseFile(candidate);
      final metadata = <String, String>{
        if (data.title.isNotEmpty) 'title': data.title,
        if (data.artist.isNotEmpty) 'artist': data.artist,
        if (data.album.isNotEmpty) 'album': data.album,
      };

      _lines = data.lines;
      _lyrics = <Map<String, Object?>>[
        for (final line in data.lines)
          <String, Object?>{'time': line.time, 'text': line.text},
      ];
      _lrcMetadata = metadata;
      _lrcPath = candidate;
      // Playback position did not change, but the line set may differ.
      _setLyricIndex(lyricIndexAt(_lines, position));
      notifyListeners();
      return; // first existing candidate wins
    }
    _clearLyrics();
  }

  Future<double> _readPosition(NativePlayer platform) async {
    try {
      return double.tryParse(await platform.getProperty('time-pos')) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<String> _readProperty(NativePlayer platform, String property) async {
    try {
      return await platform.getProperty(property);
    } catch (_) {
      return '';
    }
  }

  void _clearLyrics() {
    _lrcPath = '';
    if (_lyrics.isEmpty && _lines.isEmpty && _lrcMetadata.isEmpty) {
      return;
    }
    _lines = const <LrcLine>[];
    _lyrics = const <Map<String, Object?>>[];
    _lrcMetadata = const <String, String>{};
    _setLyricIndex(-1);
    notifyListeners();
  }

  void _setLyricIndex(int index) {
    if (_lyricIndex == index) {
      return;
    }
    _lyricIndex = index;
    notifyListeners();
  }

  void _onPositionChanged(double seconds) {
    if (_lines.isEmpty) {
      return;
    }
    _setLyricIndex(lyricIndexAt(_lines, seconds));
  }

  void _onMetadataChanged(Map<String, String> metadata) {
    if (_mapEquals(_mediaMetadata, metadata)) {
      return;
    }
    _mediaMetadata = Map<String, String>.unmodifiable(metadata);
    notifyListeners();
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  // ------------------------------------------------------------------
  // Equalizer v1
  // ------------------------------------------------------------------

  void _loadPersistedEqualizer() {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    _equalizerEnabled = settings.musicEqualizerEnabled;
    _equalizerPreset = settings.musicEqualizerPreset;
    final persisted = settings.musicEqualizerGains;
    _gains = List<double>.filled(kBandCount, 0.0);
    // Sanitize persisted data: wrong length resets to flat; each value is
    // clamped to the same range the sliders enforce.
    if (persisted.length == kBandCount) {
      for (var i = 0; i < kBandCount; ++i) {
        _gains[i] = _clamp(persisted[i]);
      }
    } else {
      _equalizerPreset = 'flat';
    }
    if (_equalizerPreset != 'custom' && !kPresetNames.contains(_equalizerPreset)) {
      _equalizerPreset = 'flat';
    }
  }

  static double _clamp(double gain) =>
      gain < -kMaxGain ? -kMaxGain : (gain > kMaxGain ? kMaxGain : gain);

  /// User moved one band slider (0..9, dB value): switches to "custom",
  /// persists and re-applies when enabled.
  Future<void> setEqualizerBand(int band, double gain) async {
    if (band < 0 || band >= kBandCount) {
      return;
    }
    final clamped = _clamp(gain);
    if (_gains[band] == clamped) {
      return;
    }
    _gains[band] = clamped;
    if (_equalizerPreset != 'custom') {
      _equalizerPreset = 'custom';
    }
    // Persistence goes through _persistEqualizer() alone: it guards the
    // null-settings case (tests run the controller without settings) and
    // writes the preset together with the gains it changed with.
    _persistEqualizer();
    await _applyEqualizerToEngine();
    notifyListeners();
  }

  /// Apply a built-in preset by name (unknown names are ignored).
  Future<void> applyEqualizerPreset(String preset) async {
    if (!kPresetNames.contains(preset)) {
      return;
    }
    _equalizerPreset = preset;
    _gains = List<double>.of(presetGains(preset));
    _persistEqualizer();
    await _applyEqualizerToEngine();
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (_equalizerEnabled == enabled) {
      return;
    }
    _equalizerEnabled = enabled;
    _persistEqualizer();
    await _applyEqualizerToEngine();
    notifyListeners();
  }

  void _persistEqualizer() {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    settings.musicEqualizerEnabled = _equalizerEnabled;
    settings.musicEqualizerPreset = _equalizerPreset;
    settings.musicEqualizerGains = List<double>.of(_gains);
    if (!settings.save()) {
      _onError?.call('cannot save ${settings.filePath}');
    }
  }

  Future<void> _applyEqualizerToEngine() async {
    final platform = _platform;
    if (platform == null) {
      return;
    }
    // Whole-chain write, narrowed for 2.0 (see the module doc): the
    // equalizer chain composes BEHIND the player bootstrap's scaletempo2
    // baseline instead of clobbering it; a disabled-after-enabled write
    // restores that baseline. Replaces whatever equalizer segment was
    // mounted before — documented sole-manager limitation for the EQ part.
    final chain = equalizerChain(_gains);
    final af = _equalizerEnabled
        ? (chain.isEmpty ? kPlaybackAfBaseline : '$kPlaybackAfBaseline,$chain')
        : kPlaybackAfBaseline;
    if (!_equalizerEnabled && !_mountedAf) {
      // inert rule: never write af when the EQ was never mounted
      return;
    }
    _mountedAf = _equalizerEnabled;
    try {
      await platform.setProperty('af', af);
    } catch (e) {
      EmoLogger().w('music: cannot apply equalizer chain', error: e);
    }
  }
}
