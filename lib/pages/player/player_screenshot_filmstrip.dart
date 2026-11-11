import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:emoplay/pages/player/controller/player_screenshot_controller.dart';
import 'package:emoplay/pages/player/player_screenshot_image.dart';
import 'package:emoplay/services/player/screenshot_candidate.dart';
import 'package:emoplay/services/player/screenshot_image_cache.dart';

/// Horizontal candidate filmstrip extracted from player_screenshot_sheet.dart
/// (M3-T0 review split; pure move, no behavior change — the classes were
/// library-private there and are renamed public here).
class PlayerScreenshotFilmstrip extends StatefulWidget {
  const PlayerScreenshotFilmstrip({
    super.key,
    required this.controller,
    required this.activeIndex,
    required this.compact,
    required this.duration,
    required this.onBrowse,
  });

  final PlayerScreenshotController controller;
  final int activeIndex;
  final bool compact;
  final Duration duration;
  final ValueChanged<int> onBrowse;

  @override
  State<PlayerScreenshotFilmstrip> createState() =>
      _PlayerScreenshotFilmstripState();
}

class _PlayerScreenshotFilmstripState extends State<PlayerScreenshotFilmstrip> {
  final ScrollController _scroll = ScrollController();
  double? _target;
  bool _positioned = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centerActive() {
    if (!mounted || !_scroll.hasClients) return;
    final offset = _target!.clamp(0.0, _scroll.position.maxScrollExtent);
    if (!_positioned || widget.duration == Duration.zero) {
      _scroll.jumpTo(offset);
      if (!_positioned) setState(() => _positioned = true);
    } else {
      _scroll.animateTo(
        offset,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Observer(
      builder: (context) {
        final items = widget.controller.candidates;
        final height = widget.compact ? 52.0 : 72.0;
        final extent = widget.compact ? 80.0 : 108.0;
        final padding = math.max(
          12.0,
          (constraints.maxWidth - items.length * extent) / 2,
        );
        final target =
            padding +
            (widget.activeIndex + 0.5) * extent -
            constraints.maxWidth / 2;
        if (_target != target) {
          _target = target;
          WidgetsBinding.instance.addPostFrameCallback((_) => _centerActive());
        }
        return SizedBox(
          height: height + (widget.compact ? 4 : 16),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: AnimatedOpacity(
              opacity: _positioned ? 1 : 0,
              duration: widget.duration == Duration.zero
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: widget.compact ? 2 : 8,
                ),
                itemExtent: extent,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Observer(
                    builder: (context) => PlayerScreenshotFrameThumbnail(
                      item: item,
                      index: index,
                      active: index == widget.activeIndex,
                      selected: widget.controller.isSelected(item),
                      duration: widget.duration,
                      onTap: () => widget.onBrowse(index),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );
}

class PlayerScreenshotFrameThumbnail extends StatelessWidget {
  const PlayerScreenshotFrameThumbnail({
    super.key,
    required this.item,
    required this.index,
    required this.active,
    required this.selected,
    required this.duration,
    required this.onTap,
  });
  final ScreenshotCandidate item;
  final int index;
  final bool active;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label:
          '查看第 ${index + 1} 张，${item.episode} ${item.timeLabel}${selected ? '，已选中' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeInOutCubicEmphasized,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: active ? colors.primary : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(active ? 12 : 8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlayerScreenshotImage(
                      bytes: item.bytes,
                      fit: BoxFit.cover,
                      cacheWidth: screenshotThumbnailCacheWidth,
                    ),
                    if (selected)
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
