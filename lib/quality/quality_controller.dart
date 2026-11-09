// Dart port of mpv-emo src/quality/QualityController.{h,cpp} (B-class:
// QObject signals -> MobX observables, MpvEngine* -> MpvQualityEngine,
// QVariantMap options -> Map<String, Object?>; PORT-MAP §2).
// Semantics preserved one-for-one; the 1.x invariant comments are the spec
// and are kept.
//
// Applies QualityProfileEngine decisions to the live engine and owns the
// user-facing quality preferences (P5 v1). 1.x patterned after HistoryStore:
// a passive QObject service driven by engine signals plus on-demand
// property reads (docs/architecture.md decision 7 — no cached play state).
//
// Responsibilities (1.x class comment):
//   - persisted preferences live in settings.json's "quality" section and
//     are exposed to the UI (1.x: read-only Q_PROPERTYs, imperative sync)
//   - startup(): adopts shaders mounted by the imported mpv config (P4)
//     into the panel's manual list on first run, and mounts the persisted
//     manual list on later runs. The profile decision table itself is NOT
//     run here — no media is loaded yet
//   - applyProfile(): gathers MediaInfo from the engine, runs the decision
//     table and applies the result — scalar options via setProperty, the
//     shader list via "change-list" commands (clr + append)
//   - notifyDropFrameRate(): fed from the 2s dropped-frame sampler (1.x
//     MpvItem's timer, now owned by this controller); sustained heavy
//     dropping demotes the ACTIVE tier to low for the current file
//     (autoDowngraded flag drives the panel hint). The persisted user tier
//     is untouched and returns on the next file
//
// Inert-at-off rule (1.x): a session with tier "off" that never had
// anything applied never writes to the engine, so imported mpv.conf
// rendering options are untouched until the user engages the quality
// engine. When the engine disengages (tier switched to off), the managed
// options are reset to mpv defaults per the decision table (known v1
// limitation: this does not restore a previously imported value).
//
// 2.0 lifetime: 1.x held one engine for the whole session; the 2.0 player
// bootstrap creates a media_kit Player per file, so the controller attaches
// to each engine instance via [attachEngine] and re-runs the same event
// flow per file (fileLoaded fires on the URI change, video-params/fps on
// their arrivals).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide compute;
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/quality/quality_profile_engine.dart';
import 'package:emoplay/settings/emoplay_settings.dart';
import 'package:emoplay/utils/async_serial_queue.dart';

part 'quality_controller.g.dart';

class QualityController = _QualityController with _$QualityController;

abstract class _QualityController with Store {
  // |settings| must outlive this controller; the engine is attached per
  // playback session (1.x allowed a null engine in tests — then nothing
  // reaches mpv; attach nothing here for the same effect).
  _QualityController({
    required EmoPlaySettings settings,
    required this.shadersDir,
    void Function(String message)? onError,
  })  : _settings = settings,
        _onError = onError {
    // 1.x Q_PROPERTY getters read AppSettings live; the MobX mirror is the
    // reactive equivalent (every setter persists through the same store).
    contentMode = settings.qualityContentMode;
    qualityTier = settings.qualityTier;
    toneMappingMode = settings.qualityToneMapping;
    scaleOverride = settings.qualityScaleOverride;
    debandMode = settings.qualityDebandMode;
    manualShaders = List<String>.of(settings.manualShaderList);
  }

  final EmoPlaySettings _settings;
  final String shadersDir;
  final void Function(String message)? _onError;

  // Persisted preferences ("auto"/"anime"/"live", "off"/"low"/"medium"/
  // "high", tone-mapping "auto" or an explicit supported value, scale
  // override "" or an explicit --scale value).
  @observable
  String contentMode = 'auto';
  @observable
  String qualityTier = 'off';
  @observable
  String toneMappingMode = 'auto';
  @observable
  String scaleOverride = '';

  // "auto"/"yes"/"no" deband override from the panel.
  @observable
  String debandMode = 'auto';

  // Scanned "*.glsl" files (relative paths, may include subdirectories)
  // for the panel's shader management list.
  @observable
  List<String> availableShaders = const <String>[];

  // Absolute shader paths currently checked in the panel (persisted).
  @observable
  List<String> manualShaders = const <String>[];

  // True while the current file ran with an automatic tier demotion.
  @observable
  bool autoDowngraded = false;

  MpvQualityEngine? _engine;
  final List<StreamSubscription<void>> _engineSubs =
      <StreamSubscription<void>>[];
  Timer? _dropSampleTimer;

