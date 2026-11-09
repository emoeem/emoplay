// Dart port of mpv-emo src/quality/InterpolationController.{h,cpp}
// (B-class: QObject signals -> MobX observables, MpvEngine* ->
// MpvQualityEngine, QVariantList vf readback -> NODE-shaped maps;
// PORT-MAP §2). Semantics preserved one-for-one; the 1.x invariant
// comments are the spec and are kept.
//
// Frame interpolation v2 (P5): VapourSynth MEMC presets applied to the live
// engine as a labeled "vf" chain entry, behind an enable switch and a
// preset picker persisted in settings.json's quality section.
//
// Honest external-dependency pattern (docs/nativeization-plan.md §2.1 vs/
// row): EmoPlay only assembles and mounts the mpv side. The VapourSynth
// runtime, inference backends and the .vpy preset scripts stay external;
// whenever a piece is missing the feature stands down visibly instead of
// pretending to work:
//   - the preset's script file missing from the scripts directory blocks
//     the preset (panel hint, switch stays on, retry is free);
//   - a vapoursynth entry in the vf chain that EmoPlay does not own
//     (imported mpv.conf / a script) makes the controller stand down
//     completely — user config territory is never fought over;
//   - if libmpv cannot accept the vapoursynth filter at all (build without
//     vapoursynth: the "change-list vf append" command fails immediately),
//     the controller detects that by reading the vf property back, reverts
//     the persisted switch to off and raises the "needs system VapourSynth
//     support" hint (vsUnavailable). The probe runs once per session.
//
// Admission (HDR sources, high/unknown fps) lives in the pure
// InterpolationDecision table; this controller gathers the facts (same
// signal-driven pattern as QualityController, docs/architecture.md
// decision 7: nothing is cached) and mounts/unmounts exactly one vf entry
// labeled "emoplay-interp", leaving the rest of the chain untouched.
//
// 2.0 note: the shipped libmpv build has no vapoursynth filter (probed
// 2026-11-10, see native_quality_engine.dart) — the probe fails honestly on
// it and the feature stands down with vsUnavailable, exactly the 1.x
// behavior on a libmpv built without VapourSynth. A user-supplied libmpv
// with VapourSynth support probes successfully at the next session.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';

import 'package:emoplay/quality/interpolation_decision.dart';
import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/quality/quality_profile_engine.dart' as engine;
import 'package:emoplay/settings/emoplay_settings.dart';

part 'interpolation_controller.g.dart';

class InterpolationController = _InterpolationController
    with _$InterpolationController;

abstract class _InterpolationController with Store {
  // |settings| must outlive this controller; the engine is attached per
  // playback session (null engine in tests — nothing reaches mpv).
  // |scriptsDir| holds the user's VapourSynth preset scripts (EmoPlay ships
  // none): 1.x main.cpp pointed it at the app data vs/ directory.
  _InterpolationController({
    required EmoPlaySettings settings,
    required this.scriptsDir,
    void Function(String message)? onError,
  })  : _settings = settings,
        _onError = onError {
    enabled = settings.qualityInterpolationEnabled;
    preset = settings.qualityInterpolationPreset;
  }

  final EmoPlaySettings _settings;
  final void Function(String message)? _onError;

  // Persisted switch and preset id ("MEMC_RIFE_STD", ...).
  @observable
  bool enabled = false;
  @observable
  String preset = '';

  // True after the session probe proved libmpv cannot host vapoursynth;
  // the switch was already reverted to off.
  @observable
  bool vsUnavailable = false;

  // Stable id for the panel hint of the current admission block ("",
  // "fps-unknown", "high-fps", "hdr", "script-missing",
  // "foreign-vapoursynth").
  @observable
  String blockReason = '';

  // Absolute script path the current preset expects (panel shows where to
  // drop the .vpy file).
  @observable
  String expectedScriptPath = '';

  final String scriptsDir;

  MpvQualityEngine? _engine;
  final List<StreamSubscription<void>> _engineSubs =
      <StreamSubscription<void>>[];
  bool _entryMounted = false;

  // Session probe result: unknown until first probed, then sticky
  // (1.x enum Support { Unknown, Yes, No }).
  _Support _support = _Support.unknown;

