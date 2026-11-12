// Dart port of mpv-emo src/plugins/PluginManifest.{h,cpp} (A-class pure
// logic, PORT-MAP §1). Field semantics and validation messages are the 1.x
// ones verbatim; they are the behavioural contract the ported tests assert.
//
// One entry of a manager.json-style plugin source manifest. Field semantics
// follow mpv-Emo's manager.json so existing upstream sources can be imported
// with a low migration cost (docs/nativeization-plan.md §4.1):
//
//   name        unique plugin id; characters [A-Za-z0-9_-] (the upstream
//               manager.json mixes "uosc_danmaku", "hdr-toys", "anime4k"),
//               which also keeps it safe to use as a directory name
//   url         upstream git repository (required)
//   branch      tracked branch (default "main")
//   source      subtree inside the upstream repo that holds the plugin
//               content; "." means the whole repository (default ".")
//   destination install target as declared by the manifest, e.g.
//               "scripts/uosc" or "shaders/Anime4K/glsl" (required)
//   mode        "check" (default): update checks only compare the remote
//               HEAD against |baseline| and never touch installed files;
//               "replace": updates re-clone and atomically swap the install
//               (with a backup, and a protective skip on local modifications)
//   baseline    upstream commit/tag the local customizations are based on;
//               empty when the manifest does not declare one
//
// M6-T1 asset integrity (optional pair, roadmap §五 M6-T1):
//   sizeBytes   total byte size of the pinned content tree (see
//               PluginContentIntegrity in plugin_git_runner.dart); absent in
//               the 1.x manager.json form
//   sha256      sha256 hex digest of the same content tree; absent in the
//               1.x form. The pair is all-or-nothing at install time
//               (缺一拒装 — [integrityGateError]): declaring only one of the
//               two refuses the install. A manifest that declares neither
//               keeps the exact 1.x behaviour.
//
// Parsing is pure logic (no I/O, no git) so it can be unit-tested directly.
library;

import 'dart:convert';

/// One manifest entry. A manifest that failed validation has [valid] == false
/// and [error] set; the other fields may then be meaningless.
class PluginManifest {
  PluginManifest({
    this.name = '',
    this.url = '',
    this.branch = '',
    this.source = '',
    this.destination = '',
    this.mode = '',
    this.baseline = '',
    this.sizeBytes,
    this.sha256 = '',
    this.valid = false,
    this.error = '',
  });

  String name;
  String url;
  String branch;
  String source;
  String destination;
  String mode;
  String baseline;

  // M6-T1 asset integrity pair (null / '' = not declared).
  int? sizeBytes;
  String sha256;

  bool valid;
  String error;

  bool get isReplace => mode == 'replace';

  /// True when the manifest declares any asset-integrity field at all.
  bool get hasIntegrityFields => sha256.isNotEmpty || sizeBytes != null;

  /// True when the size+hash pair is complete — the precondition for
  /// verifying installed content against the manifest (M6-T1).
  bool get isIntegrityPinned => sha256.isNotEmpty && sizeBytes != null;

  /// M6-T1 install gate (缺一拒装): the integrity fields form an
  /// all-or-nothing pair. A manifest that pins only one of sizeBytes/sha256
  /// refuses the install and returns the refusal reason here; a manifest
  /// that declares neither (the 1.x manager.json form) installs exactly as
  /// before and returns the empty string. Malformed values (bad hex, negative
  /// sizes) never get this far — [parse] rejects them outright.
  String integrityGateError() {
    if (sha256.isEmpty && sizeBytes == null) {
      return '';
    }
    if (sha256.isEmpty) {
      return 'manifest "$name" declares sizeBytes without sha256 — asset '
          'integrity needs both fields (size+hash), refusing to install';
    }
    if (sizeBytes == null) {
      return 'manifest "$name" declares sha256 without sizeBytes — asset '
          'integrity needs both fields (size+hash), refusing to install';
    }
    return '';
  }

