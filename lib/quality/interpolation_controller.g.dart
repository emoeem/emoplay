// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interpolation_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$InterpolationController on _InterpolationController, Store {
  late final _$enabledAtom = Atom(
    name: '_InterpolationController.enabled',
    context: context,
  );

  @override
  bool get enabled {
    _$enabledAtom.reportRead();
    return super.enabled;
  }

  @override
  set enabled(bool value) {
    _$enabledAtom.reportWrite(value, super.enabled, () {
      super.enabled = value;
    });
  }

  late final _$presetAtom = Atom(
    name: '_InterpolationController.preset',
    context: context,
  );

  @override
  String get preset {
    _$presetAtom.reportRead();
    return super.preset;
  }

  @override
  set preset(String value) {
    _$presetAtom.reportWrite(value, super.preset, () {
      super.preset = value;
    });
  }

  late final _$vsUnavailableAtom = Atom(
    name: '_InterpolationController.vsUnavailable',
    context: context,
  );

  @override
  bool get vsUnavailable {
    _$vsUnavailableAtom.reportRead();
    return super.vsUnavailable;
  }

  @override
  set vsUnavailable(bool value) {
    _$vsUnavailableAtom.reportWrite(value, super.vsUnavailable, () {
      super.vsUnavailable = value;
    });
  }

  late final _$blockReasonAtom = Atom(
    name: '_InterpolationController.blockReason',
    context: context,
  );

  @override
  String get blockReason {
    _$blockReasonAtom.reportRead();
    return super.blockReason;
  }

  @override
  set blockReason(String value) {
    _$blockReasonAtom.reportWrite(value, super.blockReason, () {
      super.blockReason = value;
    });
  }

  late final _$expectedScriptPathAtom = Atom(
    name: '_InterpolationController.expectedScriptPath',
    context: context,
  );

  @override
  String get expectedScriptPath {
    _$expectedScriptPathAtom.reportRead();
    return super.expectedScriptPath;
  }

  @override
  set expectedScriptPath(String value) {
    _$expectedScriptPathAtom.reportWrite(value, super.expectedScriptPath, () {
      super.expectedScriptPath = value;
    });
  }

  late final _$_InterpolationControllerActionController = ActionController(
    name: '_InterpolationController',
    context: context,
  );

  @override
  void setEnabled(bool value) {
    final _$actionInfo = _$_InterpolationControllerActionController.startAction(
      name: '_InterpolationController.setEnabled',
    );
    try {
      return super.setEnabled(value);
    } finally {
      _$_InterpolationControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setPreset(String presetId) {
    final _$actionInfo = _$_InterpolationControllerActionController.startAction(
      name: '_InterpolationController.setPreset',
    );
    try {
      return super.setPreset(presetId);
    } finally {
      _$_InterpolationControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
enabled: ${enabled},
preset: ${preset},
vsUnavailable: ${vsUnavailable},
blockReason: ${blockReason},
expectedScriptPath: ${expectedScriptPath}
    ''';
  }
}
