import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Diagnostic probe (2026-11-11 "no sound" report): opens a fixture through
/// the bundled fork libmpv with default ao and reports what mpv actually
/// selected. Skips everywhere the fixture doesn't exist (CI), so only the
/// machine that reproduces the report pays for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  test('AUDIO_PROBE: bundled libmpv reaches a real audio output', () async {
    const fixture = '/tmp/emoplay-test/audio.mp3';
    if (!File(fixture).existsSync()) {
      // ignore: avoid_print
      print('AUDIO_PROBE fixture missing — skipped');
      return;
    }
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.trace),
    );
    final logs = <String>[];
    player.stream.log.listen((e) => logs.add('${e.level}: ${e.text}'));
    await player.setVolume(100);
    // Loop so the pulse sink-input stays observable while the orchestrator
    // samples `pactl list sink-inputs` from outside the process.
    await player.setPlaylistMode(PlaylistMode.loop);
    await player.open(Media(fixture));
    await Future<void>.delayed(const Duration(seconds: 12));
    final pp = player.platform as NativePlayer;
    final ao = await pp.getProperty('ao');
    // ignore: avoid_print
    print('AUDIO_PROBE default-ao="$ao"');
    // ignore: avoid_print
    print('AUDIO_PROBE audio log lines:');
    for (final line in logs) {
      if (line.contains('ao') ||
          line.contains('audio') ||
          line.contains('pulse') ||
          line.contains('alsa')) {
        // ignore: avoid_print
        print('  $line');
      }
    }
    await player.dispose();

    // Second pass: pin the AO explicitly and see whether pulse comes up.
    final player2 = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.trace),
    );
    final logs2 = <String>[];
    player2.stream.log.listen((e) => logs2.add('${e.level}: ${e.text}'));
    final pp2 = player2.platform as NativePlayer;
    await pp2.setProperty('ao', 'pulse');
    await player2.open(Media(fixture));
    await Future<void>.delayed(const Duration(seconds: 3));
    final ao2 = await pp2.getProperty('ao');
    // ignore: avoid_print
    print('AUDIO_PROBE pulse-pinned ao="$ao2"');
    for (final line in logs2) {
      if (line.contains('ao') || line.contains('pulse')) {
        // ignore: avoid_print
        print('  $line');
      }
    }
    await player2.dispose();
    expect(ao2, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
