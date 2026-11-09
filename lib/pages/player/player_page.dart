import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/models/playback_args.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_item.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';

/// 播放 Tab.
///
/// M2: plays local files handed over through the route as sealed
/// [LocalFilePlaybackArgs] (Kazumi video-route pattern), or opened with the
/// temporary file_picker entries below (docs/SPEC.md §5; the full library
/// picker replaces them in M3).
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playerController,
    required this.playerPageController,
    this.initialArgs,
  });

  final PlayerController playerController;
  final PlayerPageController playerPageController;

  /// Playback context passed through the route arguments. When present the
  /// page plays exactly this file on entry, replacing any previous playlist;
  /// when absent the tab keeps its existing state.
  final LocalFilePlaybackArgs? initialArgs;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _videoExtensions = {
    '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm', '.m4v',
    '.mpg', '.mpeg', '.ts', '.3gp', '.asf', '.ogv',
  };
  static const _audioExtensions = {
    '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.wma',
  };

  PlayerController get _playerController => widget.playerController;
  PlayerPageController get _pageController => widget.playerPageController;
  final FocusNode _keyboardFocus = FocusNode();

  bool get _hasCurrent => _pageController.currentIndex >= 0;

  @override
  void initState() {
    super.initState();
    final args = widget.initialArgs;
    if (args != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_playArgs(args));
        }
      });
    }
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// Plays the file handed over through the route (mpv-emo openAt semantics:
  /// [LocalFilePlaybackArgs.startAt] is deferred to file-loaded by the
  /// playback controller). Entry through the route replaces the playlist.
  Future<void> _playArgs(LocalFilePlaybackArgs args) async {
    _pageController.setPlaylist(
      [PlayerPlaylistItem(title: args.title, path: args.path)],
      initialIndex: 0,
    );
    await _loadCurrent(startAt: args.startAt);
  }

  Future<void> _openFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    final paths =
        result?.paths.whereType<String>().where(_isMediaFile).toList() ?? [];
    if (paths.isEmpty) {
      return;
    }
    await _play(paths, 0);
  }

  Future<void> _openFolder() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      return;
    }
    final files = <String>[];
    try {
      await for (final entity
          in Directory(directory).list(recursive: true, followLinks: false)) {
        if (entity is File && _isMediaFile(entity.path)) {
          files.add(entity.path);
        }
      }
    } catch (e) {
      if (mounted) {
        EmoDialog.showToast(message: '目录读取失败：$e');
      }
      return;
    }
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (files.isEmpty) {
      if (mounted) {
        EmoDialog.showToast(message: '目录中没有可播放的媒体文件');
      }
      return;
    }
    await _play(files, 0);
  }

  bool _isMediaFile(String path) {
    final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
    return _videoExtensions.contains(ext) || _audioExtensions.contains(ext);
  }

  Future<void> _play(List<String> paths, int index) async {
    final items = [
      for (final path in paths)
        PlayerPlaylistItem(title: path.split('/').last, path: path),
    ];
    _pageController.setPlaylist(items, initialIndex: index);
    await _loadCurrent();
  }

  Future<void> _loadCurrent({double startAt = 0.0}) async {
    final item = _pageController.currentItem;
    if (item == null) {
      return;
    }
    _pageController.setLoading(true);
    final ok = await _playerController.init(
      PlaybackInitParams(
        videoUrl: item.path,
        startAt: startAt,
        isLocalPlayback: true,
        httpHeaders: const {},
        episodeTitle: item.title,
      ),
    );
    _pageController.setLoading(false);
    if (!ok) {
      EmoDialog.showToast(message: '播放初始化失败：${item.title}');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _selectItem(int index) async {
    _pageController.setCurrentIndex(index);
    await _loadCurrent();
  }

  Future<void> _handleBack() async {
    if (_pageController.isFullscreen) {
      await _pageController.setFullscreen(false);
      return;
    }
    _pageController.setCurrentIndex(-1);
    await _playerController.stop();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final hasCurrent = _hasCurrent;
      return Scaffold(
        backgroundColor: Colors.black,
        body: hasCurrent
            ? PlayerItem(
                playerController: _playerController,
                playerPageController: _pageController,
                fillsWindow: true,
                // 常驻单实例约束在 S2/S3 落地；M1 离开播放页即释放播放器。
                onBackPressed: _handleBack,
                onSelectItem: _selectItem,
                keyboardFocus: _keyboardFocus,
                pauseForTimedShutdown: () =>
                    _playerController.pause(enableSync: false),
              )
            : SafeArea(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: GeneralEmptyState(
                    icon: Icons.play_circle_outline_rounded,
                    title: '选择要播放的本地媒体',
                    actions: [
                      FilledButton.icon(
                        onPressed: _openFiles,
                        icon: const Icon(Icons.video_file_rounded),
                        label: const Text('打开文件'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openFolder,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('打开文件夹'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    });
  }
}
