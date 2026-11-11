import 'package:flutter/material.dart';

enum PlayerTimeLabelPlacement {
  aboveProgress,
  besideProgress,
  afterPlaybackButtons;

  static PlayerTimeLabelPlacement forViewport(Size viewport,
      {required bool desktop}) {
    if (desktop) return afterPlaybackButtons;
    final hasRoomForSideLabels = viewport.shortestSide >= 600 &&
        viewport.shortestSide / viewport.longestSide >= 9 / 16;
    return hasRoomForSideLabels ? besideProgress : aboveProgress;
  }
}

class PlayerTransportBar extends StatelessWidget {
  const PlayerTransportBar({
    super.key,
    required this.compact,
    required this.playPause,
    required this.nextEpisode,
    required this.progressBuilder,
    required this.timeLabel,
    required this.timePlacement,
    required this.controls,
    required this.fullscreen,
    this.frameStepBack,
    this.frameStepForward,
  });

  final bool compact;
  final Widget playPause;
  final Widget nextEpisode;
  final Widget Function({required bool sideLabels}) progressBuilder;
  final Widget timeLabel;
  final PlayerTimeLabelPlacement timePlacement;
  final Widget controls;
  final Widget fullscreen;

  /// M3 施工件 C「逐帧」：暂停态显示的上一帧/下一帧按钮（mpv OSC 的
  /// frame-step 惯例位：上一帧在播放键左侧、下一帧在播放键右侧）；null 时
  /// 完全不占位。播放态由调用方传 null 隐藏。
  final Widget? frameStepBack;
  final Widget? frameStepForward;

  @override
  Widget build(BuildContext context) => compact
      ? Row(children: [
          playPause,
          Expanded(child: progressBuilder(sideLabels: false)),
          timeLabel,
          fullscreen,
        ])
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timePlacement == PlayerTimeLabelPlacement.aboveProgress)
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 10),
                child: timeLabel,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: progressBuilder(
                sideLabels:
                    timePlacement == PlayerTimeLabelPlacement.besideProgress,
              ),
            ),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  ?frameStepBack,
                  playPause,
                  ?frameStepForward,
                  nextEpisode,
                  if (timePlacement ==
                      PlayerTimeLabelPlacement.afterPlaybackButtons)
                    Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: timeLabel),
                  Expanded(child: controls),
                  fullscreen,
                ])),
            if (timePlacement != PlayerTimeLabelPlacement.aboveProgress)
              const SizedBox(height: 6),
          ],
        );
}
