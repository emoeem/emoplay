// Dart port of mpv-emo src/quality/IccController.{h,cpp} (B-class:
// QObject signals -> MobX observables, MpvEngine* -> MpvQualityEngine;
// PORT-MAP §2). Semantics preserved one-for-one; the 1.x invariant
// comments are the spec and are kept.
//
// ICC display configuration (P5 v2): an enable switch plus a display
// profile file picked in the quality panel, applied to the live engine as
// the mpv "icc-profile" gpu-renderer option (mpv v0.37.0
// video/out/gpu/lcms.c mp_icc_conf; runtime changes are picked up by
// gl_video_update_options -> gl_lcms_update_options, video.c, so no reload
// is needed).
//
// The 3DLUT cache location always follows the P4 redirect table: the
// controller sets icc-cache-dir to MpvImportRules.redirectTarget(
// "icc-cache-dir", appDataDir) — <appData>/icc_cache — whenever it applies
// a profile, so enabling ICC from EmoPlay never moves a write path into
// the user's mpv directory, imported session or not (SPEC §4.2).
//
// Honest failure handling (1.x): the profile file must exist before
// anything is written; the property set is verified by reading icc-profile
// back; and any failure reverts the persisted switch to off and raises
// failureHint for the panel. Disabling restores the icc-profile value
// captured at startup(), so a profile imported through P4 survives the
// round trip (inert-at-off, same rule as QualityController).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';

import 'package:emoplay/mpv/compat/mpv_import_rules.dart';
import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

part 'icc_controller.g.dart';

class IccController = _IccController with _$IccController;

abstract class _IccController with Store {
  // |settings| must outlive this controller; the engine is attached per
  // playback session (null engine in tests — nothing reaches mpv).
  // |appDataDir| receives the cache redirect (icc_cache sub-directory per
  // the P4 table).
  _IccController({
    required EmoPlaySettings settings,
    required String appDataDir,
    void Function(String message)? onError,
  })  : _settings = settings,
        _appDataDir = appDataDir,
        _onError = onError {
    enabled = settings.qualityIccEnabled;
    profilePath = settings.qualityIccProfilePath;
  }

  final EmoPlaySettings _settings;
  final String _appDataDir;
  final void Function(String message)? _onError;

  // Persisted switch and profile path (absolute, from the panel's file
  // dialog).
  @observable
  bool enabled = false;
  @observable
  String profilePath = '';

  // True after the last apply attempt failed (hint below is shown).
  @observable
  bool failed = false;
  @observable
  String failureHint = '';

  // icc-profile value seen at startup(); restored on disable/failure.
  String _startupProfile = '';

  bool _applied = false;

  MpvQualityEngine? _engine;

  void _reportError(String message) {
    final callback = _onError;
    if (callback != null) {
      callback(message);
    } else {
      debugPrint('icc: $message');
    }
  }

  /// Redirected cache directory (P4 table), shown in the panel. Same table
  /// the P4 startup redirects use — one source of truth.
  String get cacheDir =>
      MpvImportRules.redirectTarget('icc-cache-dir', _appDataDir);

  /// Attaches a live engine (per playback session). Unlike the profile and
  /// interpolation flows there is no per-file admission: the ICC options
  /// are engine-level and only (re)snapshotted once per app session, which
  /// is why [startup] stays a separate one-shot step.
  void attachEngine(MpvQualityEngine engine) {
    _engine = engine;
  }

  void detachEngine() {
    _engine = null;
  }

