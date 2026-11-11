import 'dart:async';

import 'package:flutter/material.dart';
import 'package:emoplay/bean/widget/emo_menu.dart';
import 'package:emoplay/pages/player/player_controller.dart';

/// A one-shot lease that keeps the player panel visible until released.
class PlayerPanelHold {
  PlayerPanelHold({required VoidCallback onRelease}) : _onRelease = onRelease;

  VoidCallback? _onRelease;

  bool get isReleased => _onRelease == null;

  void release() {
    final onRelease = _onRelease;
    if (onRelease == null) {
      return;
    }
    _onRelease = null;
    onRelease();
  }

  void releaseSilently() {
    _onRelease = null;
  }
}

/// Release focus holds when resizing removes the input but preserves its panel.
class PlayerPanelHoldFocusRegion extends StatefulWidget {
  const PlayerPanelHoldFocusRegion({
    super.key,
    required this.acquirePlayerPanelHold,
    required this.child,
  });

  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final Widget child;

  @override
  State<PlayerPanelHoldFocusRegion> createState() =>
      _PlayerPanelHoldFocusRegionState();
}

class _PlayerPanelHoldFocusRegionState
    extends State<PlayerPanelHoldFocusRegion> {
  PlayerPanelHold? _hold;

  void _onFocusChange(bool focused) {
    if (focused) {
      _hold ??= widget.acquirePlayerPanelHold();
    } else {
      _hold?.release();
      _hold = null;
    }
  }

  @override
  void dispose() {
    _hold?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onFocusChange: _onFocusChange,
        child: widget.child,
      );
}

/// Release hover holds when their controls unmount.
class PlayerPanelHoldMouseRegion extends StatefulWidget {
  const PlayerPanelHoldMouseRegion({
    super.key,
    required this.acquirePlayerPanelHold,
    required this.child,
    this.cursor = MouseCursor.defer,
  });

  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final Widget child;
  final MouseCursor cursor;

  @override
  State<PlayerPanelHoldMouseRegion> createState() =>
      _PlayerPanelHoldMouseRegionState();
}

class _PlayerPanelHoldMouseRegionState
    extends State<PlayerPanelHoldMouseRegion> {
  PlayerPanelHold? _hold;

  @override
  void dispose() {
    _releaseHold();
    super.dispose();
  }

  void _acquireHold() {
    if (_hold?.isReleased == false) {
      return;
    }
    _hold = widget.acquirePlayerPanelHold();
  }

  void _releaseHold() {
    _hold?.release();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _acquireHold(),
      onExit: (_) => _releaseHold(),
      child: widget.child,
    );
  }
}

class PlayerPanelHoldMenuAnchor extends StatefulWidget {
  const PlayerPanelHoldMenuAnchor({
    super.key,
    required this.acquirePlayerPanelHold,
    required this.onVisibilityChanged,
    required this.builder,
    required this.menuChildren,
  });

  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onVisibilityChanged;
  final EmoMenuBuilder builder;
  final List<Widget> menuChildren;

  @override
  State<PlayerPanelHoldMenuAnchor> createState() =>
      _PlayerPanelHoldMenuAnchorState();
}

class _PlayerPanelHoldMenuAnchorState extends State<PlayerPanelHoldMenuAnchor> {
  PlayerPanelHold? _hold;
  bool _isOpen = false;

  @override
  void dispose() {
    _handleClose();
    super.dispose();
  }

  void _handleOpen() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    widget.onVisibilityChanged(true);
    _hold = widget.acquirePlayerPanelHold();
  }

  void _handleClose() {
    if (_isOpen) {
      _isOpen = false;
      widget.onVisibilityChanged(false);
    }
    _hold?.release();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    return EmoMenuButton(
      animated: false,
      onOpen: _handleOpen,
      onClose: _handleClose,
      builder: widget.builder,
      menuChildren: widget.menuChildren,
    );
  }
}

/// Panel visibility + hold registry extracted from player_item.dart (M3-T0
/// god-class split; pure move, no behavior change).
///
/// Owns the show/hide animation, the hide countdown and the one-shot leases
/// that keep the panel visible (progress-bar drag, menus, screenshot sheet).
/// The hosting state creates the [AnimationController] (it owns the
/// TickerProvider) and hands it in.
class PlayerPanelHoldRegistry {
  PlayerPanelHoldRegistry({
    required this.host,
    required this.playerController,
    required this.panelVisibility,
    required this.hideDelayMs,
  });

  /// Hosting player state; only [State.mounted] is used inside the hide timer.
  final State host;
  final PlayerController playerController;

  /// The forwarded/reversed panel visibility animation; the panel widget
  /// receives it as panelVisibilityController (player_item build).
  final AnimationController panelVisibility;

  /// Auto-hide delay in milliseconds
  /// (SettingsKeys.playerControllerLayerDisappearTime, read at initState).
  final int hideDelayMs;

  final Set<PlayerPanelHold> _playerPanelHolds = <PlayerPanelHold>{};
  Timer? _hideTimer;

  bool get canHidePlayerPanel =>
      playerController.panel.canHidePlayerPanel && _playerPanelHolds.isEmpty;

  void showVideoController({bool restartHideTimer = true}) {
    // Re-forwarding restarts the ticker and stalls a frame, so hover must not.
    if (!panelVisibility.isForwardOrCompleted) {
      panelVisibility.forward();
    }
    playerController.panel.showVideoController = true;
    if (restartHideTimer && canHidePlayerPanel) {
      _startHideTimer();
    }
  }

  void hideVideoController() {
    if (!canHidePlayerPanel) {
      return;
    }
    panelVisibility.reverse();
    _cancelHideTimer();
    playerController.panel.showVideoController = false;
  }

  PlayerPanelHold acquirePlayerPanelHold() {
    late final PlayerPanelHold hold;
    hold = PlayerPanelHold(
      onRelease: () {
        _playerPanelHolds.remove(hold);
        if (_playerPanelHolds.isNotEmpty) {
          return;
        }
        playerController.panel.canHidePlayerPanel = true;
        _startHideTimer();
      },
    );
    _playerPanelHolds.add(hold);
    playerController.panel.canHidePlayerPanel = false;
    _cancelHideTimer();
    showVideoController(restartHideTimer: false);
    return hold;
  }

  // Fullscreen and system overlays can dispose controls before their holds are released.
  // (The progress-bar drag hold lives in PlayerProgressPipeline; releasing it
  // silently here makes its later release() a no-op, same as before.)
  void releaseAllHolds() {
    for (final hold in _playerPanelHolds.toList()) {
      hold.releaseSilently();
    }
    _playerPanelHolds.clear();
    playerController.panel.canHidePlayerPanel = true;
    _startHideTimer();
  }

  void _startHideTimer() {
    _cancelHideTimer();
    if (!canHidePlayerPanel) {
      return;
    }
    _hideTimer = Timer(Duration(milliseconds: hideDelayMs), () {
      if (host.mounted) {
        hideVideoController();
      }
      _hideTimer = null;
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  /// Cancels the hide timer (player_item dispose).
  void dispose() {
    _hideTimer?.cancel();
  }
}