  // 1.x engine/state bookkeeping.
  bool _engineApplied = false; // engine-owned options are in effect
  bool _shaderListTouched = false; // we manage the glsl-shaders list
  List<String> _lastFinalShaders = const <String>[];

  // Dropped frames per second (over the 2s window) that triggers the
  // automatic tier demotion (1.x kAutoDowngradeDropRate).
  static const double _kAutoDowngradeDropRate = 2.0;

  // 1.x MpvItem::kDropSampleIntervalMs — the dropped-frame sampling window.
  static const int _dropSampleIntervalMs = 2000;

  // Cumulative counter observed from the engine (1.x: MpvEngine observed
  // frame-drop-count and MpvItem held the value; both live here now).
  int _droppedFrames = 0;
  int _lastDroppedSample = 0;

  // Serializes applyProfile() runs: 1.x ran the table synchronously on the
  // Qt event loop, so re-entrant signals could not interleave; the async
  // engine reads need the same guarantee.
  final AsyncSerialQueue _applyQueue = AsyncSerialQueue();

  void _reportError(String message) {
    final callback = _onError;
    if (callback != null) {
      callback(message);
    } else {
      debugPrint('quality: $message');
    }
  }

  /// Attaches a live engine (per playback session). Subscribes the 1.x
  /// engine signals and starts the 2s dropped-frame sampler.
  Future<void> attachEngine(MpvQualityEngine engine) async {
    detachEngine();
    _engine = engine;
    _engineSubs.addAll(<StreamSubscription<void>>[
      // A new file resets the auto demotion (the user's persisted tier
      // comes back and gets a fresh chance to trigger) and ALWAYS reruns
      // the decision table: options decided for the previous file
      // (scale/tone-mapping/shader groups) must not carry over.
      engine.fileLoaded.listen((_) => _onFileLoaded()),
      // video-params/container-fps usually arrive after file-loaded (and
      // only then); every arrival reruns the decision table so the
      // resolution-grouped shaders and HDR/HFR avoidance follow the real
      // media instead of the unknown-parameter guess.
      engine.videoParamsChanged.listen((_) => _apply()),
      engine.containerFpsChanged.listen((_) => _apply()),
      engine.frameDropCountChanged.listen(_onFrameDropCount),
    ]);
    // 1.x MpvItem: 2s dropped-frame sampling for the P5 auto-downgrade path.
    _dropSampleTimer = Timer.periodic(
      const Duration(milliseconds: _dropSampleIntervalMs),
      (_) => _sampleDroppedFrames(),
    );
  }

  /// Detaches the current engine (the player bootstrap owns the player and
  /// disposes it; this only cancels the listeners and the sampler).
  void detachEngine() {
    for (final subscription in _engineSubs) {
      unawaited(subscription.cancel());
    }
    _engineSubs.clear();
    _dropSampleTimer?.cancel();
    _dropSampleTimer = null;
    _engine = null;
  }

  void _onFrameDropCount(int count) {
    _droppedFrames = count;
  }

  void _onFileLoaded() {
    // 1.x MpvItem: reset the drop baseline on every file so rates never mix
    // files; 1.x QualityController: clear the session demotion.
    _lastDroppedSample = _droppedFrames;
    if (autoDowngraded) {
      runInAction(() => autoDowngraded = false);
    }
    _apply();
  }

  // 1.x MpvItem::sampleDroppedFrames: counter delta over the 2s window;
  // a negative delta means the counter reset (new file) — no drops.
  void _sampleDroppedFrames() {
    const windowSeconds = _dropSampleIntervalMs / 1000.0;
    var delta = _droppedFrames - _lastDroppedSample;
    _lastDroppedSample = _droppedFrames;
    if (delta < 0) {
      delta = 0; // counter reset (new file) — treat as no drops
    }
    notifyDropFrameRate(delta / windowSeconds);
  }

  /// Dropped-frames-per-second over the 2s window. A sustained rate at or
  /// above [_kAutoDowngradeDropRate] demotes the active tier to low.
  @action
  void notifyDropFrameRate(double framesPerSecond) {
    if (autoDowngraded || framesPerSecond < _kAutoDowngradeDropRate) {
      return;
    }
    final tier = qualityTierFromString(qualityTier);
    if (tier == QualityTier.off || tier == QualityTier.low) {
      return;
    }
    // Demote the active tier only: the persisted user tier stays, so the
    // next file starts from the user's real preference again.
    autoDowngraded = true;
    _apply();
  }

