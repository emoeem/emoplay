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
library;

import 'dart:convert';
import 'dart:io';

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
