import 'package:emoplay/services/platform/display_mode_service.dart';
import 'package:emoplay/utils/device.dart';
import 'package:mobx/mobx.dart';
import 'package:window_manager/window_manager.dart';

part 'player_page_controller.g.dart';

/// One playable entry in the player page playlist.
class PlayerPlaylistItem {
  const PlayerPlaylistItem({
    required this.path,
    required this.title,
  });

  /// Absolute media file path.
  final String path;

  /// Display title (file name unless a nicer title is available).
  final String title;
}

/// Page-scope state for the player page.
///
/// M1 replacement for the stripped Kazumi [VideoPageController]: it owns the
/// local playlist, the current selection and window fullscreen/PIP flags.
/// Playback itself lives in [PlayerController].
class PlayerPageController = _PlayerPageController
    with _$PlayerPageController;

abstract class _PlayerPageController with Store {
  /// Playlist shown in the player page side panel.
  @observable
  ObservableList<PlayerPlaylistItem> playlist =
      ObservableList<PlayerPlaylistItem>();

  /// Index of the entry passed to the player, -1 while nothing is loaded.
  @observable
  int currentIndex = -1;

  /// True while the route is still resolving the media for playback.
  @observable
  bool loading = false;

  /// Android picture-in-picture flag (mirrored from the native PiP handler).
  @observable
  bool isPip = false;

  /// Window fullscreen state.
  @observable
  bool isFullscreen = false;

  @computed
  PlayerPlaylistItem? get currentItem =>
      (currentIndex >= 0 && currentIndex < playlist.length)
          ? playlist[currentIndex]
          : null;

  /// Title of the media currently being played.
  @computed
  String get title => currentItem?.title ?? '';

  /// Path of the media currently being played.
  @computed
  String get src => currentItem?.path ?? '';

  PlayerPlaylistItem? itemAt(int index) {
    if (index < 0 || index >= playlist.length) {
      return null;
    }
    return playlist[index];
  }

  @action
  void setPlaylist(List<PlayerPlaylistItem> items, {int initialIndex = -1}) {
    playlist = ObservableList<PlayerPlaylistItem>.of(items);
    currentIndex = initialIndex;
  }

  @action
  void setCurrentIndex(int index) {
    if (index >= -1 && index < playlist.length) {
      currentIndex = index;
    }
  }

  @action
  void setLoading(bool value) {
    loading = value;
  }

  @action
  void setPip(bool value) {
    isPip = value;
  }

  /// Toggles fullscreen, per platform (PiliPlus triggerFullScreen split):
  ///
  /// - desktop: window fullscreen via window_manager;
  /// - mobile: landscape orientation lock + immersive system bars, through
  ///   [DisplayModeService] (its native `setSystemBarsHidden` channel and the
  ///   orientation apply were previously wired but never called).
  ///
  /// The fullscreen flag is owned here (not by the player surface) so that the
  /// route shell can react to it, mirroring the Kazumi fullscreen controller.
  @action
  Future<void> toggleFullscreen() async {
    await setFullscreen(!isFullscreen);
  }

  @action
  Future<void> setFullscreen(bool value) async {
    if (value == isFullscreen) {
      return;
    }
    if (isDesktop()) {
      await WindowManager.instance.setFullScreen(value);
      isFullscreen = value;
      return;
    }
    // PiliPlus enter/exit order: bars first, then the orientation lock; the
    // exit restores rotation before the bars so the layout lands with the
    // insets it lays out for.
    await DisplayModeService.applyVideoFullscreen(value);
    if (value) {
      await DisplayModeService.setSystemBarsHidden(owner: this, hidden: true);
    } else {
      DisplayModeService.releaseSystemBars(this);
    }
    isFullscreen = value;
  }
}
