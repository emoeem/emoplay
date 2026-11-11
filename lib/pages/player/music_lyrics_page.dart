// P7 音乐模式页（歌词页 + 折叠均衡器面板）— qml/MusicPage.qml 的 Flutter
// 对应件。挂在播放页 Stack 顶层，musicController.audioMode 为真时覆盖视频
// 表面；播放控制仍在底部栏（P7 v1 范围），本页只加：大号媒体标题头、滚动
// 歌词列表、可折叠的 10 段均衡器面板。
//
// M5-T3（docs/EMOPLAY-3.0-ROADMAP.md §五）歌词升级：
//
//  1. 逐行高亮精度 —— 滚动定位完全由 .lrc 时间戳驱动（MusicController 把
//     mpv time-pos 换算成 lyricIndex，本页把该行滚到视口中心，1.x
//     positionViewAtIndex(ListView.Center) 的语义）。在 1.x 对应件之上的
//     精度修复：
//       - 首帧定位不再丢失：此前只跟随 lyricIndex 变化，歌词加载晚于首帧
//         （mpv 探测后才有 .lrc）时第一行高亮不定位，直到下一行时间戳才
//         恢复跟随；现在首次构建即按当前 index 定位一次。
//       - 滚动动画时长与滚动距离成比例（120–420 ms 夹紧）：跨长间歇的
//         大跳不再 240 ms 硬拉，相邻行切换不再拖尾。
//  2. 翻译列（双语对照布局）—— 双语 .lrc 的通行约定：同一时间戳的相邻行
//     （时间排序后相邻）为一组，第一行原文、其余为译文（多时间戳展开
//     `[t1][t2] text` 产生的是不同时间、相同文本，不会误入该分组；病态
//     文件 `[t][t] 同文` 会照原样重复显示，与文件一致）。纯分组逻辑在
//     [groupLyricTranslations]，行高全为常量（40 + 24×译文数），滚动定位
//     因此保持确定性。无同时间戳行时布局退化为单语，与升级前一致。
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

// 行高常量：定位数学只依赖这些值（全部 maxLines 1 + ellipsis，永不换行），
// 所以滚动目标不需要测量即可精确计算。
const double kLyricMainExtent = 40;
const double kLyricTranslationExtent = 24;

/// 一行歌词及其译文（见文件头「翻译列」约定）。
@immutable
class LyricRow {
  const LyricRow({
    required this.time,
    required this.text,
    required this.translations,
  });

  final double time;
  final String text;

  /// 同时间戳的后续行（双语 .lrc 的译文）；单语歌词为空。
  final List<String> translations;

  double get extent =>
      kLyricMainExtent + translations.length * kLyricTranslationExtent;
}

/// 把 MusicController.lyrics（[{time, text}]，按时间排序）分组为
/// 原文 + 译文的行。相邻且时间完全相等的条目归入同组：首个为原文，其余
/// 为译文。纯函数、零依赖（test/music_lyrics_page_test.dart 直接覆盖）。
List<LyricRow> groupLyricTranslations(List<Map<String, Object?>> lyrics) {
  final rows = <LyricRow>[];
  for (final entry in lyrics) {
    final time = (entry['time'] as num?)?.toDouble() ?? 0.0;
    final text = entry['text'] as String? ?? '';
    final previous = rows.isEmpty ? null : rows.last;
    if (previous != null && previous.time == time) {
      // Same timestamp: the parser sorts by time, so identical timestamps
      // are adjacent. First line of the group is the original, the rest are
      // translations (bilingual .lrc convention).
      previous.translations.add(text);
      continue;
    }
    rows.add(LyricRow(
      time: time,
      text: text,
      translations: <String>[],
    ));
  }
  return rows;
}

/// 行 i 顶边的累积偏移（行高常量 ⇒ 纯前缀和，无测量）。
double lyricRowTopOffset(List<LyricRow> rows, int index) {
  var offset = 0.0;
  for (var i = 0; i < index && i < rows.length; ++i) {
    offset += rows[i].extent;
  }
  return offset;
}

/// 把行 [index] 滚到视口中心的滚动偏移（1.x positionViewAtIndex(Center)），
/// 夹紧到合法范围；[viewport] <= 0 或空表时返回 0。
double lyricScrollTarget(List<LyricRow> rows, int index, double viewport,
    {double maxScrollExtent = double.infinity}) {
  if (rows.isEmpty || viewport <= 0) {
    return 0;
  }
  final center = lyricRowTopOffset(rows, index) + rows[index].extent / 2;
  return (center - viewport / 2).clamp(0.0, maxScrollExtent);
}

/// 滚动动画时长：与滚动距离成比例（一个视口 240 ms），夹紧 120–420 ms。
Duration lyricScrollDuration(double distance, double viewport) {
  if (viewport <= 0) {
    return const Duration(milliseconds: 240);
  }
  final ms = 240.0 * (distance.abs() / viewport);
  return Duration(milliseconds: ms.round().clamp(120, 420));
}

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
  final ScrollController _scroll = ScrollController();

  // Follow bookkeeping: [groupLyricTranslations] output for the current
  // lyrics (a fresh list per controller load — identity detects reloads),
  // the last index we followed, and whether the first layout follow already
  // happened (M5-T3: the pre-upgrade code dropped positioning when lyrics
  // loaded after the first build and the index never changed afterwards).
  List<LyricRow> _rows = const <LyricRow>[];
  int _lastIndex = -1;
  bool _didFirstFollow = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Timestamp-driven follow: centers the active row (main + translations)
  /// in the viewport with a distance-proportional animation.
  void _follow(int index) {
    if (index < 0 || index >= _rows.length || !_scroll.hasClients) {
      return;
    }
    _didFirstFollow = true;
    final position = _scroll.position;
    final target = lyricScrollTarget(
      _rows,
      index,
      position.viewportDimension,
      maxScrollExtent: position.maxScrollExtent,
    );
    if ((_scroll.offset - target).abs() <= 1) {
      return;
    }
    _scroll.animateTo(
      target,
      duration: lyricScrollDuration(
        (_scroll.offset - target).abs(),
        position.viewportDimension,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;
    final lyrics = music.lyrics;
    final index = music.lyricIndex;
    if (lyrics.isEmpty) {
      // Graceful degradation: no .lrc next to the audio file — keep the page
      // (header/EQ stay usable), show the hint instead of an empty list.
      _rows = const <LyricRow>[];
      _lastIndex = -1;
      _didFirstFollow = false;
      return const Center(
        child: Text(
          '未找到歌词 — 请在音频文件旁放置同名 .lrc 文件',
          style: TextStyle(color: Color(0xFF8a8a96)),
        ),
      );
    }
    if (!identical(lyrics, _lyricsSource)) {
      _lyricsSource = lyrics;
      _rows = groupLyricTranslations(lyrics);
      _lastIndex = -1;
      _didFirstFollow = false;
    }
    if (index != _lastIndex || !_didFirstFollow) {
      _lastIndex = index;
      // Post-frame: the viewport extent is only known after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(index));
    }
    return ListView.builder(
      controller: _scroll,
      clipBehavior: Clip.hardEdge,
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        final current = i == index;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kLyricMainExtent,
              child: Center(
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
                    row.text.isNotEmpty ? row.text : '·',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            for (final translation in row.translations)
              SizedBox(
                height: kLyricTranslationExtent,
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      fontSize: current ? 14 : 12,
                      color: current
                          ? const Color(0xFF8fb3ff)
                          : const Color(0xFF585862),
                    ),
                    child: Text(
                      translation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The lyrics list instance the current [_rows] were built from.
  List<Map<String, Object?>>? _lyricsSource;
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
