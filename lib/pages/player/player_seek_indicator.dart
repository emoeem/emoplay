import 'dart:async';

import 'package:flutter/material.dart';

/// Which side of the video a double tap landed on. Ported from PiliPlus
/// `plugin/pl_player/models/double_tap_type.dart` (left/center/right).
enum PlayerDoubleTapZone { backward, center, forward }

/// Double-tap zone math from PiliPlus `pl_player/view/view.dart`
/// `onDoubleTapDownMobile` (L1107-1121): the left quarter seeks backward, the
/// middle half toggles playback, the right quarter seeks forward.
PlayerDoubleTapZone playerDoubleTapZoneFor(double dx, double width) {
  final double sectionWidth = width / 4;
  if (dx < sectionWidth) {
    return PlayerDoubleTapZone.backward;
  }
  if (dx < sectionWidth * 3) {
    return PlayerDoubleTapZone.center;
  }
  return PlayerDoubleTapZone.forward;
}

/// Accumulating seek overlay, rewritten from PiliPlus
/// `plugin/pl_player/widgets/forward_seek.dart` / `backward_seek.dart`
/// (plain StatefulWidgets there too; the GetX part — the mount flags in
/// PlPlayerController — becomes MobX observables on the panel controller).
///
/// Every extra tap on the overlay adds one more [step]; exactly one
/// [onSubmitted] fires 400 ms after the last tap, so the accumulated seek is
/// applied once instead of per tap.
class PlayerSeekIndicator extends StatefulWidget {
  const PlayerSeekIndicator({
    super.key,
    required this.forward,
    required this.step,
    required this.onSubmitted,
  });

  /// True for the right-side forward overlay, false for backward.
  final bool forward;
  final Duration step;
  final ValueChanged<Duration> onSubmitted;

  @override
  State<PlayerSeekIndicator> createState() => _PlayerSeekIndicatorState();
}

class _PlayerSeekIndicatorState extends State<PlayerSeekIndicator> {
  late Duration duration;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    duration = widget.step;
    timer = Timer(const Duration(milliseconds: 400), () {
      widget.onSubmitted(duration);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _increment() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 400), () {
      widget.onSubmitted(duration);
    });
    setState(() {
      duration += widget.step;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inSeconds;
    final String text = widget.forward ? '快进$seconds秒' : '快退$seconds秒';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        splashColor: const Color(0x44767676),
        onTap: _increment,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.forward
                  ? const [
                      Color(0x00767676),
                      Color(0x88767676),
                    ]
                  : const [
                      Color(0x88767676),
                      Color(0x00767676),
                    ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                widget.forward ? Icons.fast_forward : Icons.fast_rewind,
                size: 24.0,
                color: Colors.white,
              ),
              const SizedBox(height: 8.0),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12.0,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mounts the PiliPlus seek overlays above the gesture layer while a
/// double-tap zone is active, with the 500 ms fade-in of view.dart L1922-1968.
/// The layout mirrors PiliPlus: backward overlay on the left, forward on the
/// right, the middle left empty for the tap-through play/pause zone.
class PlayerSeekIndicatorOverlay extends StatelessWidget {
  const PlayerSeekIndicatorOverlay({
    super.key,
    required this.showBackward,
    required this.showForward,
    required this.step,
    required this.onSubmitted,
  });

  final bool showBackward;
  final bool showForward;
  final Duration step;
  final ValueChanged<Duration> onSubmitted;

  Widget _indicator(bool forward) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: child,
        ),
        child: PlayerSeekIndicator(
          forward: forward,
          step: step,
          onSubmitted: onSubmitted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Row(
        children: [
          if (showBackward) _indicator(false),
          const Spacer(flex: 2),
          if (showForward) _indicator(true),
        ],
      ),
    );
  }
}
