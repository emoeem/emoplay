import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/empty_state_widget.dart';
import 'package:emoplay/media/media_classifier.dart';
import 'package:emoplay/models/playback_args.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/pages/player/player_item.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/utils/device.dart';

/// 播放 Tab.
///
/// M3: file access goes through [MediaClassifier] — the file picker
/// (video/audio/multi-select/URL/folder/subtitle) and the desktop_drop drag
/// area feed the same planDrop executor, mirroring 1.x where the drop overlay
/// and the picker share one classification table (qml/Main.qml handleDrop).
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
  PlayerController get _playerController => widget.playerController;
  PlayerPageController get _pageController => widget.playerPageController;
  final FocusNode _keyboardFocus = FocusNode();

  bool get _hasCurrent => _pageController.currentIndex >= 0;

  bool _dragHover = false;

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

  // ------------------------------------------------------------ file access

  /// 打开文件: multi-select video/audio/subtitle files. The picked paths run
  /// through [MediaClassifier.planDrop] so picker and drop share one rule set
  /// (1.x: "a file the picker shows as audio is the same file the drop path
  /// classifies as audio").
  Future<void> _openFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...MediaClassifier.videoExtensions,
        ...MediaClassifier.audioExtensions,
        ...MediaClassifier.subtitleExtensions,
      ],
      allowMultiple: true,
      withData: false,
    );
    final paths =
        result?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) {
      return;
    }
    await _executePlan(MediaClassifier.planDrop(paths, _hasCurrent));
  }

  /// 打开文件夹: bounded-depth recursive scan through the classifier, the
  /// folder becomes the playlist (1.x folderMedia contract).
  Future<void> _openFolder() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      return;
    }
    await _playFolder(directory);
  }

  Future<void> _playFolder(String directory) async {
    final files = MediaClassifier.folderMedia(directory);
    if (files.isEmpty) {
      EmoDialog.showToast(message: '该文件夹中没有受支持的媒体文件');
      return;
    }
    await _play(files);
  }

  /// 打开 URL: stream schemes are classified like any other input; only
  /// recognised remote media URLs play (1.x remoteUrl rules).
  Future<void> _openUrl() async {
    final controller = TextEditingController();
    final url = await EmoDialog.show<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开 URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'http(s)://、rtsp、rtmp、udp、ftp',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('播放'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) {
      return;
    }
    final row = MediaClassifier.classify(url.trim());
    if (row.kind == MediaKind.remoteUrl) {
      await _play([row.path]);
    } else {
      EmoDialog.showToast(message: '${row.name}：${row.reason}');
    }
  }

  /// Loads an external subtitle into the current media (1.x subtitleDialog).
  Future<void> _loadSubtitle() async {
    if (!_hasCurrent) {
      EmoDialog.showToast(message: '请先选择要加载字幕的媒体文件');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: MediaClassifier.subtitleExtensions,
      withData: false,
    );
    final paths =
        result?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) {
      return;
    }
    await _addSubtitle(paths.first);
  }

  Future<void> _addSubtitle(String path) async {
    try {
      await _playerController.addSubtitle(MediaClassifier.normalise(path));
      EmoDialog.showToast(
        message:
            '已加载字幕：${MediaClassifier.fileNameOf(MediaClassifier.normalise(path))}',
      );
    } catch (e) {
      EmoDialog.showToast(message: '字幕加载失败：$e');
    }
  }

  // ---------------------------------------------------------- drop handling

  /// Executes one [DropPlan] verbatim — the Dart counterpart of 1.x
  /// qml/Main.qml handleDrop. "play" keeps plan order: first loads, the rest
  /// become playlist entries; "subtitle" loads into the current media;
  /// "folder" asks before playing; "needs-media"/"reject" surface a reason.
  Future<void> _executePlan(DropPlan plan) async {
    switch (plan.action) {
      case 'play':
        await _play(plan.paths);
        break;
      case 'subtitle':
        await _addSubtitle(plan.subtitles.first);
        break;
      case 'needs-media':
        EmoDialog.showToast(message: '请先选择要加载字幕的媒体文件');
        await _openFiles();
        break;
      case 'folder':
        await _confirmFolder(plan.folders.firstOrNull ?? '');
        break;

      default:
        final rejected =
            plan.rejected.isNotEmpty ? plan.rejected.first : null;
        EmoDialog.showToast(
          message: rejected == null
              ? '不支持的内容'
              : '${rejected.name}：${rejected.reason}',
        );
        break;
    }
  }

  /// 1.x folderChoiceDialog: a dropped folder must not silently replace the
  /// playlist. The 添加到媒体库 branch of the 1.x dialog arrives with the
  /// library store (PORT-MAP S4); until then the dialog offers 播放/取消.
  Future<void> _confirmFolder(String folder) async {
    if (folder.isEmpty) {
      return;
    }
    final play = await EmoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件夹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('拖入的是文件夹。要播放其中的媒体文件吗？'),
            const SizedBox(height: 8),
            Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('播放'),
          ),
        ],
      ),
    );
    if (play != true) {
      return;
    }
    await _playFolder(folder);
  }

  void _setDragHover(bool value) {
    if (!mounted || _dragHover == value) {
      return;
    }
    setState(() => _dragHover = value);
  }

  // -------------------------------------------------------------- playback

  Future<void> _play(List<String> paths, {int index = 0}) async {
    final items = [
      for (final path in paths)
        PlayerPlaylistItem(
          title: MediaClassifier.fileNameOf(path),
          path: path,
        ),
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
        // M3: the playlist can hold remote URLs (打开 URL / drops); only real
        // local files claim local playback, which feeds the demuxer cache and
        // metered-network policy (playback_cache_policy.dart).
        isLocalPlayback: !MediaClassifier.isRemote(item.path),
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

  // ------------------------------------------------------------- rendering

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final hasCurrent = _hasCurrent;
      return DropTarget(
        onDragEntered: (_) => _setDragHover(true),
        onDragExited: (_) => _setDragHover(false),
        onDragDone: (details) {
          _setDragHover(false);
          final urls = [for (final file in details.files) file.path];
          if (urls.isEmpty) {
            return;
          }
          unawaited(
              _executePlan(MediaClassifier.planDrop(urls, hasCurrent)));
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              backgroundColor: Colors.black,
              body: hasCurrent
                  ? PlayerItem(
                      playerController: _playerController,
                      playerPageController: _pageController,
                      fillsWindow: true,
                      // 常驻单实例约束在后续阶段落地；离开播放页即释放播放器。
                      onBackPressed: _handleBack,
                      onSelectItem: _selectItem,
                      onLoadSubtitle: _loadSubtitle,
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
                            FilledButton.tonalIcon(
                              onPressed: _openUrl,
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('打开 URL'),
                            ),
                            // Phones pick folders poorly; the library tab is
                            // where the storage auto-scan lives.
                            if (!isDesktop())
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    context.navigate('/tab/library/'),
                                icon: const Icon(Icons.video_library_rounded),
                                label: const Text('媒体库'),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            // Visual half of the drag-and-drop contract (1.x qml/DropOverlay.
            // qml): a translucent scrim that says what will happen on
            // release, so a drop is never a surprise.
            if (_dragHover)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xd9191a21),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.movie_creation_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '松开即可播放',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '视频、音频、字幕或文件夹',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
