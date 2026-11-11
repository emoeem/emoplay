/// One playable entry in the player page playlist.
///
/// M4-T0b (roadmap §四 step 2): the class moved here verbatim out of
/// player_page_controller.dart so the unified-model mappers
/// (lib/models/media_item_mappers.dart) can name the type without an import
/// cycle into the MobX store. player_page_controller.dart re-exports it, so
/// every existing caller keeps importing the controller file unchanged
/// ("播放页对外接口不变"). The roadmap's step 4 later demotes this class to
/// a player-page-internal implementation detail; until then it remains the
/// page-facing row shape.
class PlayerPlaylistItem {
  const PlayerPlaylistItem({
    required this.path,
    required this.title,
  });

  /// Absolute media file path.
  final String path;

  /// Display title (file name unless a nicer title is available).
  final String title;

  @override
  bool operator ==(Object other) =>
      other is PlayerPlaylistItem &&
      other.path == path &&
      other.title == title;

  @override
  int get hashCode => Object.hash(path, title);

  @override
  String toString() => 'PlayerPlaylistItem($path, $title)';
}