  void _reportError(String message) {
    final callback = _onError;
    if (callback != null) {
      callback(message);
    } else {
      debugPrint('interpolation: $message');
    }
  }

  /// Attaches a live engine (per playback session). Admission depends on
  /// the media (HDR, fps): re-evaluate whenever the facts arrive or a new
  /// file starts, exactly like the v1 quality profile path.
  Future<void> attachEngine(MpvQualityEngine engine) async {
    detachEngine();
    _engine = engine;
    _engineSubs.addAll(<StreamSubscription<void>>[
      engine.fileLoaded.listen((_) => apply()),
      engine.videoParamsChanged.listen((_) => apply()),
      engine.containerFpsChanged.listen((_) => apply()),
    ]);
  }

  void detachEngine() {
    for (final subscription in _engineSubs) {
      unawaited(subscription.cancel());
    }
    _engineSubs.clear();
    _engine = null;
  }

  /// Applies the persisted preferences to the (idle) engine. Admission for
  /// unknown media blocks without touching the chain; the support probe
  /// runs once while the switch is on (1.x startup()).
  Future<void> startup() => apply();

  /// Switch from the panel: persisted, then (re)applied. Enabling with an
  /// unsupported libmpv triggers the probe fallback immediately.
  @action
  void setEnabled(bool value) {
    if (value == enabled) {
      return;
    }
    enabled = value;
    _settings.qualityInterpolationEnabled = value;
    _settings.save();
    apply();
  }

  /// Preset id from the panel; unknown ids are ignored (defensive against
  /// corrupted settings.json).
  @action
  void setPreset(String presetId) {
    if (!isKnownPreset(presetId) || presetId == preset) {
      return;
    }
    preset = presetId;
    _settings.qualityInterpolationPreset = presetId;
    _settings.save();
    _refreshExpectedScriptPath();
    apply();
  }

  /// The applied admission flow (1.x InterpolationController::apply).
  Future<void> apply() async {
    final currentEngine = _engine;
    if (currentEngine == null) {
      return;
    }
    _refreshExpectedScriptPath();

    // Corrupted settings.json must not enable anything: unknown preset ids
    // behave like the switch being off.
    final on = enabled && isKnownPreset(preset);

    if (!on) {
      if (_entryMounted) {
        await removeEntry();
      }
      _entryMounted = false;
      _setBlockReason(blockToString(InterpolationBlock.disabled));
      return;
    }

    // The session probe already proved this libmpv cannot host the filter:
    // re-enabling (or a later preset switch) falls straight back off.
    if (_support == _Support.no) {
      await _fallbackUnsupported();
      return;
    }

    // Stand down while a vapoursynth entry we do not own is in the chain
    // (imported mpv.conf territory). Checked before probing: no reason to
    // touch the chain at all in that case.
    List<Object?> chain;
    try {
      chain = await currentEngine.vfChain();
    } catch (e) {
      _reportError('vf readback failed: $e');
      return;
    }
    if (vfHasForeignVapoursynth(chain)) {
      if (_entryMounted) {
        await removeEntry();
      }
      _entryMounted = false;
      _setBlockReason(blockToString(InterpolationBlock.foreignVapoursynth));
      return;
    }

    // Prove once per session that libmpv accepted the filter before any
    // admission decision matters. A failed probe already reverted the
    // switch to off, so the next apply() takes the disabled path.
    if (_support == _Support.unknown && !await probeSupport()) {
      return;
    }

    final facts = await gatherFacts();
    final block = admission(facts, true);
    if (block != InterpolationBlock.none) {
      if (_entryMounted) {
        await removeEntry();
      }
      _entryMounted = false;
      _setBlockReason(blockToString(block));
      return;
    }

    _setBlockReason('');
    await appendEntry(expectedScriptPath);
    _entryMounted = true;
  }

