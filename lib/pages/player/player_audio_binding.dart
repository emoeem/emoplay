import 'dart:async';

import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/player/audio_controller.dart';

/// audio_service session binding extracted from player_item.dart (M3-T0
/// god-class split; pure move, no behavior change).
///
/// Binds the system media session callbacks to the player and mirrors the
/// playback state into it. The host orchestrates [syncState] from the 1s
/// heartbeat and the progress-bar drag lifecycle.
class PlayerAudioBinding {
  PlayerAudioBinding({
    required this.playerController,
    required this.playerPageController,
    required this.onPreNextItem,
  });

  final PlayerController playerController;
  final PlayerPageController playerPageController;

  /// Playlist navigation shared with the keyboard shortcuts ('next'/'prev').
  final Future<void> Function(String direction) onPreNextItem;

  AudioController get _audioController => playerController.audioController;

  Future<void> bind() async {
    try {
      await _audioController.bindCallbacks(
        onPlay: () => playerController.play(),
        onPause: () => playerController.pause(),
        onSkipToNext: () => onPreNextItem('next'),
        onSkipToPrevious: () => onPreNextItem('prev'),
        onSeek: (position) => playerController.seek(position),
        artworkUrl: null,
      );
      syncState();
    } catch (e) {
      EmoLogger().w('AudioController: failed to bind callbacks', error: e);
    }
  }

  void syncState() {
    try {
      final index = playerPageController.currentIndex;
      final length = playerPageController.playlist.length;
      final item = playerPageController.currentItem;
      if (item == null || index < 0) {
        return;
      }

      if (playerController.playback.duration <= Duration.zero) return;

      final canSkipToPrevious = index > 0;
      final canSkipToNext = index < length - 1;

      unawaited(
        _audioController.updateSession(
          mediaId: item.path,
          title: item.title,
          album: '',
          artist: '',
          duration: playerController.playback.duration,
          playing: playerController.playback.playing,
          loading: playerController.playback.loading,
          buffering: playerController.playback.isBuffering,
          completed: playerController.playback.completed,
          updatePosition: playerController.playback.currentPosition,
          bufferedPosition: playerController.playback.buffer,
          speed: playerController.playback.playerSpeed,
          queueIndex: index,
          canSkipToNext: canSkipToNext,
          canSkipToPrevious: canSkipToPrevious,
        ),
      );
    } catch (e) {
      EmoLogger()
          .w('AudioController: failed to sync playback state', error: e);
    }
  }
}