  /// Snapshots the engine's current icc-profile (an imported value must
  /// survive disable/enable cycles) and applies the persisted preferences
  /// (1.x startup()). Runs once per app session on the first engine attach.
  Future<void> startup() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }

    // Snapshot before touching anything: with an imported mpv.conf the
    // engine may already run a user-configured profile that must survive
    // our disable path untouched.
    _startupProfile = await engine.iccProfile();

    await apply();
  }

  /// Switch from the panel: persisted, then applied; enabling without a
  /// usable profile falls back to off with a hint.
  @action
  void setEnabled(bool value) {
    if (value == enabled) {
      return;
    }
    enabled = value;
    _settings.qualityIccEnabled = value;
    _settings.save();
    apply();
  }

  /// Absolute profile path from the panel's file dialog (file:// URLs are
  /// converted). Persisted, then applied.
  @action
  void setProfilePath(String path) {
    // File dialogs hand out file:// URLs; mpv's M_OPT_FILE wants a plain
    // filesystem path (1.x MpvEngine::toMediaPath).
    final normalized = _toMediaPath(path);
    if (normalized == profilePath) {
      return;
    }
    profilePath = normalized;
    _settings.qualityIccProfilePath = normalized;
    _settings.save();
    apply();
  }

  /// The applied option flow (1.x IccController::apply).
  Future<void> apply() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }

    final on = enabled && profilePath.isNotEmpty;
    if (!on) {
      if (_applied) {
        await _restoreProfile();
        _applied = false;
      }
      _clearFailed();
      return;
    }

    // Honest pre-check: a missing/unreadable profile would only surface
    // deep inside mpv's renderer; state it where the user can act on it.
    if (!_isReadableFile(profilePath)) {
      _fail('ICC profile file not found or unreadable: $profilePath');
      return;
    }

    // Cache redirect first so the freshly enabled profile's 3DLUT cache
    // never lands in the user's mpv directory (P4 redirect table).
    try {
      await engine.setProperty('icc-cache-dir', cacheDir);
      await engine.setProperty('icc-profile', profilePath);
    } catch (e) {
      _fail('mpv rejected icc-profile ($e)');
      return;
    }

    // Verify the option actually took (a libmpv without the gpu renderer
    // option would silently ignore it otherwise).
    String readBack;
    try {
      readBack = await engine.iccProfile();
    } catch (e) {
      _fail('mpv rejected icc-profile (readback failed: $e)');
      return;
    }
    if (readBack != profilePath) {
      _fail("mpv rejected icc-profile (read back '$readBack')");
      return;
    }

    _applied = true;
    runInAction(() {
      failed = false;
      failureHint = '';
    });
  }

  Future<void> _restoreProfile() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    // An empty string restores mpv's default (no profile).
    try {
      await engine.setProperty('icc-profile', _startupProfile);
    } catch (e) {
      _reportError('cannot restore the startup icc-profile: $e');
    }
  }

  /// Reverts the switch to off (persisted), restores any applied profile
  /// and surfaces |hint| in the panel (1.x fail()).
  void _fail(String hint) {
    if (_applied) {
      unawaited(_restoreProfile());
      _applied = false;
    }
    // Same fallback contract as the interpolation controller: without a
    // usable profile the switch cannot stay on.
    if (_settings.qualityIccEnabled) {
      _settings.qualityIccEnabled = false;
      _settings.save();
    }
    runInAction(() {
      enabled = false;
      failed = true;
      failureHint = hint;
    });
    _reportError(hint);
  }

  void _clearFailed() {
    runInAction(() {
      failed = false;
      failureHint = '';
    });
  }

  // QFileInfo::isFile() && isReadable() equivalent. statSync() would not
  // honor ACLs; an actual open is the honest readable check.
  static bool _isReadableFile(String path) {
    if (path.isEmpty) {
      return false;
    }
    try {
      final stat = FileStat.statSync(path);
      if (stat.type != FileSystemEntityType.file) {
        return false;
      }
      final file = File(path);
      final handle = file.openSync();
      handle.closeSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  // 1.x MpvEngine::toMediaPath: QML file dialogs hand out file:// URLs;
  // mpv's M_OPT_FILE wants a plain filesystem path. Flutter pickers return
  // plain paths, but pasted values keep the conversion.
  static String _toMediaPath(String value) {
    if (value.startsWith('file://')) {
      try {
        return Uri.parse(value).toFilePath();
      } catch (_) {
        return value;
      }
    }
    return value;
  }
}