  /// Gathers fps/HDR facts from the engine (no caching).
  Future<MediaFacts> gatherFacts() async {
    final currentEngine = _engine;
    final facts = MediaFacts();
    if (currentEngine == null) {
      return facts;
    }

    facts.fps = await currentEngine.containerFps();
    // Same HDR criteria as the v1 quality profile (BT.2020/PQ/HLG).
    facts.isHdr = engine.isHdrVideoParams(await currentEngine.videoParams());
    facts.scriptAvailable =
        File(expectedScriptPath).existsSync();
    try {
      facts.foreignVapoursynth =
          vfHasForeignVapoursynth(await currentEngine.vfChain());
    } catch (_) {
      facts.foreignVapoursynth = false;
    }
    return facts;
  }

  /// Appends our labeled vf entry via the change-list command (1.x
  /// appendEntry): vf is an object settings list; the documented runtime
  /// mutation is the change-list command (mpv input.rst change-list;
  /// player/command.c cmd_change_list). Appending an entry that carries our
  /// label replaces an earlier one in place, so preset switches stay
  /// idempotent.
  Future<void> appendEntry(String scriptPath) async {
    final currentEngine = _engine;
    if (currentEngine == null) {
      return;
    }
    await currentEngine.command(<String>[
      'change-list',
      'vf',
      'append',
      vfEntry(scriptPath),
    ]);
  }

  /// "remove @label" marks our entry for deletion by label
  /// (options/m_option.c parse_obj_settings_del); a missing entry only
  /// warns inside mpv (probed 2026-11-10: rc=0), which is exactly what we
  /// want on cleanup paths.
  Future<void> removeEntry() async {
    final currentEngine = _engine;
    if (currentEngine == null) {
      return;
    }
    await currentEngine.command(<String>[
      'change-list',
      'vf',
      'remove',
      '@${entryLabel()}',
    ]);
  }

  /// Appends the entry, reads the chain back, removes it again. Returns
  /// true when mpv accepted the filter. On failure: persists the switch
  /// off, sets vsUnavailable and clears any mounted entry (1.x
  /// probeSupport).
  Future<bool> probeSupport() async {
    // The append either lands in the vf list (filter compiled in) or fails
    // outright on a libmpv built without vapoursynth ("X doesn't exist";
    // probed on the shipped build: rc=-12 with an empty chain) — reading
    // the chain back distinguishes the two without trusting the command's
    // void return (the media-kit fork logs command errors without
    // throwing).
    await appendEntry(expectedScriptPath);
    bool accepted;
    try {
      final chain = _engine?.vfChain() ?? Future<List<Object?>>.value(const []);
      accepted = vfHasLabeledEntry(await chain);
    } catch (_) {
      accepted = false;
    }
    await removeEntry();
    _entryMounted = false;

    if (accepted) {
      _support = _Support.yes;
      return true;
    }

    _support = _Support.no;
    await _fallbackUnsupported();
    return false;
  }

  /// The "needs system vapoursynth support" fallback: switch off
  /// (persisted), chain cleaned, hint set (1.x fallbackUnsupported).
  Future<void> _fallbackUnsupported() async {
    // Honest fallback: without engine support the switch cannot stay on.
    // Persisting "off" avoids probing again on every startup; the panel
    // keeps showing the hint for the rest of the session (the next session
    // probes again — a libmpv with vapoursynth may have appeared).
    runInAction(() {
      vsUnavailable = true;
      if (enabled) {
        enabled = false;
      }
    });
    if (_settings.qualityInterpolationEnabled) {
      _settings.qualityInterpolationEnabled = false;
      _settings.save();
    }
    if (_entryMounted) {
      await removeEntry();
      _entryMounted = false;
    }
    _setBlockReason(blockToString(InterpolationBlock.disabled));
    _reportError(
        'vapoursynth filter unavailable: libmpv rejected vf change-list '
        'append (system vapoursynth support required)');
  }

  void _setBlockReason(String reason) {
    runInAction(() {
      if (blockReason == reason) {
        return;
      }
      blockReason = reason;
    });
  }

  void _refreshExpectedScriptPath() {
    final scriptName = scriptNameForPreset(preset);
    final path =
        scriptName.isEmpty ? '' : '$scriptsDir/$scriptName';
    runInAction(() {
      if (expectedScriptPath != path) {
        expectedScriptPath = path;
      }
    });
  }
}

enum _Support { unknown, yes, no }
