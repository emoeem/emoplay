// Dart port of mpv-emo src/plugins/PluginManager.{h,cpp} (PORT-MAP §1:
// QProcess git → Process.run; state.json format unchanged).
//
// P8 plugin store v1 (docs/nativeization-plan.md §4): installs upstream git
// assets declared in a manager.json-compatible catalog and appends enabled
// script plugins to mpv's --scripts path list.
//
// Plugin content lives under <appDataDir>/plugins/<name>/ as a shallow
// (depth 1) clone of the manifest source, so `git status --porcelain` can
// detect user customizations and future batches can fetch-based update.
//
// Core principle — "local customizations are never overwritten":
//  - mode "check" never touches installed files; update checks only compare
//    the remote HEAD against the manifest baseline (`git ls-remote`).
//  - mode "replace" re-clones into a staging directory and atomically swaps,
//    but refuses when `git status --porcelain` reports local modifications,
//    and always moves the old install to a sibling ".backup-<name>" directory
//    first.
//  - enabling a plugin only APPENDS entry paths to the existing "scripts"
//    option value assembled by the P4 compat layer; the user's own script
//    list is never replaced or reordered.
//
// Every mutating action is planned by planOperation() and must be confirmed
// in the UI (the plugins page shows the change list in a dialog) before
// install/update/uninstall is invoked — the 1.x three-stage contract
// (docs/SPEC.md §4.6, planOperation → UI 确认 → 执行). The plan chain is
// never executed directly: planOperation only ever returns the change list
// (or a refusal), and M6-T2 appends every planning result and every terminal
// operation result to the append-only audit file
// <appDataDir>/plugin_audit.jsonl (PluginAuditLog — observational only, it
// never gates an operation and must never break one).
//
// M6-T1: the manifest's asset-integrity pair (sizeBytes + sha256) is
// enforced here at the very front of the install chain — an incomplete pair
// (缺一拒装) refuses the install BEFORE any git command runs, and a pinned
// manifest has its freshly cloned content verified (install) or its staged
// content verified (replace-mode update) before anything is recorded or
// swapped (PluginContentIntegrity, plugin_git_runner.dart). Manifests
// without integrity fields keep the exact 1.x behaviour.
//
// All git invocations go through the injectable PluginGitRunner interface;
// unit tests drive the whole state machine with a synchronous fake and never
// touch the network. The 1.x signal-driven step machine maps onto an
// await chain: PluginGitRunner.run is a Future, and the step order, the
// failure messages and the single-flight invariant are carried over
// verbatim.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:emoplay/plugins/plugin_git_runner.dart';
import 'package:emoplay/plugins/plugin_manifest.dart';
import 'package:emoplay/services/logging/logger.dart';

/// Per-plugin persisted state (one state.json entry).
class PluginState {
  PluginState({this.enabled = false, this.head = ''});

  bool enabled;
  // Upstream HEAD recorded when the plugin was installed or replaced.
  String head;
}

enum _Action { install, uninstall, update, check, checkAll }

enum _Step {
  clone, // git clone --depth 1 --branch <branch> -- <url> <target>
  readHead, // git rev-parse HEAD (in the new install)
  lsRemote, // git ls-remote <url> refs/heads/<branch>
  status, // git status --porcelain (replace-mode guard)
}

/// Catalog + live status for the plugins page (see [plugins] for the fields).
class PluginManager extends ChangeNotifier {
  /// [appDataDir] is EmoPlay's application support directory: the plugin root
  /// is `<appDataDir>/plugins` and per-plugin state is
  /// `<appDataDir>/plugins/state.json`. [catalogJson] is the raw text of a
  /// manager.json-style catalog (the app passes the
  /// assets/plugins/builtin_sources.json bundle; tests pass fixture text).
  PluginManager({
    required String appDataDir,
    required String catalogJson,
    required String catalogPath,
    PluginGitRunner? gitRunner,
    void Function(String message)? onError,
  })  : _pluginsRoot = '$appDataDir/plugins',
        _statePath = '$appDataDir/plugins/state.json',
        _auditPath = '$appDataDir/plugin_audit.jsonl',
        _audit = PluginAuditLog('$appDataDir/plugin_audit.jsonl'),
        _catalogPath = catalogPath,
        _onError = onError {
    // git runs with the plugin root as cwd, so it must exist before the
    // first process starts (the app-data dirs are not auto-created).
    Directory(_pluginsRoot).createSync(recursive: true);

    _git = gitRunner ?? const ProcessPluginGitRunner();

    if (!_loadCatalog(catalogJson)) {
      _emitError('cannot read plugin catalog $catalogPath');
    }
    _loadState();
  }

