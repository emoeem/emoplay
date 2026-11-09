// Dart port of the mpv-emo src/music/MusicController.cpp PURE functions
// (PORT-MAP §1: isAudioMedia/lyricIndexAt/equalizerChain/bandFrequencies/
// presetGains). The engine-glue half of MusicController lives in
// music_controller.dart.
//
// mpv 0.37 verification (P5 convention — the 1.x考证 written down where it
// decides code, carried over verbatim): v0.37.0 has no builtin
// superequalizer/equalizer audio filter — filters/user_filters.c registers
// only af_lavfi and af_lavfi_bridge, and every other name routes through
// the libavfilter bridge (check_unknown_entry -> mp_lavfi_is_usable), so
// filter availability follows the linked libavfilter. FFmpeg n6.1's
// "superequalizer" (the name behind the equalizer-gui upstream) has 18
// FIXED bands (65.4 Hz..20 kHz, options "1b".."18b") with gains clamped to
// 0..20 — no negative gain, no "bands=" parameter, and a fixed 18-band
// grid, a poor fit for a 10-band ±12 dB UI. The FFmpeg "equalizer" filter
// (libavfilter/af_biquads.c) instead takes f (frequency, double), t
// (width_type, default q), w (width, double, default 1.0) and g (gain,
// double, -900..900), which maps 1:1 to a UI band. Hence the chain form
// used here:
//     equalizer=f=31.25:t=q:w=1.4:g=2,equalizer=f=62.5:...
// w=1.4 ≈ √2 is the Q-factor for one-octave-spaced bands.
library;

import 'package:emoplay/music/lrc_parser.dart' show LrcLine;

/// Extensions treated as audio-only media (music mode candidates). Case is
/// ignored; the list mirrors the player's common audio formats plus the
/// mainstream lossless/DSD ones. Video containers (mkv/mp4/...) are
/// deliberately absent: a video file must never enter music mode, whatever
/// the extension game is.
const List<String> _audioExtensions = <String>[
  'mp3', 'flac', 'm4a', 'aac', 'ogg', 'oga', //
  'opus', 'wav', 'wma', 'ape', 'mka', 'dsf', //
  'dff', 'aiff', 'aif', 'mpc', 'tak', 'tta', //
  'alac', 'au', 'ra', 'amr', //
];

/// The 10 fixed band frequencies (ISO one-octave grid), Hz.
/// Q≈√2 (w=1.4) matches the spacing.
const List<double> kBandFrequencies = <double>[
  31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, //
];

/// Clamped slider range / band count, shared with the UI pages
/// (1.x kBandCount / kMaxGain constants).
const int kBandCount = 10;
const double kMaxGain = 12.0;

/// Built-in preset names ("custom" is reached only by moving a band).
const List<String> kPresetNames = <String>['flat', 'bass', 'vocal', 'live'];

/// Equalizer preset tables, one gain per band (dB), ordered like
/// [kBandFrequencies]: 31.25 Hz .. 16 kHz. Integer dB keeps the persisted
/// values identical to what the sliders show.
const List<double> _flatGains = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const List<double> _bassGains = <double>[7, 6, 5, 3, 1, 0, 0, 0, 0, 0];
const List<double> _vocalGains = <double>[-1, 0, 1, 3, 4, 4, 3, 1, 0, -1];
const List<double> _liveGains = <double>[5, 4, 2, 0, -1, 0, 2, 4, 5, 5];

double _clampGain(double gain) =>
    gain < -kMaxGain ? -kMaxGain : (gain > kMaxGain ? kMaxGain : gain);

/// Whether [filename]'s extension marks pure audio (case-insensitive).
bool isAudioExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return _audioExtensions.contains(filename.substring(dot + 1).toLowerCase());
}

/// One mpv track-list entry shape the controller feeds in:
/// {type: "audio"|"video"|"sub", albumart?: bool}.
/// Media counts as pure audio when no track-list entry is a (non-cover)
/// video track and the filename has a known audio extension.
bool isAudioMedia(List<Map<String, Object?>> tracks, String filename) {
  for (final track in tracks) {
    if (track['type'] != 'video') {
      continue;
    }
    // Attached cover art is exposed as a video track with albumart=yes
    // (mpv 0.37 input.rst track-list/N/albumart). Audio files with an
    // embedded cover are still pure audio for music-mode purposes.
    if (track['albumart'] == true) {
      continue;
    }
    return false;
  }
  return isAudioExtension(filename);
}

/// Index of the line playing at [seconds]: the last line whose time is
/// <= seconds; -1 before the first line (and for empty input).
int lyricIndexAt(List<LrcLine> lines, double seconds) {
  var index = -1;
  for (var i = 0; i < lines.length; ++i) {
    // Tiny epsilon so exact hits still count after double rounding (a
    // parsed ".33" and mpv's time-pos can differ in the last bits). It must
    // stay far below the 1 ms .lrc granularity: 4.999999 s (one
    // microsecond before a 5 s line) is not "at" the line.
    if (lines[i].time <= seconds + 0.000000001) {
      index = i;
    } else {
      break; // sorted by time; nothing later can match either
    }
  }
  return index;
}

/// Built-in preset gains; unknown names fall back to "flat".
List<double> presetGains(String preset) {
  switch (preset) {
    case 'bass':
      return _bassGains;
    case 'vocal':
      return _vocalGains;
    case 'live':
      return _liveGains;
    default:
      return _flatGains; // "flat" and anything unknown
  }
}

/// mpv af chain for [gains] (one "equalizer" filter per band); empty string
/// when every gain is zero (no filter mounted). Gains are clamped to ±12 dB.
/// Anything not 10 bands yields "".
String equalizerChain(List<double> gains) {
  if (gains.length != kBandCount) {
    return '';
  }
  var audible = false;
  for (final gain in gains) {
    if (gain.abs() >= 0.001) {
      audible = true;
      break;
    }
  }
  if (!audible) {
    return ''; // all-zero: mount nothing (inert)
  }

  final parts = <String>[];
  for (var i = 0; i < kBandCount; ++i) {
    parts.add(
        'equalizer=f=${_formatFrequency(kBandFrequencies[i])}:t=q:w=1.4:'
        'g=${_formatGain(_clampGain(gains[i]))}');
  }
  return parts.join(',');
}

// QString::number(double) defaults to 6 significant digits ('g' format) and
// drops the trailing fraction when it is zero — "31.25" stays "31.25",
// "62.5" stays "62.5", "125" does NOT become "125.0", "7.0" becomes "7".
String _formatFrequency(double frequency) => _formatDouble(frequency);

String _formatGain(double gain) => _formatDouble(gain);

String _formatDouble(double value) {
  var text = value.toStringAsPrecision(6);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  // Guard against "-0" (a gain of -0.0 would print "-0" and mpv accepts it,
  // but the persisted/echoed value reads better normalized).
  if (text == '-0') {
    return '0';
  }
  return text;
}
