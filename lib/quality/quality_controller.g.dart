// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quality_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$QualityController on _QualityController, Store {
  late final _$contentModeAtom = Atom(
    name: '_QualityController.contentMode',
    context: context,
  );

  @override
  String get contentMode {
    _$contentModeAtom.reportRead();
    return super.contentMode;
  }

  @override
  set contentMode(String value) {
    _$contentModeAtom.reportWrite(value, super.contentMode, () {
      super.contentMode = value;
    });
  }

  late final _$qualityTierAtom = Atom(
    name: '_QualityController.qualityTier',
    context: context,
  );

  @override
  String get qualityTier {
    _$qualityTierAtom.reportRead();
    return super.qualityTier;
  }

  @override
  set qualityTier(String value) {
    _$qualityTierAtom.reportWrite(value, super.qualityTier, () {
      super.qualityTier = value;
    });
  }

  late final _$toneMappingModeAtom = Atom(
    name: '_QualityController.toneMappingMode',
    context: context,
  );

  @override
  String get toneMappingMode {
    _$toneMappingModeAtom.reportRead();
    return super.toneMappingMode;
  }

  @override
  set toneMappingMode(String value) {
    _$toneMappingModeAtom.reportWrite(value, super.toneMappingMode, () {
      super.toneMappingMode = value;
    });
  }

  late final _$scaleOverrideAtom = Atom(
    name: '_QualityController.scaleOverride',
    context: context,
  );

  @override
  String get scaleOverride {
    _$scaleOverrideAtom.reportRead();
    return super.scaleOverride;
  }

  @override
  set scaleOverride(String value) {
    _$scaleOverrideAtom.reportWrite(value, super.scaleOverride, () {
      super.scaleOverride = value;
    });
  }

  late final _$debandModeAtom = Atom(
    name: '_QualityController.debandMode',
    context: context,
  );

  @override
  String get debandMode {
    _$debandModeAtom.reportRead();
    return super.debandMode;
  }

  @override
  set debandMode(String value) {
    _$debandModeAtom.reportWrite(value, super.debandMode, () {
      super.debandMode = value;
    });
  }

  late final _$availableShadersAtom = Atom(
    name: '_QualityController.availableShaders',
    context: context,
  );

  @override
  List<String> get availableShaders {
    _$availableShadersAtom.reportRead();
    return super.availableShaders;
  }

  @override
  set availableShaders(List<String> value) {
    _$availableShadersAtom.reportWrite(value, super.availableShaders, () {
      super.availableShaders = value;
    });
  }

  late final _$manualShadersAtom = Atom(
    name: '_QualityController.manualShaders',
    context: context,
  );

  @override
  List<String> get manualShaders {
    _$manualShadersAtom.reportRead();
    return super.manualShaders;
  }

  @override
  set manualShaders(List<String> value) {
    _$manualShadersAtom.reportWrite(value, super.manualShaders, () {
      super.manualShaders = value;
    });
  }

  late final _$autoDowngradedAtom = Atom(
    name: '_QualityController.autoDowngraded',
    context: context,
  );

  @override
  bool get autoDowngraded {
    _$autoDowngradedAtom.reportRead();
    return super.autoDowngraded;
  }

  @override
  set autoDowngraded(bool value) {
    _$autoDowngradedAtom.reportWrite(value, super.autoDowngraded, () {
      super.autoDowngraded = value;
    });
  }

  late final _$setShaderMountedAsyncAction = AsyncAction(
    '_QualityController.setShaderMounted',
    context: context,
  );

  @override
  Future<void> setShaderMounted(String relativePath, bool mounted) {
    return _$setShaderMountedAsyncAction.run(
      () => super.setShaderMounted(relativePath, mounted),
    );
  }

  late final _$_QualityControllerActionController = ActionController(
    name: '_QualityController',
    context: context,
  );

  @override
  void notifyDropFrameRate(double framesPerSecond) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.notifyDropFrameRate',
    );
    try {
      return super.notifyDropFrameRate(framesPerSecond);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setContentMode(String mode) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.setContentMode',
    );
    try {
      return super.setContentMode(mode);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setQualityTier(String tier) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.setQualityTier',
    );
    try {
      return super.setQualityTier(tier);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setToneMappingMode(String mode) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.setToneMappingMode',
    );
    try {
      return super.setToneMappingMode(mode);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setScaleOverride(String scale) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.setScaleOverride',
    );
    try {
      return super.setScaleOverride(scale);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setDebandMode(String mode) {
    final _$actionInfo = _$_QualityControllerActionController.startAction(
      name: '_QualityController.setDebandMode',
    );
    try {
      return super.setDebandMode(mode);
    } finally {
      _$_QualityControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
contentMode: ${contentMode},
qualityTier: ${qualityTier},
toneMappingMode: ${toneMappingMode},
scaleOverride: ${scaleOverride},
debandMode: ${debandMode},
availableShaders: ${availableShaders},
manualShaders: ${manualShaders},
autoDowngraded: ${autoDowngraded}
    ''';
  }
}
