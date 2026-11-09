import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/services/player/audio_controller.dart';
import 'package:emoplay/services/shaders/shader_asset_service.dart';

/// Root-owned application data and cross-feature coordinators.
///
/// This module intentionally has no path, so its registrations live for the
/// whole application. Page and feature-local state belongs in route `provide`
/// callbacks or path-bearing modules instead.
///
/// EmoPlay M1: the Kazumi repository/controller stack (collect, history,
/// download, plugins, sync) was removed with the bangumi business layer
/// (docs/STRIP-LIST.md §3). The EmoPlay stores (settings/library/history/
/// plugins/quality) register here as they are ported in S3-S7.
final coreModule = createModule(
  register: (c) {
    c
      // Service layer.
      ..addSingleton<AudioController>(AudioController.new)
      ..addSingleton<ShaderAssetService>(ShaderAssetService.new);
  },
);
