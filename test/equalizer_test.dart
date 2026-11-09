import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/lrc_parser.dart';
import 'package:emoplay/music/music_controller.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

// Pure-logic tests for the music-mode decision rules (no engine) plus the
// equalizer mapping.
//
// Case-for-case port of mpv-emo tests/test_music_controller.cpp — the pure
// cases only. The C++ file's engine-integration cases
// (equalizerAppliesToEngine / equalizerDisableClearsChain /
// equalizerPersistedAcrossInstances) drove a real headless libmpv core to
// verify the af chain against the linked libavfilter; flutter_test has no
// libmpv, so those stay runtime-verifiable on a real machine only (same
// known-limit note as the 1.x test_music_page). The persistence mechanics
// they exercised are covered engine-free below by
// equalizerPersistedAcrossInstances.
void main() {
  Map<String, Object?> track(String type, {bool albumart = false}) {
    // Minimal track-list entry for the isAudioMedia() cases: {type: "audio"|
    // "video"|"sub"}, plus the optional albumart flag (mpv exposes embedded
    // cover art as a video track with albumart=yes).
    return <String, Object?>{
      'type': type,
      if (albumart) 'albumart': true,
    };
  }

  test('audioExtensionRules', () {
    expect(isAudioExtension('song.mp3'), isTrue);
    expect(isAudioExtension('SONG.MP3'), isTrue);
    expect(isAudioExtension('/music/a/song.FLAC'), isTrue);
    expect(isAudioExtension('song.opus'), isTrue);
    expect(isAudioExtension('movie.mkv'), isFalse);
    expect(isAudioExtension('song.mp4'), isFalse);
    expect(isAudioExtension('noextension'), isFalse);
    expect(isAudioExtension(''), isFalse);
  });

  test('audioMediaDetection', () {
    // Audio track list + audio extension -> music mode.
    expect(isAudioMedia([track('audio')], 'song.mp3'), isTrue);
    // A real video track disqualifies, even with an audio extension.
    expect(isAudioMedia([track('audio'), track('video')], 'song.mp3'), isFalse);
    expect(isAudioMedia([track('video')], 'movie.mkv'), isFalse);
    // Sub/lyric tracks neither qualify nor disqualify.
    expect(isAudioMedia([track('audio'), track('sub')], 'song.flac'), isTrue);
    // Audio extension but empty track list (file still probing): the rule
    // is "no video AND audio extension", so this qualifies.
    expect(isAudioMedia([], 'song.mp3'), isTrue);
    // Video container without tracks: no video track, but the extension
    // gate keeps it out of music mode.
    expect(isAudioMedia([], 'movie.mkv'), isFalse);
  });

  test('coverArtTrackDoesNotDisqualify', () {
    // mpv exposes an embedded cover as a video track with albumart=yes
    // (input.rst track-list/N/albumart); common on mp3/flac downloads.
    expect(
        isAudioMedia([track('audio'), track('video', albumart: true)],
            'song.mp3'),
        isTrue);
    // A real video next to the cover still disqualifies.
    expect(
        isAudioMedia(
            [track('video', albumart: true), track('video')], 'song.mp3'),
        isFalse);
  });

  test('lyricIndexBasics', () {
    final lines = <LrcLine>[
      const LrcLine(time: 10.0, text: 'one'),
      const LrcLine(time: 20.0, text: 'two'),
      const LrcLine(time: 30.0, text: 'three'),
    ];
    expect(lyricIndexAt(lines, 0.0), -1);
    expect(lyricIndexAt(lines, 9.999), -1);
    expect(lyricIndexAt(lines, 10.0), 0);
    expect(lyricIndexAt(lines, 19.0), 0);
    expect(lyricIndexAt(lines, 20.0), 1);
    expect(lyricIndexAt(lines, 999.0), 2);
    expect(lyricIndexAt(const [], 10.0), -1);
  });

  test('lyricIndexExactAndPastEnd', () {
    // Exact hits count (epsilon guard against double rounding), and an
    // empty line at a timestamp is still an indexable line.
    final lines = <LrcLine>[
      const LrcLine(time: 5.0, text: ''),
      const LrcLine(time: 5.0, text: 'repeat'),
    ];
    expect(lyricIndexAt(lines, 4.999999), -1);
    expect(lyricIndexAt(lines, 5.0), 1);
  });

  test('nullEngineStaysIdle', () {
    // Controller without an engine: nothing may crash and audioMode stays
    // false after a reevaluate().
    final controller = MusicController();
    controller.reevaluate();
    expect(controller.audioMode, isFalse);
    expect(controller.lyrics, isEmpty);
    expect(controller.lyricIndex, -1);

    // EQ mutations without AppSettings must not crash either (the page
    // drives these methods): state changes stay in memory only.
    controller.setEqualizerEnabled(true);
    controller.applyEqualizerPreset('bass');
    controller.setEqualizerBand(0, 3);
    expect(controller.equalizerEnabled, isTrue);
    expect(controller.equalizerPreset, 'custom');
    expect(controller.equalizerGains[0], 3.0);
  });

  test('equalizerChainAllZeroIsEmpty', () {
    // All-zero gains mount nothing (inert, like the P5 tier=off rule).
    expect(equalizerChain(List<double>.filled(10, 0.0)), '');
    // Wrong band count is refused outright.
    expect(equalizerChain(List<double>.filled(3, 1.0)), '');
  });

  test('equalizerChainFormat', () {
    // One peaking "equalizer" filter per band, Q-factor width 1.4
    // (one octave), comma-joined in band order. Verified against
    // FFmpeg n6.1 libavfilter/af_biquads.c (f/t/w/g options).
    final gains = List<double>.filled(10, 0.0);
    gains[0] = 7.0;
    gains[9] = -2.0;
    expect(
        equalizerChain(gains),
        'equalizer=f=31.25:t=q:w=1.4:g=7,'
        'equalizer=f=62.5:t=q:w=1.4:g=0,'
        'equalizer=f=125:t=q:w=1.4:g=0,'
        'equalizer=f=250:t=q:w=1.4:g=0,'
        'equalizer=f=500:t=q:w=1.4:g=0,'
        'equalizer=f=1000:t=q:w=1.4:g=0,'
        'equalizer=f=2000:t=q:w=1.4:g=0,'
        'equalizer=f=4000:t=q:w=1.4:g=0,'
        'equalizer=f=8000:t=q:w=1.4:g=0,'
        'equalizer=f=16000:t=q:w=1.4:g=-2');
    expect(kBandFrequencies.length, 10);
    expect(kBandFrequencies.first, 31.25);
    expect(kBandFrequencies.last, 16000.0);
  });

  test('equalizerChainClampsGains', () {
    // Out-of-range gains clamp to the slider range (±12 dB).
    final gains = List<double>.filled(10, 0.0);
    gains[0] = 30.0;
    gains[1] = -30.0;
    final chain = equalizerChain(gains);
    expect(chain, contains('equalizer=f=31.25:t=q:w=1.4:g=12,'));
    expect(chain, contains('equalizer=f=62.5:t=q:w=1.4:g=-12,'));
  });

  test('presetTables', () {
    expect(kPresetNames, ['flat', 'bass', 'vocal', 'live']);

    final flat = presetGains('flat');
    expect(flat.length, 10);
    expect(flat.every((g) => g == 0.0), isTrue);

    expect(presetGains('bass'), [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]);
    expect(presetGains('vocal'), [-1, 0, 1, 3, 4, 4, 3, 1, 0, -1]);
    expect(presetGains('live'), [5, 4, 2, 0, -1, 0, 2, 4, 5, 5]);

    // Unknown preset names fall back to flat instead of crashing.
    expect(presetGains('nope'), flat);
  });

  test('equalizerPersistedAcrossInstances', () async {
    // Engine-free port of the persistence half of
    // equalizerPersistedAcrossInstances: a fresh controller restores the
    // persisted EQ state (enabled/preset/gains) from settings.json; a
    // disabled state persists as inert. The af-application half ran against
    // a real libmpv in 1.x and stays runtime-verifiable only.
    final dir = Directory.systemTemp.createTempSync('emoplay-eq-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = '${dir.path}/settings.json';
    {
      final settings = EmoPlaySettings(file);
      final controller = MusicController(settings: settings);
      await controller.setEqualizerEnabled(true);
      await controller.applyEqualizerPreset('bass');
      await controller.setEqualizerBand(2, 4);
      expect(controller.equalizerPreset, 'custom');
      // persistEqualizer() already saved through EmoPlaySettings.save().
    }
    final reloaded = EmoPlaySettings(file)..load();
    final controller = MusicController(settings: reloaded);
    expect(controller.equalizerEnabled, isTrue);
    expect(controller.equalizerPreset, 'custom');
    expect(controller.equalizerGains[2], 4.0);

    // Disabled state persists as inert.
    await controller.setEqualizerEnabled(false);
    final reloaded2 = EmoPlaySettings(file)..load();
    final controller2 = MusicController(settings: reloaded2);
    expect(controller2.equalizerEnabled, isFalse);
  });
}
