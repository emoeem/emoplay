// P7 音乐模式页（歌词页 + 折叠均衡器面板）— qml/MusicPage.qml 的 Flutter
// 对应件。挂在播放页 Stack 顶层，musicController.audioMode 为真时覆盖视频
// 表面；播放控制仍在底部栏（P7 v1 范围），本页只加：大号媒体标题头、滚动
// 歌词列表、可折叠的 10 段均衡器面板。
//
// 滑杆/开关值遵循 1.x 的 imperative-sync 约定（docs/architecture.md
// 「QML 状态同步模式」）：用户编辑调用控制器 setter，控制器更新通过
// ListenableBuilder 拉回——声明式绑定会在第一次拖动时被摧毁，所以拖动中
// 的滑杆不回读控制器值。
library;

import 'package:flutter/material.dart';

import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/music_controller.dart';

/// 10 个固定频点的短标签（31.25 Hz .. 16 kHz）。
const List<String> _bandLabels = <String>[
  '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k', //
];

const Map<String, String> _presetLabels = <String, String>{
  'flat': '平坦',
  'bass': '低音增强',
  'vocal': '人声',
  'live': '现场',
};

class MusicLyricsPage extends StatefulWidget {
  const MusicLyricsPage({super.key});

  @override
  State<MusicLyricsPage> createState() => _MusicLyricsPageState();
}

class _MusicLyricsPageState extends State<MusicLyricsPage> {
  bool _eqPanelVisible = false;

  String _subtitle(MusicController music) {
    final parts = <String>[];
    final lrc = music.lrcMetadata;
    if ((lrc['artist'] ?? '').isNotEmpty) {
      parts.add(lrc['artist']!);
    }
    if ((lrc['album'] ?? '').isNotEmpty) {
      parts.add(lrc['album']!);
    }
    if (parts.isEmpty) {
      final meta = music.mediaMetadata;
      if ((meta['artist'] ?? '').isNotEmpty) {
        parts.add(meta['artist']!);
      }
      if ((meta['album'] ?? '').isNotEmpty) {
        parts.add(meta['album']!);
      }
    }
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final music = MediaStores.instance.music;
    return ListenableBuilder(
      listenable: music,
      builder: (context, _) {
        if (!music.audioMode) {
          // Hidden: no click absorption, the video surface keeps its
          // gestures.
          return const SizedBox.shrink();
        }
        // Absorb pointer events so they never reach the video gesture layer:
        // the music page has no click-to-pause; the bottom bar owns
        // playback (1.x MouseArea with accepted = true).
        return GestureDetector(
          onTap: () {}, // absorbed
          onDoubleTap: () {}, // absorbed
          onLongPress: () {}, // absorbed
          child: Container(
            color: const Color(0xF0101014),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 104),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      music.mediaTitle.isNotEmpty ? music.mediaTitle : 'Music',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFe8e8ee),
                      ),
                    ),
                    if (_subtitle(music).isNotEmpty)
                      Text(
                        _subtitle(music),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8a8a96),
                        ),
                      ),
                    Expanded(child: _LyricList(music: music)),
                    _EqToggle(
                      visible: _eqPanelVisible,
                      onToggle: () =>
                          setState(() => _eqPanelVisible = !_eqPanelVisible),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.topCenter,
                      child: _eqPanelVisible
                          ? _EqualizerPanel(music: music)
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricList extends StatefulWidget {
  const _LyricList({required this.music});

  final MusicController music;

  @override
  State<_LyricList> createState() => _LyricListState();
}

class _LyricListState extends State<_LyricList> {
  // Fixed line extent so index-based centering stays deterministic
  // (interlude lines render as a dot at the same height).
  static const double _extent = 40;

  final ScrollController _scroll = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index < 0 || !_scroll.hasClients) {
      return;
    }
    final viewport = _scroll.position.viewportDimension;
    final target = (index * _extent - viewport / 2 + _extent / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((_scroll.offset - target).abs() <= 1) {
      return;
    }
    // Follow the highlighted line (1.x positionViewAtIndex(ListView.Center)).
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.music.lyrics;
    final index = widget.music.lyricIndex;
    if (lyrics.isEmpty) {
      return const Center(
        child: Text(
          '未找到歌词 — 请在音频文件旁放置同名 .lrc 文件',
          style: TextStyle(color: Color(0xFF8a8a96)),
        ),
      );
    }
    if (index != _lastIndex) {
      _lastIndex = index;
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(index));
    }
    return ListView.builder(
      controller: _scroll,
      clipBehavior: Clip.hardEdge,
      itemExtent: _extent,
      itemCount: lyrics.length,
      itemBuilder: (context, i) {
        final current = i == index;
        final text = lyrics[i]['text'] as String? ?? '';
        return Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: TextStyle(
              fontSize: current ? 22 : 16,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal,
              color: current
                  ? const Color(0xFF4f8cff)
                  : const Color(0xFF6f6f7a),
            ),
            child: Text(
              text.isNotEmpty ? text : '·',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}

class _EqToggle extends StatelessWidget {
  const _EqToggle({required this.visible, required this.onToggle});

  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onToggle,
        icon: Icon(
          visible ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
          size: 16,
          color: const Color(0xFFcfcfd8),
        ),
        label: const Text(
          '均衡器',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFe8e8ee),
          ),
        ),
      ),
    );
  }
}

class _EqualizerPanel extends StatelessWidget {
  const _EqualizerPanel({required this.music});

  final MusicController music;

  @override
  Widget build(BuildContext context) {
    final gains = music.equalizerGains;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('启用',
                style: TextStyle(fontSize: 13, color: Color(0xFFcfcfd8))),
            Switch(
              value: music.equalizerEnabled,
              onChanged: (value) => music.setEqualizerEnabled(value),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: kPresetNames.contains(music.equalizerPreset)
                    ? music.equalizerPreset
                    : null,
                // "custom" has no dropdown entry: the field shows the hint
                // until a preset is picked (the 1.x combo reset to -1).
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                items: [
                  for (final preset in kPresetNames)
                    DropdownMenuItem(
                      value: preset,
                      child: Text(_presetLabels[preset] ?? preset,
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: music.equalizerEnabled
                    ? (value) {
                        if (value != null) {
                          music.applyEqualizerPreset(value);
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
        Text(
          music.equalizerEnabled
              ? '应用于 mpv 音频滤镜链'
              : '已停用 — 音频滤镜链保持不动',
          style: const TextStyle(fontSize: 11, color: Color(0xFF8a8a96)),
        ),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              for (var band = 0; band < MusicController.bandCount; ++band)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value:
                                (gains.length > band ? gains[band] : 0.0)
                                    .clamp(-MusicController.maxGain,
                                        MusicController.maxGain),
                            min: -MusicController.maxGain,
                            max: MusicController.maxGain,
                            // Integer dB steps, snap-always like 1.x.
                            divisions:
                                (MusicController.maxGain * 2).round(),
                            label:
                                '${gains.length > band ? gains[band].round() : 0}',
                            // Integer-dB divisions snap, so the controller's
                            // clamped value always equals the slider's —
                            // values can be read straight back without a
                            // drag guard.
                            onChanged: music.equalizerEnabled
                                ? (value) => music.setEqualizerBand(band, value)
                                : null,
                          ),
                        ),
                      ),
                      Text(
                        _bandLabels[band],
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF8a8a96)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
