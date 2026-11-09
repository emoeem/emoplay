// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_page_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PlayerPageController on _PlayerPageController, Store {
  Computed<PlayerPlaylistItem?>? _$currentItemComputed;

  @override
  PlayerPlaylistItem? get currentItem =>
      (_$currentItemComputed ??= Computed<PlayerPlaylistItem?>(
        () => super.currentItem,
        name: '_PlayerPageController.currentItem',
      )).value;
  Computed<String>? _$titleComputed;

  @override
  String get title => (_$titleComputed ??= Computed<String>(
    () => super.title,
    name: '_PlayerPageController.title',
  )).value;
  Computed<String>? _$srcComputed;

  @override
  String get src => (_$srcComputed ??= Computed<String>(
    () => super.src,
    name: '_PlayerPageController.src',
  )).value;

  late final _$playlistAtom = Atom(
    name: '_PlayerPageController.playlist',
    context: context,
  );

  @override
  ObservableList<PlayerPlaylistItem> get playlist {
    _$playlistAtom.reportRead();
    return super.playlist;
  }

  @override
  set playlist(ObservableList<PlayerPlaylistItem> value) {
    _$playlistAtom.reportWrite(value, super.playlist, () {
      super.playlist = value;
    });
  }

  late final _$currentIndexAtom = Atom(
    name: '_PlayerPageController.currentIndex',
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

  late final _$loadingAtom = Atom(
    name: '_PlayerPageController.loading',
    context: context,
  );

  @override
  bool get loading {
    _$loadingAtom.reportRead();
    return super.loading;
  }

  @override
  set loading(bool value) {
    _$loadingAtom.reportWrite(value, super.loading, () {
      super.loading = value;
    });
  }

  late final _$isPipAtom = Atom(
    name: '_PlayerPageController.isPip',
    context: context,
  );

  @override
  bool get isPip {
    _$isPipAtom.reportRead();
    return super.isPip;
  }

  @override
  set isPip(bool value) {
    _$isPipAtom.reportWrite(value, super.isPip, () {
      super.isPip = value;
    });
  }

  late final _$isFullscreenAtom = Atom(
    name: '_PlayerPageController.isFullscreen',
    context: context,
  );

  @override
  bool get isFullscreen {
    _$isFullscreenAtom.reportRead();
    return super.isFullscreen;
  }

  @override
  set isFullscreen(bool value) {
    _$isFullscreenAtom.reportWrite(value, super.isFullscreen, () {
      super.isFullscreen = value;
    });
  }

  late final _$toggleFullscreenAsyncAction = AsyncAction(
    '_PlayerPageController.toggleFullscreen',
    context: context,
  );

  @override
  Future<void> toggleFullscreen() {
    return _$toggleFullscreenAsyncAction.run(() => super.toggleFullscreen());
  }

  late final _$setFullscreenAsyncAction = AsyncAction(
    '_PlayerPageController.setFullscreen',
    context: context,
  );

  @override
  Future<void> setFullscreen(bool value) {
    return _$setFullscreenAsyncAction.run(() => super.setFullscreen(value));
  }

  late final _$_PlayerPageControllerActionController = ActionController(
    name: '_PlayerPageController',
    context: context,
  );

  @override
  void setPlaylist(List<PlayerPlaylistItem> items, {int initialIndex = -1}) {
    final _$actionInfo = _$_PlayerPageControllerActionController.startAction(
      name: '_PlayerPageController.setPlaylist',
    );
    try {
      return super.setPlaylist(items, initialIndex: initialIndex);
    } finally {
      _$_PlayerPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setCurrentIndex(int index) {
    final _$actionInfo = _$_PlayerPageControllerActionController.startAction(
      name: '_PlayerPageController.setCurrentIndex',
    );
    try {
      return super.setCurrentIndex(index);
    } finally {
      _$_PlayerPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setLoading(bool value) {
    final _$actionInfo = _$_PlayerPageControllerActionController.startAction(
      name: '_PlayerPageController.setLoading',
    );
    try {
      return super.setLoading(value);
    } finally {
      _$_PlayerPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setPip(bool value) {
    final _$actionInfo = _$_PlayerPageControllerActionController.startAction(
      name: '_PlayerPageController.setPip',
    );
    try {
      return super.setPip(value);
    } finally {
      _$_PlayerPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
playlist: ${playlist},
currentIndex: ${currentIndex},
loading: ${loading},
isPip: ${isPip},
isFullscreen: ${isFullscreen},
currentItem: ${currentItem},
title: ${title},
src: ${src}
    ''';
  }
}
