// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_ab_loop_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PlayerAbLoopController on _PlayerAbLoopController, Store {
  Computed<PlayerAbLoopPhase>? _$phaseComputed;

  @override
  PlayerAbLoopPhase get phase =>
      (_$phaseComputed ??= Computed<PlayerAbLoopPhase>(
        () => super.phase,
        name: '_PlayerAbLoopController.phase',
      )).value;

  late final _$positionAAtom = Atom(
    name: '_PlayerAbLoopController.positionA',
    context: context,
  );

  @override
  double? get positionA {
    _$positionAAtom.reportRead();
    return super.positionA;
  }

  @override
  set positionA(double? value) {
    _$positionAAtom.reportWrite(value, super.positionA, () {
      super.positionA = value;
    });
  }

  late final _$positionBAtom = Atom(
    name: '_PlayerAbLoopController.positionB',
    context: context,
  );

  @override
  double? get positionB {
    _$positionBAtom.reportRead();
    return super.positionB;
  }

  @override
  set positionB(double? value) {
    _$positionBAtom.reportWrite(value, super.positionB, () {
      super.positionB = value;
    });
  }

  late final _$_PlayerAbLoopControllerActionController = ActionController(
    name: '_PlayerAbLoopController',
    context: context,
  );

  @override
  void _applyObservation(String property, String value) {
    final _$actionInfo = _$_PlayerAbLoopControllerActionController.startAction(
      name: '_PlayerAbLoopController._applyObservation',
    );
    try {
      return super._applyObservation(property, value);
    } finally {
      _$_PlayerAbLoopControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _setMarks(double? a, double? b) {
    final _$actionInfo = _$_PlayerAbLoopControllerActionController.startAction(
      name: '_PlayerAbLoopController._setMarks',
    );
    try {
      return super._setMarks(a, b);
    } finally {
      _$_PlayerAbLoopControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
positionA: ${positionA},
positionB: ${positionB},
phase: ${phase}
    ''';
  }
}
