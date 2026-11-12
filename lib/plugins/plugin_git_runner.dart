// Dart port of mpv-emo src/plugins/PluginGitRunner.{h,cpp} — the seam
// between PluginManager and the git binary (PORT-MAP §1: QProcess →
// dart:io Process).
//
// Result of one git command invocation.
//
// Unit tests inject a fake that answers synchronously; production runs
// `dart:io` Process.run asynchronously so a slow network clone never blocks
// the UI isolate.
//
// One instance serializes whole PluginManager operations; PluginManager
// guarantees at most one run() call is in flight at any time (single-flight
// invariant, kept from the 1.x QProcess design).
//
// M6-T1 (roadmap §五): this module also owns the content-integrity
// checkpoint ([PluginContentIntegrity]). The manifest may pin its asset with
// a size+sha256 pair (plugin_manifest.dart); PluginManager consults the
// integrity gate at the very FRONT of the install chain — no git command
// runs before it — and verifies the freshly cloned content against the pin
// before anything is recorded or swapped. The digest definition lives here
// because it is I/O over the installed tree, which the pure-logic manifest
// parser deliberately keeps out of its own scope.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Result of one git command invocation.
class PluginGitResult {
  const PluginGitResult({
    this.exitCode = -1,
    this.standardOutput = '',
    this.standardError = '',
    this.started = false,
  });

  final int exitCode;
  final String standardOutput;
  final String standardError;

  /// False when the git program could not be started at all.
  final bool started;
}

/// Seam between PluginManager and the git binary, mirroring the 1.x
/// PluginGitRunner abstract class.
abstract class PluginGitRunner {
  /// Runs `git <arguments>` with [workingDirectory] as the cwd. Exactly one
  /// result is reported per call.
  Future<PluginGitResult> run(
    List<String> arguments,
    String workingDirectory,
  );
}

/// Production implementation: one Process.run per call (the 1.x
/// QProcessPluginGitRunner). The future completes even when the git binary
/// is missing — [PluginGitResult.started] is false then, which the manager
/// maps to the same failure path as a non-zero exit.
class ProcessPluginGitRunner implements PluginGitRunner {
  const ProcessPluginGitRunner();

  @override
  Future<PluginGitResult> run(
    List<String> arguments,
    String workingDirectory,
  ) async {
    try {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return PluginGitResult(
        exitCode: result.exitCode,
        standardOutput: result.stdout as String,
        standardError: result.stderr as String,
        started: true,
      );
    } catch (e) {
      return PluginGitResult(
        started: false,
        standardError: e.toString(),
      );
    }
  }
}

/// Digest of one plugin content tree (see [PluginContentIntegrity.compute]).
class PluginContentDigest {
  const PluginContentDigest({required this.sha256, required this.sizeBytes});

  /// sha256 over the canonical per-file listing (see
  /// [PluginContentIntegrity] for the exact definition).
  final String sha256;

  /// Total bytes of the content files, checked independently of the digest.
  final int sizeBytes;
}

/// One content file folded into the digest listing.
class _ContentFile {
  const _ContentFile(this.relativePath, this.sha256Hex, this.sizeBytes);

  final String relativePath;
  final String sha256Hex;
  final int sizeBytes;
}

/// M6-T1 content-integrity checkpoint: computes and verifies the digest a
/// manifest pins (plugin_manifest.dart sizeBytes + sha256).
///
/// Canonical definition — deterministic, replayable, independent of
/// filesystem metadata (mtimes) and of the filesystem's listing order:
///   - regular files of the content tree only; any directory named ".git"
///     is pruned (the shallow clone's metadata is not plugin content);
///   - files are ordered by relative POSIX path (code-unit sort);
///   - the digest input is one line per file,
///     `<file-sha256-hex>  <relative-path>\n`;
///   - [PluginContentDigest.sizeBytes] is the sum of the file sizes and is
///     verified separately from the digest.
///
/// Symbolic links are skipped entirely (the digest must not depend on
/// whether a plugin ships a link or a copy of a file).
class PluginContentIntegrity {
  PluginContentIntegrity._();

  /// True when [value] has the manifest-level sha256 shape (64 hex chars).
  static bool isValidSha256(String value) => _sha256Pattern.hasMatch(value);

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Digest of the content tree at [contentRoot], or null when the directory
  /// does not exist. An existing but empty directory digests to the sha256
  /// of the empty string with size 0 — still deterministic.
  static Future<PluginContentDigest?> compute(String contentRoot) async {
    final root = Directory(contentRoot);
    if (!root.existsSync()) {
      return null;
    }
    final files = <_ContentFile>[];
    await _collect(root, '', files);
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final listing = StringBuffer();
    var totalBytes = 0;
    for (final file in files) {
      totalBytes += file.sizeBytes;
      listing
        ..write(file.sha256Hex)
        ..write('  ')
        ..write(file.relativePath)
        ..write('\n');
    }
    return PluginContentDigest(
      sha256: sha256.convert(utf8.encode(listing.toString())).toString(),
      sizeBytes: totalBytes,
    );
  }

  /// Verifies the content tree at [contentRoot] against a manifest's pinned
  /// size+hash pair. Returns null when the content matches; otherwise a
  /// human-readable refusal reason (the size check runs before the digest
  /// check, so each failure names exactly what diverged).
  static Future<String?> verify({
    required String contentRoot,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    final actual = await compute(contentRoot);
    if (actual == null) {
      return 'content directory "$contentRoot" is missing';
    }
    if (actual.sizeBytes != expectedSize) {
      return 'content size mismatch in "$contentRoot": expected '
          '$expectedSize bytes, found ${actual.sizeBytes}';
    }
    if (actual.sha256.toLowerCase() != expectedSha256.toLowerCase()) {
      return 'content sha256 mismatch in "$contentRoot": expected '
          '$expectedSha256, found ${actual.sha256}';
    }
    return null;
  }

  // Depth-first collection of the regular files under [dir], pruning ".git"
  // directories and skipping symbolic links. [prefix] carries the relative
  // POSIX path accumulated so far ('' at the content root).
  static Future<void> _collect(
    Directory dir,
    String prefix,
    List<_ContentFile> out,
  ) async {
    final entries = <FileSystemEntity>[];
    await for (final entity in dir.list(followLinks: false)) {
      entries.add(entity);
    }
    // Sort by base name so the recursion order is stable regardless of the
    // filesystem's listing order (compute sorts again globally, but a stable
    // walk keeps the sibling order meaningful for equal-name edge cases).
    entries.sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));
    for (final entity in entries) {
      final name = _baseName(entity.path);
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      if (entity is Directory) {
        if (name == '.git') {
          continue; // clone metadata is not plugin content
        }
        await _collect(entity, relative, out);
      } else if (entity is File) {
        final bytes = await entity.readAsBytes();
        out.add(_ContentFile(
          relative,
          sha256.convert(bytes).toString(),
          bytes.length,
        ));
      }
      // Links (followLinks: false) are deliberately skipped.
    }
  }

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
