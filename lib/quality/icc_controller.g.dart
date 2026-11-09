// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'icc_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$IccController on _IccController, Store {
  late final _$enabledAtom = Atom(
    name: '_IccController.enabled',
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

  late final _$profilePathAtom = Atom(
    name: '_IccController.profilePath',
    context: context,
  );

  @override
  String get profilePath {
    _$profilePathAtom.reportRead();
    return super.profilePath;
  }

  @override
  set profilePath(String value) {
    _$profilePathAtom.reportWrite(value, super.profilePath, () {
      super.profilePath = value;
    });
  }

  late final _$failedAtom = Atom(
    name: '_IccController.failed',
    context: context,
  );

  @override
  bool get failed {
    _$failedAtom.reportRead();
    return super.failed;
  }

  @override
  set failed(bool value) {
    _$failedAtom.reportWrite(value, super.failed, () {
      super.failed = value;
    });
  }

  late final _$failureHintAtom = Atom(
    name: '_IccController.failureHint',
    context: context,
  );

  @override
  String get failureHint {
    _$failureHintAtom.reportRead();
    return super.failureHint;
  }

  @override
  set failureHint(String value) {
    _$failureHintAtom.reportWrite(value, super.failureHint, () {
      super.failureHint = value;
    });
  }

  late final _$_IccControllerActionController = ActionController(
    name: '_IccController',
    context: context,
  );

  @override
  void setEnabled(bool value) {
    final _$actionInfo = _$_IccControllerActionController.startAction(
      name: '_IccController.setEnabled',
    );
    try {
      return super.setEnabled(value);
    } finally {
      _$_IccControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setProfilePath(String path) {
    final _$actionInfo = _$_IccControllerActionController.startAction(
      name: '_IccController.setProfilePath',
    );
    try {
      return super.setProfilePath(path);
    } finally {
      _$_IccControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
enabled: ${enabled},
profilePath: ${profilePath},
failed: ${failed},
failureHint: ${failureHint}
    ''';
  }
}