  final String _pluginsRoot;
  final String _statePath;
  final String _catalogPath;
  // M6-T2: append-only operation audit, an AppData sibling of plugins/.
  final String _auditPath;
  final PluginAuditLog _audit;
  final void Function(String message)? _onError;

  List<PluginManifest> _catalog = <PluginManifest>[];
  // Manifests fetched from online sources (P8 v2 RemoteManifestSource);
  // never persisted here, the source object owns the cache.
  List<PluginManifest> _remoteCatalog = <PluginManifest>[];
  final Map<String, PluginState> _state = <String, PluginState>{};
  // Live results of the last remote check (not persisted).
  final Map<String, String> _remoteHeads = <String, String>{};
  // Live results of the last `git status --porcelain` check (not persisted).
  final Map<String, bool> _locallyModified = <String, bool>{};

  late final PluginGitRunner _git;
  bool _busy = false;
  _Action _action = _Action.check;
  _Step _step = _Step.lsRemote;
  String _currentName = '';
  String _stagingDir = '';
  String _newHead = '';
  final List<String> _checkQueue = <String>[];
  Completer<void>? _checkAllCompleter;

  /// Result of a confirmed operation (including refused pre-flight checks);
  /// the 1.x operationFinished(name, action, success, message) signal.
  void Function(String name, String action, bool success, String message)?
      onOperationFinished;

  bool get busy => _busy;

  /// The M6-T2 audit file path: `<appDataDir>/plugin_audit.jsonl` — an
  /// AppData sibling of the `plugins/` directory, never a user-home or CWD
  /// file (PluginAuditLog).
  String get auditPath => _auditPath;

  // ---- pure helpers (unit-tested without git) -------------------------------

  // mpv's --scripts is a path list (OPT_PATHLIST): ':' on Unix, ';' on
  // Windows — never the ',' used by ordinary list options (mpv options.rst
  // "--scripts=file1.lua:file2.lua:...").
  static String get scriptSeparator => Platform.isWindows ? ';' : ':';

  // Paths appended to --scripts for an installed plugin. Script plugins
  // only; shader/asset plugins yield an empty list. For a single-file
  // destination ("scripts/mpv360.lua") the entry is the file inside the
  // content root; for a directory destination the entry is the content
  // root itself, which mpv loads via its "main.lua" (mpv 0.37.0
  // player/scripting.c mp_load_script: a directory entry is loaded through
  // "main.<backend ext>").
  static List<String> scriptEntryPaths(
    PluginManifest manifest,
    String pluginsRoot,
  ) {
    if (!manifest.valid || !manifest.isScriptPlugin) {
      return const [];
    }
    final contentRoot =
        manifest.contentRoot('$pluginsRoot/${manifest.name}');
    // QFileInfo::fileName(): the last path component of the destination.
    final base = manifest.destination.split('/').last;
    // Single-file destination (manager.json also carries entries like
    // "scripts/mpv360.lua"): the entry is the file inside the content root.
    final lower = base.toLowerCase();
    if (lower.endsWith('.lua') || lower.endsWith('.js')) {
      return <String>['$contentRoot/$base'];
    }
    // Directory destination: mpv loads a directory entry from the --scripts
    // path list via its "main.lua" (mpv 0.37.0 player/scripting.c,
    // mp_load_script: S_ISDIR branch looks up "main.<backend ext>").
    return <String>[contentRoot];
  }

  // Appends [entryPaths] to the "scripts" option, preserving whatever the
  // compat layer assembled. An empty [entryPaths] leaves the map untouched
  // (no empty "scripts" value is ever created). The 1.x guard against a
  // non-string "scripts" value (joinExistingScripts) has no Dart analogue:
  // the option map is Map<String, String>, so a non-string value cannot be
  // stored in the first place.
  static void mergeScriptOptions(
    Map<String, String> options,
    List<String> entryPaths,
  ) {
    if (entryPaths.isEmpty) {
      return; // never create an empty "scripts" value
    }
    final addition = entryPaths.join(scriptSeparator);
    final existing = options['scripts'];
    if (existing != null && existing.isNotEmpty) {
      // Append-only: whatever the user imported keeps its position.
      options['scripts'] = '$existing$scriptSeparator$addition';
      return;
    }
    options['scripts'] = addition;
  }

  // ---- model ------------------------------------------------------------------