  /// Startup seeding (1.x QualityController::startup); runs once per app
  /// session on the first engine attach, before any file is loaded.
  Future<void> startup() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }

    manualShaders = List<String>.of(_settings.manualShaderList);
    final mountedNow = await engine.glslShaders();

    if (manualShaders.isEmpty) {
      // First run of the quality panel: adopt whatever the imported mpv
      // config already mounted (P4 passes glsl-shaders through) so that
      // the panel becomes the single source of truth.
      final adopted = <String>[];
      for (final path in mountedNow) {
        if (path.isNotEmpty && !adopted.contains(path)) {
          adopted.add(path);
        }
      }
      if (adopted.isNotEmpty) {
        manualShaders = adopted;
        _settings.manualShaderList = adopted;
        _settings.save();
      }
    } else if (mountedNow.isEmpty) {
      // Returning session without an imported shader list: mount the
      // persisted manual list via the documented change-list commands.
      await applyShaderList(manualShaders);
    }

    await scanAvailableShaders();
    if (manualShaders.isNotEmpty) {
      _shaderListTouched = true;
      _lastFinalShaders = List<String>.of(manualShaders);
    }
  }

  // Preference changes from the quality panel: persist, then re-apply.

  @action
  void setContentMode(String mode) {
    if (mode == contentMode) {
      return;
    }
    contentMode = mode;
    _settings.qualityContentMode = mode;
    _settings.save();
    _apply();
  }

  @action
  void setQualityTier(String tier) {
    if (tier == qualityTier) {
      return;
    }
    qualityTier = tier;
    _settings.qualityTier = tier;
    _settings.save();
    if (autoDowngraded) {
      // A manual choice lifts the automatic demotion.
      autoDowngraded = false;
    }
    _apply();
  }

  @action
  void setToneMappingMode(String mode) {
    if (mode == toneMappingMode) {
      return;
    }
    toneMappingMode = mode;
    _settings.qualityToneMapping = mode;
    _settings.save();
    _apply();
  }

  @action
  void setScaleOverride(String scale) {
    if (scale == scaleOverride) {
      return;
    }
    scaleOverride = scale;
    _settings.qualityScaleOverride = scale;
    _settings.save();
    _apply();
  }

  @action
  void setDebandMode(String mode) {
    if (mode == debandMode) {
      return;
    }
    debandMode = mode;
    _settings.qualityDebandMode = mode;
    _settings.save();
    _apply();
  }

  /// Panel shader list: mount/unmount a relative shader path.
  @action
  Future<void> setShaderMounted(String relativePath, bool mounted) async {
    if (relativePath.isEmpty) {
      return;
    }
    final absolute = p.join(shadersDir, relativePath);
    final next = List<String>.of(manualShaders);
    if (mounted) {
      if (!next.contains(absolute)) {
        next.add(absolute);
      }
    } else {
      next.remove(absolute);
    }
    if (_listEquals(next, manualShaders)) {
      return;
    }
    manualShaders = next;
    _settings.manualShaderList = next;
    _settings.save();
    _apply();
  }

  /// Recompute and apply; 1.x connected this to the engine's fileLoaded.
  /// The returned future completes when the run finishes (errors are
  /// reported through [onError], never rethrown).
  Future<void> applyProfile() {
    return _applyQueue.run(() async {
      try {
        await _applyProfile();
      } catch (e) {
        _reportError('applyProfile failed: $e');
      }
    });
  }

  /// Fire-and-forget apply used by the event-driven paths (1.x called
  /// applyProfile() synchronously from Qt signals; the async engine reads
  /// are serialized through the queue instead).
  void _apply() {
    unawaited(applyProfile());
  }

  Future<void> _applyProfile() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }

    // 1.x read the persisted prefs live through the Q_PROPERTY getters on
    // every applyProfile() run (QualityController.cpp L199-208); the MobX
    // mirror is re-synced here for the same contract, so a writer outside
    // this controller (settings.json changed between files) is honored
    // from the next apply on. Setters persist before applying, so this is
    // a no-op in the normal panel flow.
    runInAction(() {
      contentMode = _settings.qualityContentMode;
      qualityTier = _settings.qualityTier;
      toneMappingMode = _settings.qualityToneMapping;
      scaleOverride = _settings.qualityScaleOverride;
      debandMode = _settings.qualityDebandMode;
    });

    final prefs = UserPrefs()
      ..contentMode = contentModeFromString(contentMode);
    final userTier = qualityTierFromString(qualityTier);
    // Active-tier demotion while auto-downgraded; "off" stays off.
    prefs.qualityTier =
        autoDowngraded && userTier != QualityTier.off ? QualityTier.low : userTier;
    prefs.toneMappingMode = toneMappingMode;
    prefs.scaleOverride = scaleOverride;
    prefs.debandMode = debandMode;

    final info = await gatherMediaInfo();
    final result = compute(info, prefs);

    final engineActive = prefs.qualityTier != QualityTier.off;

    // Final mount list = manual (user-owned, absolute) + engine selection
    // (relative under shadersDir) with manual entries first.
    final finalShaders = List<String>.of(manualShaders);
    for (final relative in result.shaders) {
      final absolute = p.join(shadersDir, relative);
      if (!finalShaders.contains(absolute)) {
        finalShaders.add(absolute);
      }
    }

    // Inert at "off" until the engine or the shader list was ever engaged:
    // never touch imported rendering options of a fresh session.
    if (!engineActive && !_engineApplied && !_shaderListTouched &&
        finalShaders.isEmpty) {
      return;
    }

    if (engineActive || _engineApplied) {
      await _applyScalarOptions(engine, result.options);
    }
    _engineApplied = engineActive;

    if ((engineActive || finalShaders.isNotEmpty || _shaderListTouched) &&
        !_listEquals(finalShaders, _lastFinalShaders)) {
      await applyShaderList(finalShaders);
    }
    _shaderListTouched = engineActive || finalShaders.isNotEmpty;
    _lastFinalShaders = finalShaders;
  }

  Future<MediaInfo> gatherMediaInfo() async {
    final engine = _engine;
    final info = MediaInfo();
    if (engine == null) {
      return info;
    }

    final params = await engine.videoParams();
    info.width = params['w'] is int ? params['w'] as int : 0;
    info.height = params['h'] is int ? params['h'] as int : 0;
    info.isHdr = isHdrVideoParams(params);
    info.fps = await engine.containerFps();

    // Animated content hint: file name first, fall back to the title
    // (streaming URLs usually have no usable path part).
    var name = await engine.mediaPath();
    if (name.isEmpty) {
      name = await engine.mediaTitle();
    }
    info.vfFormat = animatedHintFrom(name);

    info.availableShaders = List<String>.of(availableShaders);
    return info;
  }

  /// 1.x scanAvailableShaders: QDirIterator "*.glsl" recursive (not
  /// following symlinks), QDir::relativeFilePath, sorted.
  Future<void> scanAvailableShaders() async {
    final names = <String>[];
    final dir = Directory(shadersDir);
    if (dir.existsSync()) {
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && entity.path.endsWith('.glsl')) {
            names.add(p.relative(entity.path, from: shadersDir));
          }
        }
      } catch (e) {
        _reportError('cannot scan $shadersDir: $e');
      }
    }
    names.sort();
    runInAction(() => availableShaders = List<String>.unmodifiable(names));
  }

  /// Scalar options only (skips the "glsl-shaders" entry). 1.x sent the
  /// QVariant values through MpvEngine::setProperty; the string-format
  /// property path maps booleans to mpv's "yes"/"no".
  Future<void> _applyScalarOptions(
    MpvQualityEngine engine,
    Map<String, Object?> options,
  ) async {
    for (final entry in options.entries) {
      if (entry.key == 'glsl-shaders') {
        continue; // handled by applyShaderList (change-list commands)
      }
      final value = entry.value;
      final String text;
      if (value is bool) {
        text = value ? 'yes' : 'no';
      } else {
        text = value?.toString() ?? '';
      }
      try {
        await engine.setProperty(entry.key, text);
      } catch (e) {
        _reportError('setProperty ${entry.key}=$text failed: $e');
      }
    }
  }

  /// clr + append of the desired final shader list (absolute paths).
  Future<void> applyShaderList(List<String> paths) async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    // glsl-shaders is a path-list option (mpv options.rst): the documented
    // runtime mutation is the change-list command (input.rst change-list;
    // player/command.c cmd_change_list; actions add/append/clr/...).
    try {
      await engine.command(
          <String>['change-list', 'glsl-shaders', 'clr', '']);
      for (final path in paths) {
        await engine.command(
            <String>['change-list', 'glsl-shaders', 'append', path]);
      }
    } catch (e) {
      _reportError('applyShaderList failed: $e');
    }
  }
}

/// Element-wise list comparison, the QStringList == semantics the guarded
/// apply path relies on.
bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
