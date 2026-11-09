import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';

// View state over the LibraryStore's entries, mapped from 1.x LibraryModel
// (QAbstractListModel + roles -> ChangeNotifier + [visible]). Adds two
// things on top of the raw list: a case-insensitive substring filter (the
// page's search box) applied to title and path, and the "thumbnail" lookup
// (cache path of the entry's ffmpeg-generated JPEG, empty when none — the
// grid falls back to the type icon placeholder).
//
// Thumbnails are requested on demand: whenever the visible list is rebuilt,
// every visible path is handed to the ThumbnailService (which dedupes,
// serves cache hits and serializes generation in the background). Ready
// thumbnails map back to their rows through the service's notifications, so
// delegates reload without a full reset (1.x dataChanged(ThumbnailRole);
// Flutter rebuilds the delegate from the notification instead).
//
// The model re-reads the whole filtered list whenever the store reports an
// update or a filter changes — library sizes make incremental diffing
// pointless in v1.
class LibraryModel extends ChangeNotifier {
  // |thumbnails| is optional: null keeps the thumbnail role permanently
  // empty (and is what minimal setups pass).
  LibraryModel(this._store, [ThumbnailService? thumbnails])
      : _thumbnails = thumbnails {
    _store.addListener(_rebuild);
    if (_thumbnails != null) {
      final thumbnails = _thumbnails;
      thumbnails.addListener(_onServiceUpdate);
      // Requests made while ffmpeg was still probing (or while it was
      // missing) are dropped by the service; when availability changes we
      // ask again so late-probed / late-installed ffmpeg still fills the
      // visible grid. Unavailable services drop them again (degradation).
      _availabilitySubscription =
          thumbnails.onThumbnailReady.listen((_) => notifyListeners());
    }
    _rebuild();
  }

  final LibraryStore _store;
  final ThumbnailService? _thumbnails;
  StreamSubscription<ThumbnailReady>? _availabilitySubscription;

  // Rows matching the current filter.
  int get count => _visible.length;
  List<LibraryEntry> get visible => List.unmodifiable(_visible);
  final List<LibraryEntry> _visible = <LibraryEntry>[];

  // Case-insensitive substring filter over title and path; empty = all.
  String get filter => _filter;
  String _filter = '';
  set filter(String value) {
    if (_filter == value) {
      return;
    }
    _filter = value;
    _rebuild();
  }

  // Media-type filter: "all" | "video" | "audio". Applied together with the
  // text filter so the Library page can offer both without two models.
  String get typeFilter => _typeFilter;
  String _typeFilter = 'all';
  set typeFilter(String value) {
    final normalized = value.trim().toLowerCase();
    final next = (normalized == 'video' || normalized == 'audio')
        ? normalized
        : 'all';
    if (_typeFilter == next) {
      return;
    }
    _typeFilter = next;
    _rebuild();
  }

  // Sort order: "title" (default, case-insensitive ascending) |
  // "titledesc" | "size" (largest first) | "recent" (last played first,
  // never played last) | "path". Unknown values normalise to "title".
  String get sortMode => _sortMode;
  String _sortMode = 'title';
  set sortMode(String value) {
    final normalized = value.trim().toLowerCase();
    const known = <String>['title', 'titledesc', 'size', 'recent', 'path'];
    final next = known.contains(normalized) ? normalized : 'title';
    if (_sortMode == next) {
      return;
    }
    _sortMode = next;
    _rebuild();
  }

  // 1.x role lookups map onto row reads; data() on an invalid index became
  // an empty-string/null-safe accessor.
  String pathAt(int row) =>
      row >= 0 && row < _visible.length ? _visible[row].path : '';
  String titleAt(int row) =>
      row >= 0 && row < _visible.length ? _visible[row].title : '';
  String typeAt(int row) =>
      row >= 0 && row < _visible.length ? _visible[row].type : '';
  int sizeAt(int row) => row >= 0 && row < _visible.length
      ? _visible[row].size
      : 0;
  String lastPlayedAt(int row) =>
      row >= 0 && row < _visible.length ? _visible[row].lastPlayed : '';
  String thumbnailAt(int row) =>
      row >= 0 && row < _visible.length
          ? (_thumbnails?.cachedThumbnailPath(_visible[row].path) ?? '')
          : '';

  // Stable ordered sort: Dart's List.sort is unstable and 1.x used
  // std::stable_sort, so ties keep the store's order (index fallback).
  List<LibraryEntry> _stableSort(
      List<LibraryEntry> rows, int Function(LibraryEntry, LibraryEntry) compare) {
    final order = List<int>.generate(rows.length, (index) => index);
    order.sort((a, b) {
      final result = compare(rows[a], rows[b]);
      return result != 0 ? result : a.compareTo(b);
    });
    return [for (final index in order) rows[index]];
  }

  void _rebuild() {
    _visible.clear();
    final needle = _filter.trim();
    for (final entry in _store.entryList) {
      if (_typeFilter != 'all' && entry.type != _typeFilter) {
        continue;
      }
      if (needle.isNotEmpty &&
          !entry.title.toLowerCase().contains(needle.toLowerCase()) &&
          !entry.path.toLowerCase().contains(needle.toLowerCase())) {
        continue;
      }
      _visible.add(entry);
    }

    switch (_sortMode) {
      case 'titledesc':
        // Sort into a temporary first: the clear must not race the source
        // list (Dart cascades evaluate left to right, so
        // `_visible..clear()..addAll(_stableSort(_visible, ...))` would
        // sort the already-cleared list).
        final sorted = _stableSort(
            _visible,
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        _visible
          ..clear()
          ..addAll(sorted);
        break;
      case 'size':
        final sorted =
            _stableSort(_visible, (a, b) => b.size.compareTo(a.size));
        _visible
          ..clear()
          ..addAll(sorted);
        break;
      case 'recent':
        // ISO 8601 strings compare chronologically; empty (never played)
        // sorts last instead of first.
        final sorted = _stableSort(_visible, (a, b) {
          final aEmpty = a.lastPlayed.isEmpty;
          final bEmpty = b.lastPlayed.isEmpty;
          if (aEmpty != bEmpty) {
            return bEmpty ? -1 : 1;
          }
          return b.lastPlayed.compareTo(a.lastPlayed);
        });
        _visible
          ..clear()
          ..addAll(sorted);
        break;
      case 'path':
        final sorted = _stableSort(
            _visible,
            (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        _visible
          ..clear()
          ..addAll(sorted);
        break;
      default:
        // "title": the store already delivers title-sorted rows.
        break;
    }

    // On-demand thumbnails for the freshly (re)built visible list. The
    // service dedupes, serves cache hits synchronously (thumbnailReady
    // arrives within this loop) and queues the rest.
    _requestVisibleThumbnails();
    notifyListeners();
  }

  void _onServiceUpdate() {
    // Ready paths / availability flips flow in from the service; the grid
    // re-reads the thumbnail role without a full rebuild (1.x
    // dataChanged(ThumbnailRole)).
    notifyListeners();
  }

  void _requestVisibleThumbnails() {
    final thumbnails = _thumbnails;
    if (thumbnails == null) {
      return;
    }
    for (final entry in _visible) {
      thumbnails.requestThumbnail(entry.path);
    }
  }

  @override
  void dispose() {
    _availabilitySubscription?.cancel();
    _store.removeListener(_rebuild);
    _thumbnails?.removeListener(_onServiceUpdate);
    super.dispose();
  }
}