  /// Builtin catalog first, then the remote one, deduped by name.
  List<PluginManifest> allManifests() {
    final all = List<PluginManifest>.of(_catalog);
    final seen = <String>{for (final m in _catalog) m.name};
    for (final manifest in _remoteCatalog) {
      if (!seen.contains(manifest.name)) {
        all.add(manifest); // the builtin catalog keeps priority
      }
    }
    return all;
  }

  PluginManifest manifestFor(String name) {
    for (final manifest in _catalog) {
      if (manifest.name == name) {
        return manifest;
      }
    }
    // P8 v2: manifests from online sources resolve after the builtin catalog.
    for (final manifest in _remoteCatalog) {
      if (manifest.name == name) {
        return manifest;
      }
    }
    return PluginManifest(); // invalid
  }

  bool isInstalled(String name) => Directory(_pluginDir(name)).existsSync();

  String _pluginDir(String name) => '$_pluginsRoot/$name';

  /// The plugins() row for one manifest (catalog + live install state).
  Map<String, Object?> pluginRow(PluginManifest manifest) {
    final state = _state[manifest.name] ?? PluginState();
    final installed = isInstalled(manifest.name);
    final entryPaths = scriptEntryPaths(manifest, _pluginsRoot);

    return <String, Object?>{
      'name': manifest.name,
      'url': manifest.url,
      'branch': manifest.branch,
      'source': manifest.source,
      'destination': manifest.destination,
      'mode': manifest.mode,
      'baseline': manifest.baseline,
      'sizeBytes': manifest.sizeBytes,
      'sha256': manifest.sha256,
      'isScript': manifest.isScriptPlugin,
      'installed': installed,
      'enabled': installed && manifest.isScriptPlugin && state.enabled,
      'head': state.head,
      'remoteHead': _remoteHeads[manifest.name] ?? '',
      'updateAvailable': _updateAvailable(manifest, state),
      'locallyModified': _locallyModified[manifest.name] ?? false,
      'entryPath': entryPaths.isEmpty ? '' : entryPaths.first,
    };
  }

  /// One row per known manifest (builtin + remote), for the plugins page.
  List<Map<String, Object?>> plugins() => <Map<String, Object?>>[
        for (final manifest in allManifests()) pluginRow(manifest),
      ];

  /// Startup hook: appends enabled+installed plugin entry paths to
  /// [options] (see [mergeScriptOptions]).
  void appendScriptOptions(Map<String, String> options) {
    mergeScriptOptions(options, scriptOptions());
  }

  /// The raw entry paths [appendScriptOptions] would merge — the
  /// MpvPlayerProperties.build(pluginScripts:) input.
  List<String> scriptOptions() {
    final entries = <String>[];
    for (final manifest in allManifests()) {
      final state = _state[manifest.name];
      final enabled = state != null && state.enabled;
      if (enabled && isInstalled(manifest.name)) {
        entries.addAll(scriptEntryPaths(manifest, _pluginsRoot));
      }
    }
    return entries;
  }

  /// P8 v2: manifests from online sources become installable/updateable like
  /// builtin ones. Skips no-op pushes: RemoteManifestSource pushes on every
  /// fetch/cache load, and an unconditional notifyListeners would churn the
  /// plugins page needlessly.
  void setRemoteCatalog(List<PluginManifest> manifests) {
    var same = manifests.length == _remoteCatalog.length;
    for (var i = 0; same && i < manifests.length; ++i) {
      final a = manifests[i];
      final b = _remoteCatalog[i];
      same = a.name == b.name &&
          a.url == b.url &&
          a.branch == b.branch &&
          a.source == b.source &&
          a.destination == b.destination &&
          a.mode == b.mode &&
          a.baseline == b.baseline &&
          // M6-T1: a re-pinned integrity pair changes the manifest.
          a.sizeBytes == b.sizeBytes &&
          a.sha256 == b.sha256;
    }
    if (same) {
      return;
    }
    _remoteCatalog = List<PluginManifest>.of(manifests);
    notifyListeners();
  }

  // Update-available decision per manifest mode (see the module doc):
  // check mode references the manifest baseline (upstream moved ahead of
  // what the local customizations are based on); without a baseline (and
  // always for replace mode) the reference is the recorded install HEAD.
  bool _updateAvailable(PluginManifest manifest, PluginState state) {
    if (!isInstalled(manifest.name)) {
      return false;
    }
    final remote = _remoteHeads[manifest.name] ?? '';
    if (remote.isEmpty) {
      return false;
    }
    final reference =
        (!manifest.isReplace && manifest.baseline.isNotEmpty)
            ? manifest.baseline
            : state.head;
    return remote != reference;
  }

