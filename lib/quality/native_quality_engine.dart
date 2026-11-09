// media_kit adapter for MpvQualityEngine (the 1.x MpvEngine* stand-in the
// quality controllers drive). Semantics: facts are read on demand from the
// live engine; the 1.x engine signals map onto media_kit streams and raw
// property observation:
//
//   fileLoaded          -> player.stream.playlist, deduplicated on the
//                          current entry URI (media_kit has no file-loaded
//                          event; the same constraint the M2 resume-seek
//                          port worked around with playback-time —
//                          player_playback_controller.dart _armResumeSeek).
//   videoParamsChanged  -> player.stream.videoParams (media-kit reads
//                          video-params as MPV_FORMAT_NODE internally and
//                          re-emits on every report, not distinct).
//   containerFpsChanged -> NativePlayer.observeProperty('container-fps'),
//                          parsed from the string readback.
//   frameDropCountChanged -> observeProperty('frame-drop-count'), the
//                          cumulative counter MpvItem sampled every 2s.
//
// Empirical ground truth for the string readbacks (throwaway dlopen harness
// against the shipped build/native_assets/linux/libmpv.so.2, "mpv v0.41.0-
// 11-gf011d73d5-dirty", probed 2026-11-10; M5 used the same technique for
// the init-time option probe):
//   * change-list vf append @emoplay-interp:vapoursynth=... fails outright
//     (rc=-12, "error running command") — this build has no vapoursynth
//     filter, so InterpolationController's probe will honestly fall back to
//     vsUnavailable exactly like 1.x on a libmpv built without it.
//   * vf prints as comma-joined "[@label:]name[=k=v:k=v]" entries; %len%
//     quoting is parsed away in the print form; appending an entry whose
//     label already exists replaces it in place; remove of a missing label
//     only warns (rc=0).
//   * glsl-shaders prints colon-joined after change-list appends and echoes
//     the comma form when it was set as one comma-joined string.
//   * icc-profile round-trips the set string verbatim (readback equality is
//     a valid acceptance check); scalar options (scale/deband/tone-mapping/
//     target-colorspace-hint/icc-cache-dir) echo what was set.
//   * container-fps / frame-drop-count / path / media-title read back empty
//     (mpv_get_property_string returns NULL) while idle — the adapters treat
//     that as "unknown" (0.0 / no event), never a guess.
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/services/logging/logger.dart';

class NativeQualityEngine implements MpvQualityEngine {
  NativeQualityEngine(this._player);

  final Player _player;

  final StreamController<void> _fileLoadedController =
      StreamController<void>.broadcast();
  final StreamController<double> _containerFpsController =
      StreamController<double>.broadcast();
  final StreamController<int> _frameDropCountController =
      StreamController<int>.broadcast();
  final List<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>[];
  final List<String> _observedProperties = <String>[];
  String? _lastFileUri;
  bool _disposed = false;

  NativePlayer get _platform => _player.platform as NativePlayer;

  /// Registers the engine events. Called once per player by the quality
  /// session; observeProperty throws on a duplicate observation, so every
  /// property is registered at most once per engine instance.
  Future<void> start() async {
    _subscriptions
        .add(_player.stream.playlist.listen(_onPlaylistChanged));
    await _observe(
      'container-fps',
      (value) async {
        final fps = double.tryParse(value);
        if (fps != null && !_containerFpsController.isClosed) {
          _containerFpsController.add(fps);
        }
      },
      'cannot observe container-fps',
    );
    await _observe(
      'frame-drop-count',
      (value) async {
        final count = int.tryParse(value);
        if (count != null && !_frameDropCountController.isClosed) {
          _frameDropCountController.add(count);
        }
      },
      'cannot observe frame-drop-count',
    );
  }

  Future<void> _observe(
    String property,
    Future<void> Function(String value) listener,
    String failureMessage,
  ) async {
    try {
      await _platform.observeProperty(property, listener);
      _observedProperties.add(property);
    } catch (e) {
      // A property missing from this libmpv build only degrades the
      // corresponding 1.x signal to "never fires" — the controllers' own
      // on-demand reads stay authoritative.
      EmoLogger().w('NativeQualityEngine: $failureMessage', error: e);
    }
  }

  void _onPlaylistChanged(Playlist playlist) {
    if (_disposed) {
      return;
    }
    final index = playlist.index;
    final String? uri = index >= 0 && index < playlist.medias.length
        ? playlist.medias[index].uri
        : null;
    // Fire once per file: only when the playing entry's URI actually
    // changes (1.x fileLoaded fired exactly once per loaded file).
    if (uri != null && uri != _lastFileUri) {
      _lastFileUri = uri;
      if (!_fileLoadedController.isClosed) {
        _fileLoadedController.add(null);
      }
    }
  }

  @override
  Future<Map<Object?, Object?>> videoParams() async {
    // Player.state carries the current video-params NODE read maintained by
    // media-kit itself (real.dart copies it into VideoParams on every
    // report) — the on-demand equivalent of 1.x getProperty('video-params').
    final params = _player.state.videoParams;
    return <Object?, Object?>{
      if (params.w != null) 'w': params.w,
      if (params.h != null) 'h': params.h,
      if (params.primaries != null) 'primaries': params.primaries,
      if (params.gamma != null) 'gamma': params.gamma,
    };
  }

  @override
  Future<double> containerFps() async {
    try {
      final value = await _platform.getProperty('container-fps');
      return double.tryParse(value) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<String> mediaPath() => _readString('path');

  @override
  Future<String> mediaTitle() => _readString('media-title');

  @override
  Future<List<String>> glslShaders() async {
    return parsePathList(await _readString('glsl-shaders'));
  }

  @override
  Future<List<Object?>> vfChain() async {
    return parseVfChain(await _readString('vf'));
  }

  @override
  Future<String> iccProfile() => _readString('icc-profile');

  @override
  Future<void> setProperty(String property, String value) async {
    await _platform.setProperty(property, value);
  }

  @override
  Future<void> command(List<String> args) async {
    await _platform.command(args);
  }

  @override
  Stream<void> get fileLoaded => _fileLoadedController.stream;

  @override
  Stream<void> get videoParamsChanged => _player.stream.videoParams.map<void>(
        (_) {},
      );

  @override
  Stream<double> get containerFpsChanged => _containerFpsController.stream;

  @override
  Stream<int> get frameDropCountChanged => _frameDropCountController.stream;

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final property in _observedProperties) {
      // The player may already be disposed — nothing left to unobserve.
      unawaited(
        _platform.unobserveProperty(property).catchError((_) {}),
      );
    }
    _observedProperties.clear();
    _fileLoadedController.close();
    _containerFpsController.close();
    _frameDropCountController.close();
  }

  Future<String> _readString(String property) async {
    try {
      return await _platform.getProperty(property);
    } catch (_) {
      return '';
    }
  }
}
