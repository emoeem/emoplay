// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_chapters_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PlayerChaptersController on _PlayerChaptersController, Store {
  Computed<bool>? _$hasChaptersComputed;

  @override
  bool get hasChapters => (_$hasChaptersComputed ??= Computed<bool>(
    () => super.hasChapters,
    name: '_PlayerChaptersController.hasChapters',
  )).value;
  Computed<MediaChapter?>? _$currentChapterComputed;

  @override
  MediaChapter? get currentChapter =>
      (_$currentChapterComputed ??= Computed<MediaChapter?>(
        () => super.currentChapter,
        name: '_PlayerChaptersController.currentChapter',
      )).value;

  late final _$chaptersAtom = Atom(
    name: '_PlayerChaptersController.chapters',
    context: context,
  );

  @override
  List<MediaChapter> get chapters {
    _$chaptersAtom.reportRead();
    return super.chapters;
  }

  @override
  set chapters(List<MediaChapter> value) {
    _$chaptersAtom.reportWrite(value, super.chapters, () {
      super.chapters = value;
    });
  }

  late final _$currentIndexAtom = Atom(
    name: '_PlayerChaptersController.currentIndex',
    context: context,
  );

  @override
  int get currentIndex {
    _$currentIndexAtom.reportRead();
    return super.currentIndex;
  }

  @override
  set currentIndex(int value) {
    _$currentIndexAtom.reportWrite(value, super.currentIndex, () {
      super.currentIndex = value;
    });
  }

  late final _$_PlayerChaptersControllerActionController = ActionController(
    name: '_PlayerChaptersController',
    context: context,
  );

  @override
  void _setChapters(List<MediaChapter> value) {
    final _$actionInfo = _$_PlayerChaptersControllerActionController
        .startAction(name: '_PlayerChaptersController._setChapters');
    try {
      return super._setChapters(value);
    } finally {
      _$_PlayerChaptersControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _setCurrentIndex(int value) {
    final _$actionInfo = _$_PlayerChaptersControllerActionController
        .startAction(name: '_PlayerChaptersController._setCurrentIndex');
    try {
      return super._setCurrentIndex(value);
    } finally {
      _$_PlayerChaptersControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
chapters: ${chapters},
currentIndex: ${currentIndex},
hasChapters: ${hasChapters},
currentChapter: ${currentChapter}
    ''';
  }
}
