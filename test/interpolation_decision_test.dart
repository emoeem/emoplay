// Dart port of mpv-emo tests/test_interpolation_decision.cpp — pure-logic
// tests for the P5 v2 interpolation decision table: preset registry, vf
// entry assembly (mpv %len% quoting), admission blocks and the vf readback
// classification. No mpv, no GUI, no filesystem. Assertion values are
// copied verbatim from the C++ file (PORT-MAP §4).
import 'dart:convert';

import 'package:emoplay/quality/interpolation_decision.dart';
import 'package:flutter_test/flutter_test.dart';

MediaFacts factsWith({
  double fps = 0.0,
  bool isHdr = false,
  bool scriptAvailable = false,
  bool foreignVapoursynth = false,
}) {
  return MediaFacts()
    ..fps = fps
    ..isHdr = isHdr
    ..scriptAvailable = scriptAvailable
    ..foreignVapoursynth = foreignVapoursynth;
}

Map<String, Object?> vfEntryMap(String name, String label) {
  final map = <String, Object?>{'name': name};
  if (label.isNotEmpty) {
    map['label'] = label;
  }
  return map;
}

List<Object?> vfChain(List<Map<String, Object?>> entries) =>
    List<Object?>.of(entries);

void main() {
  test('presetTableMatchesDocumentedVsPresets', () {
    // The interpolation presets of docs/nativeization-plan.md §2.1
    // (mpv-Emo vs/ MEMC_* semantics); script names follow the preset ids.
    final all = presets;
    expect(all, hasLength(6));
    for (final preset in all) {
      expect(isKnownPreset(preset.id), isTrue);
      expect(preset.scriptName, '${preset.id}.vpy');
    }
    expect(isKnownPreset('MEMC_RIFE_STD'), isTrue);
    expect(isKnownPreset('MEMC_SVP_PRO'), isTrue);
    expect(scriptNameForPreset('MEMC_RIFE_STD'), 'MEMC_RIFE_STD.vpy');
  });

  test('unknownPresetRejected', () {
    expect(isKnownPreset('MEMC_MAGICAL'), isFalse);
    expect(isKnownPreset(''), isFalse);
    expect(scriptNameForPreset('MEMC_MAGICAL'), isEmpty);
  });

  test('admissionDisabledWhenSwitchOff', () {
    final facts = factsWith(fps: 24.0, scriptAvailable: true);
    expect(admission(facts, false), InterpolationBlock.disabled);
  });

  test('admissionBlocksUnknownAndHighFps', () {
    final facts = factsWith(scriptAvailable: true);

    // Unknown fps (idle or not yet decoded) never guesses.
    facts.fps = 0.0;
    expect(admission(facts, true), InterpolationBlock.fpsUnknown);

    // HFR sources have nothing to interpolate; the threshold matches the
    // v1 shader HFR avoidance (50 fps).
    facts.fps = 23.976;
    expect(admission(facts, true), InterpolationBlock.none);
    facts.fps = 49.9;
    expect(admission(facts, true), InterpolationBlock.none);
    facts.fps = 50.0;
    expect(admission(facts, true), InterpolationBlock.highFps);
    facts.fps = 60.0;
    expect(admission(facts, true), InterpolationBlock.highFps);
    expect(highFpsThreshold(), 50.0);
  });

  test('admissionBlocksHdr', () {
    // HDR sources are excluded (safety fallback semantics of the vs/
    // presets, docs/nativeization-plan.md §2.1).
    final facts =
        factsWith(fps: 24.0, scriptAvailable: true, isHdr: true);
    expect(admission(facts, true), InterpolationBlock.hdr);
  });

  test('admissionBlocksMissingScriptAndForeignFilter', () {
    final facts = factsWith(fps: 24.0);

    facts.scriptAvailable = false;
    expect(admission(facts, true), InterpolationBlock.scriptMissing);

    facts.scriptAvailable = true;
    facts.foreignVapoursynth = true;
    expect(
        admission(facts, true), InterpolationBlock.foreignVapoursynth);

    // A foreign filter wins even over every other condition.
    facts.fps = 0.0;
    facts.isHdr = true;
    expect(
        admission(facts, true), InterpolationBlock.foreignVapoursynth);
  });

  test('admissionPassesSdrLowFpsWithScript', () {
    final facts = factsWith(
        fps: 24.0,
        scriptAvailable: true,
        isHdr: false,
        foreignVapoursynth: false);
    expect(admission(facts, true), InterpolationBlock.none);
    expect(blockToString(InterpolationBlock.none), '');
    expect(blockToString(InterpolationBlock.hdr), 'hdr');
    expect(
        blockToString(InterpolationBlock.scriptMissing), 'script-missing');
  });

  test('vfEntryUsesLenQuoting', () {
    // mpv sub-param quoting: %len%<len bytes> — byte-exact, so the entry
    // parser can never split inside the path.
    const path = '/tmp/a.vpy';
    expect(vfEntry(path),
        '@emoplay-interp:vapoursynth=file=%10%/tmp/a.vpy');
    expect(vfEntry(path).startsWith('@emoplay-interp:vapoursynth=file=%'),
        isTrue);
    expect(entryLabel(), 'emoplay-interp');
    expect(vapoursynthFilterName(), 'vapoursynth');
  });

  test('vfEntrySurvivesMetacharacters', () {
    // Windows drive letters and separators must survive the ':'-separated
    // sub-param parser; the %len% prefix must carry the UTF-8 byte count.
    const path = 'C:/Users/tester/AppData/vs/MEMC_RIFE_STD.vpy';
    final entry = vfEntry(path);
    final expected = '@emoplay-interp:vapoursynth=file=%'
        '${utf8LengthOf(path)}%$path';
    expect(entry, expected);

    // Commas (the vf list separator) and brackets are protected the same
    // way: the whole path stays one value.
    const nasty = '/tmp/a,b[c].vpy';
    final nastyEntry = vfEntry(nasty);
    expect(nastyEntry.contains('=file=%'), isTrue);
    expect(nastyEntry.endsWith(nasty), isTrue);
  });

  test('vfReadbackClassification', () {
    // The vf property NODE readback: entries with name/label (get_obj_
    // settings_list). Only our exact label counts as ours.
    final ours = vfChain(<Map<String, Object?>>[
      vfEntryMap('scale', ''),
      vfEntryMap('vapoursynth', 'emoplay-interp'),
    ]);
    expect(vfHasLabeledEntry(ours), isTrue);
    expect(vfHasForeignVapoursynth(ours), isFalse);

    // No entry at all.
    const empty = <Object?>[];
    expect(vfHasLabeledEntry(empty), isFalse);
    expect(vfHasForeignVapoursynth(empty), isFalse);

    // An unlabeled vapoursynth entry is foreign (user config territory).
    final unlabeled =
        vfChain(<Map<String, Object?>>[vfEntryMap('vapoursynth', '')]);
    expect(vfHasLabeledEntry(unlabeled), isFalse);
    expect(vfHasForeignVapoursynth(unlabeled), isTrue);

    // A differently-labeled vapoursynth entry is foreign, too.
    final labeledOther = vfChain(
        <Map<String, Object?>>[vfEntryMap('vapoursynth', 'my-own-memc')]);
    expect(vfHasLabeledEntry(labeledOther), isFalse);
    expect(vfHasForeignVapoursynth(labeledOther), isTrue);

    // Same-name mismatch: a non-vapoursynth entry with our label is not
    // ours (and not foreign).
    final wrongName = vfChain(
        <Map<String, Object?>>[vfEntryMap('crop', 'emoplay-interp')]);
    expect(vfHasLabeledEntry(wrongName), isFalse);
    expect(vfHasForeignVapoursynth(wrongName), isFalse);
  });
}

/// QString::toUtf8().size() equivalent for the expected-string builders.
int utf8LengthOf(String value) => utf8.encode(value).length;