  // ---- catalog / state persistence -------------------------------------------

  bool _loadCatalog(String catalogJson) {
    final error = StringBuffer();
    // Fail closed: a half-readable catalog must not silently drop entries.
    _catalog = PluginManifest.parseList(catalogJson, errorOut: error);
    if (_catalog.isEmpty && error.isNotEmpty) {
      EmoLogger().w('plugins: catalog $_catalogPath: $error');
    }
    return _catalog.isNotEmpty;
  }

  void _loadState() {
    _state.clear();
    String text;
    try {
      text = File(_statePath).readAsStringSync();
    } catch (_) {
      return; // no state yet: everything defaults to disabled/absent
    }
    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (document is! Map) {
      return;
    }
    final plugins = document['plugins'];
    if (plugins is! Map) {
      return;
    }
    plugins.forEach((key, value) {
      if (value is! Map) {
        return;
      }
      _state[key.toString()] = PluginState(
        enabled: value['enabled'] is bool ? value['enabled'] as bool : false,
        head: value['head'] is String ? value['head'] as String : '',
      );
    });
  }

  bool _saveState() {
    final plugins = <String, Object?>{
      for (final entry in _state.entries)
        entry.key: <String, Object?>{
          'enabled': entry.value.enabled,
          'head': entry.value.head,
        },
    };
    final root = <String, Object?>{'plugins': plugins};

    // QSaveFile pattern: temp file + rename, indented JSON like 1.x
    // (QJsonDocument::Indented).
    try {
      final temp = File('$_statePath.tmp');
      temp.writeAsStringSync(
          const JsonEncoder.withIndent('    ').convert(root),
          flush: true);
      temp.renameSync(_statePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _emitError(String message) {
    EmoLogger().w('plugins: $message');
    _onError?.call(message);
  }

  void _reportFinished(String name, String action, bool success, String message) {
    onOperationFinished?.call(name, action, success, message);
    // M6-T2: every terminal operation result lands in the audit — the
    // refused ones included (busy / already installed / porcelain
    // local-modification guard / content-integrity refusals all flow
    // through here, so a refusal is always 留痕).
    _audit.append(<String, Object?>{
      'ts': _auditTimestamp(),
      'kind': 'operation',
      'name': name,
      'action': action,
      'success': success,
      'message': message,
    });
  }

  // ---- planning ---------------------------------------------------------------

  /// Human-readable change list for the page's confirmation dialog:
  /// {name, action, title, details: [..]} or {error: "..."}. Never performs
  /// the operation and never runs git — the 1.x planOperation contract.
  /// M6-T2: every result (the accepted plan and the refusals alike) is
  /// appended to the audit file as a "plan" event before being returned.
  Map<String, Object?> planOperation(String name, String action) {
    final result = _planOperation(name, action);
    _auditPlan(name, action, result);
    return result;
  }

  void _auditPlan(String name, String action, Map<String, Object?> result) {
    final ok = !result.containsKey('error');
    _audit.append(<String, Object?>{
      'ts': _auditTimestamp(),
      'kind': 'plan',
      'name': name,
      'action': action,
      'ok': ok,
      if (ok) 'details': result['details'] else 'error': result['error'],
    });
  }

  static String _auditTimestamp() => DateTime.now().toUtc().toIso8601String();

  Map<String, Object?> _planOperation(String name, String action) {
    final manifest = manifestFor(name);
    if (!manifest.valid) {
      return <String, Object?>{'error': 'unknown plugin "$name"'};
    }
    final isInstall = action == 'install';
    final isUninstall = action == 'uninstall';
    final isUpdate = action == 'update';
    final isCheck = action == 'check';
    if (!isInstall && !isUninstall && !isUpdate && !isCheck) {
      return <String, Object?>{'error': 'unknown action "$action"'};
    }

    final details = <String>[];
    if (isInstall) {
      details.add('Clone ${manifest.url} (branch ${manifest.branch}, --depth 1)');
      details.add('Install into ${_pluginDir(name)}');
      if (manifest.isReplace) {
        details.add(
            'Mode replace: later updates replace this directory. A backup '
            'is kept and the replace is refused when local modifications '
            'are detected.');
      } else {
        details.add(
            'Mode check: later updates only compare the baseline — your '
            'local customizations are never overwritten.');
      }
    } else if (isUninstall) {
      details.add(
          'Delete ${_pluginDir(name)} including any local customizations '
          '(irreversible).');
      details.add(
          'Its paths disappear from the scripts option on the next launch.');
    } else if (isUpdate && !manifest.isReplace) {
      // check mode: "update" can only mean a comparison (the nativeization
      // plan's baseline flow needs a manual three-way merge; this batch
      // never rewrites customized files).
      final baseline = manifest.baseline.isEmpty
          ? '<recorded install HEAD>'
          : manifest.baseline;
      details.add(
          'Check only: compare the remote HEAD of ${manifest.url} '
          '(${manifest.branch}) against the baseline $baseline via git '
          'ls-remote. No local file is touched.');
      details.add(
          'Upstream moves ahead of the baseline require a manual merge of '
          'your local customizations; local customizations are never '
          'overwritten automatically.');
    } else if (isUpdate) {
      details.add('Re-clone ${manifest.url} (branch ${manifest.branch}) '
          'into $_pluginsRoot/.staging-$name');
      details.add('Move ${_pluginDir(name)} to '
          '$_pluginsRoot/.backup-$name (backup first)');
      details.add('Swap the fresh clone into ${_pluginDir(name)} atomically');
      details.add(
          'Refused when git reports local modifications — local '
          'customizations are never overwritten.');
    } else {
      details.add(
          'Run git ls-remote against ${manifest.url} (${manifest.branch}) '
          'and compare the result with the baseline/installed HEAD. No file '
          'is touched.');
    }

    return <String, Object?>{
      'name': name,
      'action': action,
      'title': '${_actionTitle(action)}: $name',
      'details': details,
    };
  }

  static String _actionTitle(String action) {
    if (action == 'install') {
      return 'Install plugin';
    }
    if (action == 'uninstall') {
      return 'Uninstall plugin';
    }
    if (action == 'update') {
      return 'Update plugin';
    }
    return 'Check for update';
  }

  // ---- operations -------------------------------------------------------------

  /// Takes effect at the next launch (the scripts option is assembled once
  /// at startup); the plugins page states this explicitly.
  void setEnabled(String name, bool enabled) {
    final manifest = manifestFor(name);
    if (!manifest.valid || !manifest.isScriptPlugin) {
      return;
    }
    if (enabled && !isInstalled(name)) {
      return;
    }
    final existing = _state[name];
    if (existing != null) {
      if (existing.enabled == enabled) {
        return;
      }
      existing.enabled = enabled;
    } else {
      if (!enabled) {
        return;
      }
      _state[name] = PluginState(enabled: true);
    }
    if (!_saveState()) {
      _emitError('cannot save $_statePath');
    }
    notifyListeners();
  }

  Future<void> install(String name) async {
    final manifest = manifestFor(name);
    if (!manifest.valid) {
      _reportFinished(
          name, 'install', false, 'unknown plugin "$name"');
      return;
    }
    // M6-T1: the integrity checkpoint is the front of the install chain —
    // an incomplete size+hash pair (缺一拒装) refuses BEFORE any git
    // command (including ls-remote) can run. The refusal flows through
    // _reportFinished, so it is audited like every other terminal result.
    final integrityError = manifest.integrityGateError();
    if (integrityError.isNotEmpty) {
      _reportFinished(name, 'install', false, integrityError);
      return;
    }
    if (_busy || isInstalled(name)) {
      _reportFinished(
          name,
          'install',
          false,
          _busy
              ? 'another operation is in progress'
              : 'already installed');
      return;
    }
    await _begin(name, _Action.install);
  }

  Future<void> uninstall(String name) async {
    final manifest = manifestFor(name);
    if (!manifest.valid) {
      _reportFinished(
          name, 'uninstall', false, 'unknown plugin "$name"');
      return;
    }
    if (_busy || !isInstalled(name)) {
      _reportFinished(
          name,
          'uninstall',
          false,
          _busy
              ? 'another operation is in progress'
              : 'not installed');
      return;
    }
    // File removal is bounded by the plugin directory size, and no
    // git/network is involved (the 1.x synchronous QDir::removeRecursively).
    final dir = Directory(_pluginDir(name));
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      _reportFinished(
          name, 'uninstall', false, 'failed to delete ${dir.path}');
      return;
    }
    _state.remove(name);
    _remoteHeads.remove(name);
    _locallyModified.remove(name);
    if (!_saveState()) {
      _emitError('cannot save $_statePath');
    }
    notifyListeners();
    _reportFinished(name, 'uninstall', true, 'uninstalled $name');
  }

  Future<void> update(String name) async {
    final manifest = manifestFor(name);
    if (!manifest.valid) {
      _reportFinished(name, 'update', false, 'unknown plugin "$name"');
      return;
    }
    if (_busy) {
      _reportFinished(name, 'update', false,
          'another operation is in progress');
      return;
    }
    if (!isInstalled(name)) {
      // Both modes compare against the local install; a missing install
      // is an install, not an update.
      _reportFinished(name, 'update', false, 'not installed');
      return;
    }
    // M6-T1: a replace-mode update re-clones and swaps — the destructive
    // path carries the same integrity gate as install (缺一拒装). A
    // check-mode update never touches files, so it needs no pin.
    if (manifest.isReplace) {
      final integrityError = manifest.integrityGateError();
      if (integrityError.isNotEmpty) {
        _reportFinished(name, 'update', false, integrityError);
        return;
      }
    }
    await _begin(name, _Action.update);
  }

  /// Remote check only: records the remote HEAD (update-available state),
  /// never touches files — for check-mode plugins this IS the "update".
  Future<void> checkForUpdate(String name) async {
    final manifest = manifestFor(name);
    if (!manifest.valid) {
      _reportFinished(name, 'check', false, 'unknown plugin "$name"');
      return;
    }
    if (_busy) {
      _reportFinished(name, 'check', false,
          'another operation is in progress');
      return;
    }
    await _begin(name, _Action.check);
  }

  Future<void> checkAll() async {
    final all = allManifests();
    if (_busy || all.isEmpty) {
      return;
    }
    _checkQueue.clear();
    for (final manifest in all) {
      _checkQueue.add(manifest.name);
    }
    // The whole queue drains before the returned future completes — the 1.x
    // Qt signal chain ran every hop synchronously inside checkAll().
    _checkAllCompleter = Completer<void>();
    unawaited(_begin(_checkQueue.removeAt(0), _Action.checkAll));
    return _checkAllCompleter!.future;
  }

  // ---- state machine ----------------------------------------------------------

  Future<void> _begin(String name, _Action action) async {
    _busy = true;
    _currentName = name;
    _action = action;
    _newHead = '';
    final manifest = manifestFor(name);
    switch (action) {
      case _Action.install:
        _step = _Step.clone;
        break;
      case _Action.update:
        // check mode never rewrites files — its "update" is the comparison.
        _step = manifest.isReplace ? _Step.status : _Step.lsRemote;
        break;
      case _Action.uninstall:
      case _Action.check:
      case _Action.checkAll:
        _step = _Step.lsRemote;
        break;
    }
    notifyListeners();
    await _runSteps();
  }

  Future<void> _runSteps() async {
    while (true) {
      final manifest = manifestFor(_currentName);
      assert(manifest.valid);

      switch (_step) {
        case _Step.clone:
          {
            final target = _action == _Action.install
                ? _pluginDir(_currentName)
                : _stagingDir;
            if (_action != _Action.install) {
              // Remove a leftover staging directory from a crashed run.
              if (Directory(_stagingDir).existsSync()) {
                try {
                  await Directory(_stagingDir)
                      .delete(recursive: true);
                } catch (_) {}
              }
            }
            final result = await _git.run(<String>[
              'clone',
              '--depth',
              '1',
              '--branch',
              manifest.branch,
              '--',
              manifest.url,
              target,
            ], _pluginsRoot);
            if (!_onCloneFinished(result)) {
              return;
            }
            continue;
          }
        case _Step.readHead:
          {
            final result = await _git.run(<String>['rev-parse', 'HEAD'],
                _action == _Action.install
                    ? _pluginDir(_currentName)
                    : _stagingDir);
            if (!await _onReadHeadFinished(result)) {
              return;
            }
            continue;
          }
        case _Step.lsRemote:
          {
            final result = await _git.run(<String>[
              'ls-remote',
              manifest.url,
              'refs/heads/${manifest.branch}',
            ], _pluginsRoot);
            if (!_onLsRemoteFinished(manifest, result)) {
              return;
            }
            continue;
          }
        case _Step.status:
          {
            final result = await _git.run(
                <String>['status', '--porcelain'],
                _pluginDir(_currentName));
            if (!await _onStatusFinished(manifest, result)) {
              return;
            }
            continue;
          }
      }
    }
  }

  bool _onCloneFinished(PluginGitResult result) {
    if (!result.started || result.exitCode != 0) {
      if (_action != _Action.install && Directory(_stagingDir).existsSync()) {
        try {
          Directory(_stagingDir).delete(recursive: true);
        } catch (_) {}
      }
      _fail(
          'git clone failed: ${result.standardError.trim()}');
      return false;
    }
    _step = _Step.readHead;
    return true;
  }

  Future<bool> _onReadHeadFinished(PluginGitResult result) async {
    if (!result.started || result.exitCode != 0) {
      _fail(
          'git rev-parse failed: ${result.standardError.trim()}');
      return false;
    }
    _newHead = result.standardOutput.trim();
    // M6-T1: content-integrity gate — the freshly cloned content is verified
    // against the manifest's pinned size+hash BEFORE the install is recorded
    // (or, for a replace-mode update, BEFORE the backup/swap touches
    // anything). A mismatch removes the just-cloned tree so no unverified
    // install ever becomes visible.
    final manifest = manifestFor(_currentName);
    if (manifest.isIntegrityPinned) {
      final cloned = _action == _Action.install
          ? _pluginDir(_currentName)
          : _stagingDir;
      final reason = await PluginContentIntegrity.verify(
        contentRoot: manifest.contentRoot(cloned),
        expectedSha256: manifest.sha256,
        expectedSize: manifest.sizeBytes!,
      );
      if (reason != null) {
        if (_action == _Action.install) {
          try {
            await Directory(_pluginDir(_currentName))
                .delete(recursive: true);
          } catch (_) {}
        } else if (Directory(_stagingDir).existsSync()) {
          try {
            await Directory(_stagingDir).delete(recursive: true);
          } catch (_) {}
        }
        _fail('content integrity check failed: $reason');
        return false;
      }
    }
    if (_action == _Action.install) {
      final state = PluginState(
        // Installing expresses the intent to use it.
        enabled: true,
        head: _newHead,
      );
      _state[_currentName] = state;
      if (!_saveState()) {
        _emitError('cannot save $_statePath');
      }
      notifyListeners();
      // The full HEAD is recorded here and in state.json alike (the page
      // shows it); no 12-char truncation in the message.
      _finish(true, 'installed $_currentName ($_newHead)');
      return false;
    }
    // Update (replace mode): swap staging into place.
    await _performSwap();
    return false;
  }

  bool _onLsRemoteFinished(PluginManifest manifest, PluginGitResult result) {
    if (!result.started || result.exitCode != 0) {
      _fail(
          'git ls-remote failed: ${result.standardError.trim()}');
      return false;
    }
    final line =
        result.standardOutput.split('\n').first; // section('\n', 0, 0)
    final remoteHead =
        line.split('\t').first.trim(); // section('\t', 0, 0).trimmed()
    if (remoteHead.isEmpty) {
      _fail('branch not found on remote');
      return false;
    }
    _remoteHeads[_currentName] = remoteHead;
    if (_action == _Action.check ||
        _action == _Action.checkAll ||
        (_action == _Action.update && !manifestFor(_currentName).isReplace)) {
      // check-mode "update" and plain checks: only the comparison, never
      // file changes. Additionally probe local modifications so the page
      // can show the customization badge.
      if (isInstalled(_currentName)) {
        _step = _Step.status;
        return true;
      }
      _finishCheck(manifest);
      return false;
    }
    // Update (replace mode): guard against local modifications first.
    _step = _Step.status;
    return true;
  }

  Future<bool> _onStatusFinished(
    PluginManifest manifest,
    PluginGitResult result,
  ) async {
    if (!result.started || result.exitCode != 0) {
      _fail('git status failed: ${result.standardError.trim()}');
      return false;
    }
    final modified = result.standardOutput.trim().isNotEmpty;
    _locallyModified[_currentName] = modified;

    // Only a replace-mode update may proceed to the swap; a check-mode
    // update is the comparison itself and must never clone or rewrite
    // files (本地定制永不覆盖) — same contract as Action::Check.
    if (_action == _Action.update && manifest.isReplace) {
      if (modified) {
        // Protective skip: local customizations win, always.
        _fail(
            'local modifications detected — refusing to replace '
            '(local customizations are never overwritten)');
        return false;
      }
      _stagingDir = '$_pluginsRoot/.staging-$_currentName';
      _step = _Step.clone;
      return true;
    }
    _finishCheck(manifest);
    return false;
  }

  void _finishCheck(PluginManifest manifest) {
    final remote = _remoteHeads[_currentName] ?? '';
    final state = _state[_currentName] ?? PluginState();
    final available = _updateAvailable(manifest, state);
    String message;
    if (!isInstalled(_currentName)) {
      message = 'not installed (remote HEAD ${_left(remote, 12)})';
    } else if (remote.isEmpty) {
      message = 'could not determine the remote HEAD';
    } else if (available) {
      final reference = manifest.baseline.isEmpty
          ? state.head
          : manifest.baseline;
      message = 'update available: $reference -> $remote';
    } else {
      message = 'up to date';
    }
    notifyListeners();
    _finish(true, message);
  }

  Future<void> _performSwap() async {
    final dir = _pluginDir(_currentName);
    final backup = '$_pluginsRoot/.backup-$_currentName';
    final oldHead = (_state[_currentName] ?? PluginState()).head;

    // Keep exactly one generation of backups.
    if (Directory(backup).existsSync()) {
      try {
        await Directory(backup).delete(recursive: true);
      } catch (_) {
        _fail('cannot remove the old backup $backup');
        return;
      }
    }
    if (!await _rename(Directory(dir), Directory(backup))) {
      _fail('cannot move $dir to $backup');
      return;
    }
    if (!await _rename(Directory(_stagingDir), Directory(dir))) {
      // best-effort restore
      await _rename(Directory(backup), Directory(dir));
      _fail('cannot move $_stagingDir to $dir');
      return;
    }
    (_state[_currentName] ??= PluginState()).head = _newHead;
    if (!_saveState()) {
      _emitError('cannot save $_statePath');
    }
    notifyListeners();
    _finish(
      true,
      'updated $_currentName (${_left(oldHead, 12)} -> '
      '${_left(_newHead, 12)}); old install kept at $backup',
    );
  }

  // QDir::rename on a directory; false when the move failed.
  static Future<bool> _rename(Directory from, Directory to) async {
    try {
      await from.rename(to.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  // QString::left(n) — the message truncation used by the check reports.
  static String _left(String value, int n) =>
      value.length <= n ? value : value.substring(0, n);

  String get _currentActionString {
    switch (_action) {
      case _Action.install:
        return 'install';
      case _Action.uninstall:
        return 'uninstall';
      case _Action.update:
        return 'update';
      case _Action.check:
      case _Action.checkAll:
        return 'check';
    }
  }

  void _finish(bool success, String message) {
    final action = _currentActionString;
    final name = _currentName;
    _busy = false;
    _currentName = '';
    _stagingDir = '';
    _reportFinished(name, action, success, message);
    notifyListeners();
    // The 1.x finish() deferred the next CheckAll hop onto the event loop
    // via signal re-entry; chaining it here keeps the same single-flight
    // serialization.
    if (_action == _Action.checkAll) {
      if (_checkQueue.isEmpty) {
        _checkAllCompleter?.complete();
        _checkAllCompleter = null;
      } else {
        final next = _checkQueue.removeAt(0);
        // Fire-and-forget: the next hop owns the motor from here.
        unawaited(_begin(next, _Action.checkAll));
      }
    }
  }

  void _fail(String message) {
    EmoLogger().w('plugins: $_currentName: $message');
    _finish(false, message);
  }
}

/// Append-only JSONL audit trail of the plugin operation decision chain
/// (M6-T2, roadmap §五 M6-T2).
///
/// One JSON object per line at `<appDataDir>/plugin_audit.jsonl` — an AppData
/// sibling of the `plugins/` directory, never a user-home or CWD file. The
/// file is opened in append mode for every write and is never rewritten,
/// rotated or truncated, so a crashed run leaves the history intact.
///
/// Two event kinds (see PluginManager for the emission points):
///   - "plan": one line per planOperation() call — the never-directly-
///     executed decision chain, carrying the planned change list (ok=true)
///     or the refusal reason (ok=false, e.g. unknown plugin/action);
///   - "operation": one line per terminal operation result, refused ones
///     included (busy, already installed, the porcelain local-modification
///     guard, content-integrity refusals).
///
/// [readEntries] skips lines that do not decode to a JSON object — a torn
/// write or manual edit degrades to fewer entries, never an error. Write
/// failures are logged and swallowed: the audit is observational only and
/// must never break a plugin operation.
class PluginAuditLog {
  PluginAuditLog(this.path);

  /// Absolute path of the JSONL file.
  final String path;

  /// Appends one event as a single JSON line. Creates the parent directory
  /// and the file on first use; existing bytes are never touched.
  void append(Map<String, Object?> event) {
    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      file.writeAsStringSync(
        '${jsonEncode(event)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      EmoLogger().w('plugins: cannot append to $path: $e');
    }
  }

  /// Reads every well-formed entry back. A missing file yields an empty
  /// list; corrupt (undecodable or non-object) lines are skipped, not
  /// repaired, and never throw.
  List<Map<String, Object?>> readEntries() {
    String text;
    try {
      text = File(path).readAsStringSync();
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
    final entries = <Map<String, Object?>>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is Map) {
        entries.add(<String, Object?>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        });
      }
    }
    return entries;
  }
}
