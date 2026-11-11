import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/models/media_item.dart';
import 'package:emoplay/pages/player/controller/player_playlist_item.dart';

// Adapters between the 1.x-shaped stores, the unified model and the player
// page row type (EmoPlay 3.0 roadmap docs/EMOPLAY-3.0-ROADMAP.md §四, task
// M4-T0 step 1 + step 2). Read-only bridges: every mapper is a pure field
// copy — the §7 stores (history.json / library.json / settings.json) are
// never written here, and the store entries are never mutated, so the
// release promise guarded by test/data_compat_spec7_test.dart is untouched.
//
// Losslessness contract (asserted by test/media_item_mappers_test.dart): a
// §7 sample document mapped into [MediaItem] carries every field the model
// represents without alteration. Fields the model deliberately does not
// represent are documented per mapper (HistoryEntry.position is a resume
// fact, not a media fact — the session's startPosition / PendingResumeSeek
// carry it at open time, invariant 4).

/// LibraryEntry (§7 library.json) → MediaItem.
///
/// [MediaItem.duration] is 0.0 (unknown): the §7 library entries carry no
/// duration. [MediaItem.lastPlayed] parses the entry's ISO 8601 string —
/// "" and the foreign-writer JSON null (which LibraryEntry.fromJson already
/// normalises to "") both become null. [MediaItem.type] passes through
/// verbatim: the classifier vocabulary ("video" | "audio") is what 1.x
/// wrote; a "" from a foreign writer stays "" (no invented normalisation).
MediaItem mediaItemFromLibraryEntry(LibraryEntry entry) => MediaItem(
      path: entry.path,
      title: entry.title,
      type: entry.type,
      size: entry.size,
      lastPlayed: tryParseIso8601(entry.lastPlayed),
    );

/// HistoryEntry (§7 history.json) → MediaItem.
///
/// [MediaItem.duration] is the recorded duration (0.0 stays the unknown
/// sentinel), [MediaItem.lastPlayed] parses lastPlayedAt. [MediaItem.size]
/// is 0 (unknown): history.json records no size. The entry's [position] —
/// the resume point — is intentionally NOT mapped: it is a playback fact
/// consumed at open time (openAt semantics, SPEC §4.4 invariant 4), not a
/// media fact; HistoryEntry keeps owning it.
///
/// [MediaItem.type] is derived from the path's extension against the
/// classifier tables (media_classifier.dart, "classifier 词汇，不扩"):
/// history.json has no type field, so nothing can be lost — an unknown or
/// remote-path extension degrades to "".
MediaItem mediaItemFromHistoryEntry(HistoryEntry entry) {
  final ext = MediaClassifier.extensionOf(entry.path);
  final type = MediaClassifier.videoExtensions.contains(ext)
      ? 'video'
      : MediaClassifier.audioExtensions.contains(ext)
          ? 'audio'
          : '';
  return MediaItem(
    path: entry.path,
    title: entry.title,
    type: type,
    duration: entry.duration,
    lastPlayed: tryParseIso8601(entry.lastPlayedAt),
  );
}

/// ISO 8601 string → DateTime, "" / unparseable → null. Shared by both
/// store mappers so one implementation owns the tolerance contract.
DateTime? tryParseIso8601(String isoOrEmpty) =>
    isoOrEmpty.isEmpty ? null : DateTime.tryParse(isoOrEmpty);

extension MediaItemPlaylistMapper on MediaItem {
  /// MediaItem → player page row (roadmap §四 step 1's third mapping). The
  /// playlist row is a (path, title) pair by contract: the 3.0 metadata
  /// extensions stay available on the [MediaItem] behind the session for
  /// detail views, and are deliberately not flattened into the row.
  PlayerPlaylistItem toPlaylistItem() =>
      PlayerPlaylistItem(path: path, title: title);
}

extension PlayerPlaylistItemMediaMapper on PlayerPlaylistItem {
  /// PlayerPlaylistItem → MediaItem — the M4-T0b seam
  /// (player_page_controller.setPlaylist) uses to store the queue as a
  /// [PlaybackSession] while its constructor signature stays unchanged.
  /// Only (path, title) exist on the row; everything else is "unknown".
  MediaItem toMediaItem() => MediaItem(path: path, title: title);
}