  /// Roundtrips through [parse] with identical field values (M6-T1 field
  /// roundtrip contract). The integrity keys are emitted only when declared,
  /// so unpinned entries keep the exact 1.x manager.json field shape.
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'url': url,
        'branch': branch,
        'source': source,
        'destination': destination,
        'mode': mode,
        'baseline': baseline,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (sha256.isNotEmpty) 'sha256': sha256,
      };

  /// Script plugins install under a scripts/ destination and can be appended
  /// to mpv's --scripts path list; shader/asset plugins are only distributed
  /// as files (P8 v1 does not mount them automatically).
  bool get isScriptPlugin {
    // manager.json destinations are either "scripts/<name>" (or a single
    // file "scripts/<name>.lua") for script plugins, or "shaders/<...>" for
    // shader packs. Only the first kind feeds mpv's --scripts option.
    return destination.startsWith('scripts/');
  }

  /// Directory inside an installed plugin clone that holds the plugin
  /// content: the manifest [source] subtree (the clone root itself when
  /// source is "."). [pluginDir] is the installed clone directory.
  String contentRoot(String pluginDir) {
    if (source == '.') {
      return pluginDir;
    }
    return '$pluginDir/$source';
  }

  /// Parses one manifest object. Missing required fields (name/url/
  /// destination), out-of-domain names, path traversal in source/
  /// destination, or a mode other than "check"/"replace" fail validation;
  /// absent branch/source/mode/baseline fall back to their defaults.
  static PluginManifest parse(Object? object) {
    final manifest = PluginManifest()..valid = false;

    if (object is! Map) {
      return manifest..error = 'manifest entry is not an object';
    }

    String error = '';
    String name = '';
    String url = '';
    String destination = '';
    String branch = '';
    String source = '';
    String mode = '';
    String baseline = '';
    String sha256 = '';
    int? sizeBytes;

    if (!_readString(object, 'name', (v) => name = v, (e) => error = e) ||
        !_readString(object, 'url', (v) => url = v, (e) => error = e) ||
        !_readString(
            object, 'destination', (v) => destination = v, (e) => error = e) ||
        !_readString(object, 'branch', (v) => branch = v, (e) => error = e) ||
        !_readString(object, 'source', (v) => source = v, (e) => error = e) ||
        !_readString(object, 'mode', (v) => mode = v, (e) => error = e) ||
        !_readString(
            object, 'baseline', (v) => baseline = v, (e) => error = e) ||
        !_readString(object, 'sha256', (v) => sha256 = v, (e) => error = e) ||
        !_readInt(object, 'sizeBytes', (v) => sizeBytes = v, (e) => error = e)) {
      return manifest..error = error;
    }

    if (name.isEmpty) {
      return manifest..error = 'missing required field "name"';
    }
    if (!_namePattern.hasMatch(name)) {
      return manifest
        ..error = 'invalid plugin name "$name" (allowed: A-Z a-z 0-9 _ -)';
    }
    if (url.isEmpty) {
      return manifest..error = 'missing required field "url" for "$name"';
    }
    if (destination.isEmpty) {
      return manifest
        ..error = 'missing required field "destination" for "$name"';
    }
    if (!isSafeRelativePath(destination)) {
      return manifest
        ..error = 'unsafe destination path "$destination" for "$name"';
    }
    if (source.isNotEmpty && source != '.' && !isSafeRelativePath(source)) {
      return manifest..error = 'unsafe source path "$source" for "$name"';
    }
    // mode: "check" (default) or "replace"; anything else is rejected so a
    // typo can never silently pick the destructive semantics.
    if (mode.isNotEmpty && mode != 'check' && mode != 'replace') {
      return manifest
        ..error =
            'invalid mode "$mode" for "$name" (expected "check" or "replace")';
    }
    // M6-T1: a declared sha256 must be a well-formed 64-hex digest and a
    // declared sizeBytes a non-negative byte count. Parse stays accepting
    // for entries that declare neither (the 1.x manager.json has no
    // integrity fields); the size+hash PAIR requirement (缺一拒装) is the
    // install gate — see [integrityGateError].
    if (sha256.isNotEmpty && !_sha256Pattern.hasMatch(sha256)) {
      return manifest
        ..error =
            'field "sha256" must be a 64-character hex digest for "$name"';
    }
    if (sizeBytes != null && sizeBytes! < 0) {
      return manifest..error = 'field "sizeBytes" must be >= 0 for "$name"';
    }

    return manifest
      ..valid = true
      ..name = name
      ..url = url
      ..destination = destination
      // Defaults per nativeization-plan §4.1/§4.2: branch main, source "."
      // (whole repo), mode check (never destructive by default), no baseline.
      ..branch = branch.isEmpty ? 'main' : branch
      ..source = source.isEmpty ? '.' : source
      ..mode = mode.isEmpty ? 'check' : mode
      ..baseline = baseline
      ..sizeBytes = sizeBytes
      ..sha256 = sha256;
  }

  /// Parses a manifest document: either the mpv-Emo form
  /// `{"sources": [ ... ]}` or a bare JSON array of entries. Returns an empty
  /// list and sets [errorOut] on malformed input or duplicate names (plugin
  /// ids are unique). |errorOut| mirrors the C++ `QString *error = nullptr`
  /// out-parameter: null means the caller does not need the reason.
  static List<PluginManifest> parseList(String json, {StringBuffer? errorOut}) {
    // Assignment semantics: each failure OVERWRITES the error, exactly like
    // `*error = message` did in C++.
    void fail(String message) {
      errorOut?.clear();
      errorOut?.write(message);
    }

    Object? document;
    try {
      document = jsonDecode(json);
    } on FormatException catch (e) {
      // QJsonParseError::errorString() wording kept where it is observable.
      fail('manifest is not valid JSON: ${e.message}');
      return const [];
    }

    if (document is! Map && document is! List) {
      fail('manifest must be an object or an array');
      return const [];
    }

    List<Object?> entries;
    if (document is Map) {
      // mpv-Emo manager.json form: {"sources": [ ... ]}.
      final sources = document['sources'];
      if (sources is! List) {
        fail('manifest object lacks a "sources" array');
        return const [];
      }
      entries = sources;
    } else {
      entries = document as List<Object?>;
    }

    final manifests = <PluginManifest>[];
    final seenNames = <String>{};
    for (var i = 0; i < entries.length; ++i) {
      if (entries[i] is! Map) {
        fail('manifest entry $i is not an object');
        return const [];
      }
      final manifest = PluginManifest.parse(entries[i]);
      if (!manifest.valid) {
        fail('manifest entry $i: ${manifest.error}');
        return const [];
      }
      if (seenNames.contains(manifest.name)) {
        fail('duplicate plugin name "${manifest.name}"');
        return const [];
      }
      seenNames.add(manifest.name);
      manifests.add(manifest);
    }
    return manifests;
  }

  // Plugin ids become directory names under <AppData>/plugins/, so the
  // charset is deliberately narrow. This mirrors the ids actually used by
  // mpv-Emo's manager.json (uosc, uosc_danmaku, anime4k, file_browser,
  // hdr-toys, trakt_scrobble) while excluding path separators and dots (no
  // traversal, no hidden directories).
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9_-]+$');

  // A declared sha256 is a lowercase/uppercase 64-hex digest (M6-T1). The
  // digest itself is defined by PluginContentIntegrity (plugin_git_runner.dart).
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  // Relative paths (manifest source/destination) must stay inside the tree
  // they are applied to: absolute paths, ".." segments and backslashes are
  // rejected.
  static bool isSafeRelativePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        path.contains('\\')) {
      return false;
    }
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        return false;
      }
    }
    return true;
  }

  // Reads a string field. Returns false when the key is present but is not a
  // JSON string (type confusion would silently produce "" otherwise).
  // QJsonValue semantics kept: an ABSENT key is optional, an explicit JSON
  // null fails the string check exactly like it failed isString() in C++.
  static bool _readString(
    Map<Object?, Object?> object,
    String key,
    void Function(String value) assign,
    void Function(String error) fail,
  ) {
    if (!object.containsKey(key)) {
      return true; // absent: optional, stays at the caller's default
    }
    final json = object[key];
    if (json is! String) {
      fail('field "$key" must be a string');
      return false;
    }
    assign(json);
    return true;
  }

  // Reads an integer field. Mirrors _readString: an absent key is optional,
  // an explicit JSON null, a double (1.5), a bool or a string ("42") fails —
  // nothing may silently coerce into the byte-count field (M6-T1).
  static bool _readInt(
    Map<Object?, Object?> object,
    String key,
    void Function(int value) assign,
    void Function(String error) fail,
  ) {
    if (!object.containsKey(key)) {
      return true; // absent: optional, stays at the caller's default
    }
    final json = object[key];
    if (json is! int) {
      fail('field "$key" must be an integer');
      return false;
    }
    assign(json);
    return true;
  }
}
