// Tests for the 2.0-only glue the 1.x port adds on top of the pure tables:
//
//   1. the engine string readback parsers in quality_engine.dart, with the
//      serialization forms MEASURED on the shipped libmpv (probed
//      2026-11-10, see native_quality_engine.dart);
//   2. the three MobX controllers driven by a fake MpvQualityEngine (the
//      1.x controllers' "engine may be null / fake in tests" contract),
//      covering: inert-at-off, the clr+append change-list applier, the
//      >=2/s session demotion + new-file reset, the one-shot VapourSynth
//      probe fallback (persisted off + vsUnavailable), the successful
//      mount/admission cycle, and the ICC verify/fail/restore contract.
import 'dart:async';
import 'dart:io';

import 'package:emoplay/quality/icc_controller.dart';
import 'package:emoplay/quality/interpolation_controller.dart';
import 'package:emoplay/quality/interpolation_decision.dart';
import 'package:emoplay/quality/quality_controller.dart';
import 'package:emoplay/quality/quality_engine.dart';
import 'package:emoplay/settings/emoplay_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// String readback parsers
// ---------------------------------------------------------------------------

void main() {
  group('parseVfChain (measured string forms)', () {
    test('emptyReadbackYieldsEmptyChain', () {
      expect(parseVfChain(''), isEmpty);
    });

    test('labeledEntryKeepsLabel', () {
      // Probe: `@emoplay-interp:crop=w=%3%100:h=100` printed as
      // `@emoplay-interp:crop=w=100:h=100` (%len% quoting parsed away).
      final chain = parseVfChain('@emoplay-interp:crop=w=100:h=100');
      expect(chain, hasLength(1));
      expect(chain.single['label'], 'emoplay-interp');
      expect(chain.single['name'], 'crop');
    });

    test('twoEntriesAreCommaJoined', () {
      // Probe: appended labeled crop then scale printed as
      // `@emoplay-interp:crop=w=100:h=100,scale=w=64:h=64`.
      final chain =
          parseVfChain('@emoplay-interp:crop=w=100:h=100,scale=w=64:h=64');
      expect(chain, hasLength(2));
      expect(chain[0]['name'], 'crop');
      expect(chain[0]['label'], 'emoplay-interp');
      expect(chain[1]['name'], 'scale');
      expect(chain[1].containsKey('label'), isFalse);
    });

    test('classificationSurvivesTheStringForm', () {
      // The decision functions must see our entry as ours through the
      // parsed string form (the probe fallback depends on it).
      final ours = parseVfChain(
          'scale=w=64:h=64,@emoplay-interp:vapoursynth=file=/tmp/a.vpy');
      expect(vfHasLabeledEntry(ours), isTrue);
      expect(vfHasForeignVapoursynth(ours), isFalse);

      final foreign = parseVfChain('vapoursynth=file=/tmp/x.vpy');
      expect(vfHasLabeledEntry(foreign), isFalse);
      expect(vfHasForeignVapoursynth(foreign), isTrue);

      final foreignLabeled =
          parseVfChain('@my-own-memc:vapoursynth=file=/tmp/x.vpy');
      expect(vfHasLabeledEntry(foreignLabeled), isFalse);
      expect(vfHasForeignVapoursynth(foreignLabeled), isTrue);
    });
  });

  group('parsePathList (measured string forms)', () {
    test('changeListBuiltListPrintsColonJoined', () {
      // Probe: clr + two appends printed `/tmp/one.glsl:/tmp/two.glsl`.
      expect(parsePathList('/tmp/one.glsl:/tmp/two.glsl'),
          <String>['/tmp/one.glsl', '/tmp/two.glsl']);
    });

    test('stringSetListEchoesCommaForm', () {
      // Probe: set_property_string('/tmp/one.glsl,/tmp/two.glsl') echoed
      // the comma form verbatim.
      expect(parsePathList('/tmp/one.glsl,/tmp/two.glsl'),
          <String>['/tmp/one.glsl', '/tmp/two.glsl']);
    });

    test('emptyReadbackYieldsEmptyList', () {
      expect(parsePathList(''), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Controllers against a fake engine
  // -------------------------------------------------------------------------

  group('QualityController (fake engine)', () {
    late Directory tempDir;
    late EmoPlaySettings settings;
    late FakeEngine engine;
    late QualityController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('emoplay_quality_');
      settings = EmoPlaySettings(p.join(tempDir.path, 'settings.json'));
      settings.load();
      engine = FakeEngine();
      engine.videoParamsMap = <String, Object?>{
        'w': 1920,
        'h': 1080,
        'primaries': 'bt.709',
        'gamma': 'bt.1886',
      };
      engine.fps = 23.976;
      engine.path = '[VCB-Studio] Kimi no Na wa [Ma10p_1080p].mkv';
      controller = QualityController(
        settings: settings,
        shadersDir: p.join(tempDir.path, 'shaders'),
        onError: (_) {},
      );
      await controller.attachEngine(engine);
      // A full-enough Anime4K "Fast" install on disk (flat layout — the
      // resolver also matches nested paths, covered by the pure tests).
      final shadersDir = Directory(controller.shadersDir);
      await shadersDir.create(recursive: true);
      for (final name in <String>[
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Upscale_CNN_x2_M.glsl',
        'Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K_AutoDownscalePre_x4.glsl',
        'Anime4K_Upscale_CNN_x2_S.glsl',
      ]) {
        await File(p.join(shadersDir.path, name))
            .writeAsString('//!HOOK LUMA');
      }
      await controller.startup();
    });

    tearDown(() async {
      controller.detachEngine();
      await tempDir.delete(recursive: true);
    });

    test('offTierAndNeverEngagedWritesNothing', () async {
      await controller.applyProfile();
      expect(engine.setProperties, isEmpty);
      expect(engine.commands, isEmpty);
    });

    test('highTierAppliesScalarsAndClrAppend', () async {
      controller.setQualityTier('high');
      await controller.applyProfile();
      // Decision table (FHD anime -> group A, file name hint "animated").
      expect(engine.propertySet('scale'), 'ewa_lanczossharp');
      expect(engine.propertySet('deband'), 'yes');
      expect(engine.propertySet('tone-mapping'), 'auto');
      final clr = engine.commands.firstWhere(
          (command) => command.length > 3 && command[2] == 'clr');
      expect(clr.take(3), <String>['change-list', 'glsl-shaders', 'clr']);
      final appended = engine.commands
          .where((command) => command.length > 3 && command[2] == 'append')
          .map((command) => command[3])
          .toList();
      // Manual list empty + engine selection resolved under shadersDir.
      expect(appended, hasLength(6));
      expect(appended.first,
          p.join(controller.shadersDir, 'Anime4K_Clamp_Highlights.glsl'));
    });

    test('sustainedDropRateDemotesTierForTheSession', () async {
      controller.setQualityTier('high');
      await controller.applyProfile();
      // >= 2 dropped frames per second demotes the ACTIVE tier to low.
      engine.commands.clear();
      controller.notifyDropFrameRate(2.0);
      await controller.applyProfile();
      expect(controller.autoDowngraded, isTrue);
      expect(engine.propertySet('scale'), 'lanczos'); // low-tier scale
      final appended = engine.commands
          .where((command) => command.length > 3 && command[2] == 'append')
          .map((command) => command[3])
          .toList();
      expect(appended, isEmpty); // low tier never mounts shaders
      // The persisted user tier is untouched.
      expect(settings.qualityTier, 'high');

      // A new file resets the demotion: the user's tier comes back.
      engine.fireFileLoaded();
      await pumpEventQueue();
      await controller.applyProfile();
      expect(controller.autoDowngraded, isFalse);
      expect(engine.propertySet('scale'), 'ewa_lanczossharp');
    });

    test('disengagingResetsToMpvDefaults', () async {
      controller.setQualityTier('high');
      await controller.applyProfile();
      controller.setQualityTier('off');
      await controller.applyProfile();
      expect(engine.propertySet('scale'), 'lanczos');
      expect(engine.propertySet('deband'), 'no');
      expect(engine.propertySet('tone-mapping'), 'auto');
      expect(engine.propertySet('target-colorspace-hint'), 'no');
      // The shader list was touched while active, so it is cleared too.
      expect(engine.mountedShaders, isEmpty);
    });
  });

  group('InterpolationController (fake engine)', () {
    late Directory tempDir;
    late EmoPlaySettings settings;
    late FakeEngine engine;
    late String scriptsDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('emoplay_interp_');
      settings = EmoPlaySettings(p.join(tempDir.path, 'settings.json'));
      settings.load();
      engine = FakeEngine();
      engine.videoParamsMap = <String, Object?>{
        'w': 1920,
        'h': 1080,
        'primaries': 'bt.709',
        'gamma': 'bt.1886',
      };
      scriptsDir = p.join(tempDir.path, 'vs');
      await Directory(scriptsDir).create(recursive: true);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    InterpolationController build() => InterpolationController(
          settings: settings,
          scriptsDir: scriptsDir,
          onError: (_) {},
        );

    test('probeFailurePersistsOffAndSetsVsUnavailable', () async {
      // The shipped libmpv build has no vapoursynth filter: the append
      // never lands in the chain readback (probed 2026-11-10, rc=-12).
      final controller = build();
      await controller.attachEngine(engine);
      controller.setEnabled(true);
      await controller.startup();
      expect(controller.vsUnavailable, isTrue);
      expect(settings.qualityInterpolationEnabled, isFalse);
      expect(controller.enabled, isFalse);
      // The chain was left clean (probe removed its attempt).
      expect(engine.mountedVfEntries, isEmpty);
    });

    test('acceptedProbeMountsAndAdmitsByFacts', () async {
      engine.supportsVapoursynth = true;
      engine.fps = 23.976;
      final script = File(p.join(scriptsDir, 'MEMC_RIFE_STD.vpy'));
      await script.writeAsString('// user-supplied preset');
      final controller = build();
      await controller.attachEngine(engine);
      controller.setEnabled(true);
      await controller.startup();
      expect(controller.vsUnavailable, isFalse);
      expect(controller.blockReason, '');
      expect(engine.mountedVfEntries, hasLength(1));
      expect(engine.mountedVfEntries.single['label'], 'emoplay-interp');
      expect(engine.mountedVfEntries.single['name'], 'vapoursynth');

      // HFR admission unmounts the entry.
      engine.fps = 60.0;
      engine.fireVideoParamsChanged();
      await pumpEventQueue();
      await controller.apply();
      expect(controller.blockReason, 'high-fps');
      expect(engine.mountedVfEntries, isEmpty);
    });

    test('foreignVapoursynthStandsDown', () async {
      engine.supportsVapoursynth = true;
      engine.fps = 23.976;
      final script = File(p.join(scriptsDir, 'MEMC_RIFE_STD.vpy'));
      await script.writeAsString('// user-supplied preset');
      // The user's imported config already runs a vapoursynth filter.
      engine.mountedVfEntries
          .add(<String, Object?>{'name': 'vapoursynth', 'label': 'mine'});
      final controller = build();
      await controller.attachEngine(engine);
      controller.setEnabled(true);
      await controller.startup();
      expect(controller.blockReason, 'foreign-vapoursynth');
      // Our entry was never appended on top of the user's.
      expect(engine.mountedVfEntries, hasLength(1));
      expect(engine.mountedVfEntries.single['label'], 'mine');
    });
  });

  group('IccController (fake engine)', () {
    late Directory tempDir;
    late EmoPlaySettings settings;
    late FakeEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('emoplay_icc_');
      settings = EmoPlaySettings(p.join(tempDir.path, 'settings.json'));
      settings.load();
      engine = FakeEngine();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    IccController build() => IccController(
          settings: settings,
          appDataDir: tempDir.path,
          onError: (_) {},
        );

    test('missingProfileFailsAndPersistsOff', () async {
      final controller = build();
      controller.attachEngine(engine);
      await controller.startup();
      controller.setProfilePath(p.join(tempDir.path, 'no.icc'));
      controller.setEnabled(true);
      await pumpEventQueue();
      expect(controller.failed, isTrue);
      expect(controller.failureHint, contains('not found or unreadable'));
      expect(settings.qualityIccEnabled, isFalse);
      // Nothing was written to the engine.
      expect(engine.setProperties, isEmpty);
    });

    test('validProfileAppliesWithRedirectedCache', () async {
      final profile = File(p.join(tempDir.path, 'fake.icc'));
      await profile.writeAsBytes(List<int>.filled(8, 0));
      final controller = build();
      controller.attachEngine(engine);
      controller.setProfilePath(profile.path);
      controller.setEnabled(true);
      await controller.startup();
      expect(controller.failed, isFalse);
      // P4 redirect: the 3DLUT cache never lands in a user mpv directory.
      expect(engine.propertySet('icc-cache-dir'),
          p.join(tempDir.path, 'icc_cache'));
      expect(engine.propertySet('icc-profile'), profile.path);

      // Disabling restores the startup snapshot (empty = mpv default).
      controller.setEnabled(false);
      await pumpEventQueue();
      expect(engine.properties['icc-profile'], '');
    });

    test('readbackMismatchFails', () async {
      // A libmpv without the gpu renderer option would silently ignore the
      // set; the readback check must catch it (1.x honest failure rule).
      engine.rejectIccProfile = true;
      final profile = File(p.join(tempDir.path, 'fake.icc'));
      await profile.writeAsBytes(List<int>.filled(8, 0));
      final controller = build();
      controller.attachEngine(engine);
      controller.setProfilePath(profile.path);
      controller.setEnabled(true);
      await controller.startup();
      expect(controller.failed, isTrue);
      expect(controller.failureHint, contains("read back '"));
      expect(settings.qualityIccEnabled, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake engine: the 1.x "engine may be fake in tests" contract
// ---------------------------------------------------------------------------

class FakeEngine implements MpvQualityEngine {
  final Map<String, Object?> properties = <String, Object?>{};
  Map<String, Object?> videoParamsMap = <String, Object?>{};
  double fps = 0.0;
  String path = '';
  String mediaTitleValue = '';

  // glsl-shaders state + vf state, mutated by change-list commands.
  final List<String> mountedShaders = <String>[];
  final List<Map<String, Object?>> mountedVfEntries = <Map<String, Object?>>[];
  bool supportsVapoursynth = false;
  bool rejectIccProfile = false;

  final List<Map<String, String>> setProperties = <Map<String, String>>[];

  /// Latest value written to |property| via setProperty (null = never).
  String? propertySet(String property) {
    for (final entry in setProperties.reversed) {
      if (entry[property] != null) {
        return entry[property];
      }
    }
    return null;
  }
  final List<List<String>> commands = <List<String>>[];

  final StreamController<void> _fileLoaded =
      StreamController<void>.broadcast();
  final StreamController<void> _videoParams =
      StreamController<void>.broadcast();
  final StreamController<double> _containerFps =
      StreamController<double>.broadcast();
  final StreamController<int> _frameDropCount =
      StreamController<int>.broadcast();

  void fireFileLoaded() => _fileLoaded.add(null);
  void fireVideoParamsChanged() => _videoParams.add(null);
  void fireContainerFpsChanged(double value) => _containerFps.add(value);

  @override
  Future<Map<Object?, Object?>> videoParams() async =>
      Map<Object?, Object?>.of(videoParamsMap);

  @override
  Future<double> containerFps() async => fps;

  @override
  Future<String> mediaPath() async => path;

  @override
  Future<String> mediaTitle() async => mediaTitleValue;

  @override
  Future<List<String>> glslShaders() async => List<String>.of(mountedShaders);

  @override
  Future<List<Object?>> vfChain() async =>
      List<Object?>.of(mountedVfEntries);

  @override
  Future<String> iccProfile() async => properties['icc-profile'] as String? ?? '';

  @override
  Future<void> setProperty(String property, String value) async {
    setProperties.add(<String, String>{property: value});
    if (property == 'icc-profile' && rejectIccProfile) {
      // Silently ignored, like a libmpv without the gpu renderer option.
      return;
    }
    properties[property] = value;
  }

  @override
  Future<void> command(List<String> args) async {
    commands.add(List<String>.of(args));
    if (args.length < 4 || args[0] != 'change-list') {
      return;
    }
    if (args[1] == 'glsl-shaders') {
      if (args[2] == 'clr') {
        mountedShaders.clear();
      } else if (args[2] == 'append') {
        mountedShaders.add(args[3]);
      }
    } else if (args[1] == 'vf') {
      if (args[2] == 'append') {
        final entry = args[3];
        // Parse `@label:name=file=%len%path` the way mpv would; a filter
        // that is not compiled in makes the append fail (probe path).
        final labelEnd = entry.indexOf(':');
        final hasLabel = entry.startsWith('@') && labelEnd > 1;
        final nameStart = hasLabel ? labelEnd + 1 : 0;
        final equals = entry.indexOf('=', nameStart);
        final name = entry.substring(
            nameStart, equals >= 0 ? equals : entry.length);
        if (name == 'vapoursynth' && !supportsVapoursynth) {
          return; // "vapoursynth doesn't exist" — nothing lands
        }
        final parsed = <String, Object?>{'name': name};
        if (hasLabel) {
          parsed['label'] = entry.substring(1, labelEnd);
        }
        // Appending an entry with an existing label replaces in place
        // (mpv parse_obj_settings_del semantics, probed 2026-11-10).
        mountedVfEntries.removeWhere(
            (existing) => existing['label'] == parsed['label']);
        mountedVfEntries.add(parsed);
      } else if (args[2] == 'remove') {
        final label = args[3];
        mountedVfEntries
            .removeWhere((existing) => '@${existing['label']}' == label);
      }
    }
  }

  @override
  Stream<void> get fileLoaded => _fileLoaded.stream;

  @override
  Stream<void> get videoParamsChanged => _videoParams.stream;

  @override
  Stream<double> get containerFpsChanged => _containerFps.stream;

  @override
  Stream<int> get frameDropCountChanged => _frameDropCount.stream;

  @override
  void dispose() {
    _fileLoaded.close();
    _videoParams.close();
    _containerFps.close();
    _frameDropCount.close();
  }
}
