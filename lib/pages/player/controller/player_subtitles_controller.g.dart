// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_subtitles_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PlayerSubtitlesController on _PlayerSubtitlesController, Store {
  Computed<bool>? _$hasTracksComputed;

  @override
  bool get hasTracks => (_$hasTracksComputed ??= Computed<bool>(
    () => super.hasTracks,
    name: '_PlayerSubtitlesController.hasTracks',
  )).value;
  Computed<SubtitleTrack?>? _$currentTrackComputed;

  @override
  SubtitleTrack? get currentTrack =>
      (_$currentTrackComputed ??= Computed<SubtitleTrack?>(
        () => super.currentTrack,
        name: '_PlayerSubtitlesController.currentTrack',
      )).value;

  late final _$tracksAtom = Atom(
    name: '_PlayerSubtitlesController.tracks',
    context: context,
  );

  @override
  List<SubtitleTrack> get tracks {
    _$tracksAtom.reportRead();
    return super.tracks;
  }

  @override
  set tracks(List<SubtitleTrack> value) {
    _$tracksAtom.reportWrite(value, super.tracks, () {
      super.tracks = value;
    });
  }

  late final _$currentSubIdAtom = Atom(
    name: '_PlayerSubtitlesController.currentSubId',
    context: context,
  );

  @override
  String get currentSubId {
    _$currentSubIdAtom.reportRead();
    return super.currentSubId;
  }

  @override
  set currentSubId(String value) {
    _$currentSubIdAtom.reportWrite(value, super.currentSubId, () {
      super.currentSubId = value;
    });
  }

  late final _$subDelayAtom = Atom(
    name: '_PlayerSubtitlesController.subDelay',
    context: context,
  );

  @override
  double get subDelay {
    _$subDelayAtom.reportRead();
    return super.subDelay;
  }

  @override
  set subDelay(double value) {
    _$subDelayAtom.reportWrite(value, super.subDelay, () {
      super.subDelay = value;
    });
  }

  late final _$_PlayerSubtitlesControllerActionController = ActionController(
    name: '_PlayerSubtitlesController',
    context: context,
  );

  @override
  void _setTracks(List<SubtitleTrack> value) {
    final _$actionInfo = _$_PlayerSubtitlesControllerActionController
        .startAction(name: '_PlayerSubtitlesController._setTracks');
    try {
      return super._setTracks(value);
    } finally {
      _$_PlayerSubtitlesControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _setCurrentSubId(String value) {
    final _$actionInfo = _$_PlayerSubtitlesControllerActionController
        .startAction(name: '_PlayerSubtitlesController._setCurrentSubId');
    try {
      return super._setCurrentSubId(value);
    } finally {
      _$_PlayerSubtitlesControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _setSubDelay(double value) {
    final _$actionInfo = _$_PlayerSubtitlesControllerActionController
        .startAction(name: '_PlayerSubtitlesController._setSubDelay');
    try {
      return super._setSubDelay(value);
    } finally {
      _$_PlayerSubtitlesControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
tracks: ${tracks},
currentSubId: ${currentSubId},
subDelay: ${subDelay},
hasTracks: ${hasTracks},
currentTrack: ${currentTrack}
    ''';
  }
}
