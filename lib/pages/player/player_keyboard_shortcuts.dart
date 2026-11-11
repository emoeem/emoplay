import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/pages/player/controller/player_page_controller.dart';
import 'package:emoplay/pages/player/player_adjustment_hud.dart';
import 'package:emoplay/pages/player/player_controller.dart';
import 'package:emoplay/services/logging/logger.dart';
import 'package:emoplay/services/storage/storage.dart';
import 'package:emoplay/utils/constants.dart';
import 'package:emoplay/utils/device.dart';
import 'package:window_manager/window_manager.dart';

typedef PlayerShortcutAction = FutureOr<void> Function();

class PlayerLongPressShortcutActions {
  const PlayerLongPressShortcutActions({
    required this.onRepeat,
    required this.onRelease,
  });

  final PlayerShortcutAction onRepeat;
  final PlayerShortcutAction onRelease;
}

/// Dispatches player shortcuts before focused controls handle the key event.
///
/// [focusScopeNode] must be attached to a stable ancestor of the player area.
/// Dialog routes and explicitly blocked overlay interactions keep their normal
/// key handling. Active long-press shortcuts are always released, even after
/// focus leaves the player or this widget is disposed.
class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.focusScopeNode,
    required this.actions,
    this.longPressActions = const <String, PlayerLongPressShortcutActions>{},
    this.isBlocked,
    this.shortcuts,
  });

  final FocusNode focusScopeNode;
  final Map<String, PlayerShortcutAction> actions;
  final Map<String, PlayerLongPressShortcutActions> longPressActions;
  final bool Function()? isBlocked;
  final Map<String, List<String>>? shortcuts;

  @override
  State<PlayerKeyboardShortcuts> createState() =>
      _PlayerKeyboardShortcutsState();
}

class _PlayerKeyboardShortcutsState extends State<PlayerKeyboardShortcuts> {
  late Map<String, List<String>> _shortcuts;
  final Map<LogicalKeyboardKey, PlayerLongPressShortcutActions>
      _activeLongPressKeys =
      <LogicalKeyboardKey, PlayerLongPressShortcutActions>{};

  @override
  void initState() {
    super.initState();
    _shortcuts = widget.shortcuts ?? _loadShortcuts();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(PlayerKeyboardShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shortcuts != oldWidget.shortcuts) {
      _shortcuts = widget.shortcuts ?? _loadShortcuts();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    _releaseAllLongPressShortcuts();
    super.dispose();
  }

  Map<String, List<String>> _loadShortcuts() {
    return <String, List<String>>{
      for (final entry in defaultShortcuts.entries)
        entry.key: GStorage.getStringListSettingByName(
          'shortcut_${entry.key}',
          defaultValue: entry.value,
        ),
    };
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      final longPressActions = _activeLongPressKeys.remove(event.logicalKey);
      if (longPressActions != null) {
        _invokeAction(longPressActions.onRelease);
        return KeyEventResult.handled;
      }
    }

    if (!_shouldHandleShortcut()) {
      return KeyEventResult.ignored;
    }

    final actionName = _findActionName(_keyIdentity(event));
    if (actionName == null) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      final action = widget.actions[actionName];
      if (action == null) {
        return KeyEventResult.ignored;
      }
      final longPressActions = widget.longPressActions[actionName];
      if (longPressActions != null) {
        _activeLongPressKeys[event.logicalKey] = longPressActions;
      }
      _invokeAction(action);
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      final longPressActions = _activeLongPressKeys[event.logicalKey];
      if (longPressActions == null) {
        return KeyEventResult.ignored;
      }
      _invokeAction(longPressActions.onRepeat);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _shouldHandleShortcut() {
    if (widget.isBlocked?.call() ?? false) {
      return false;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }

    // 播放器快捷键 = "页面可见即全局"（PiliPlus player_focus 语义）：路由
    // current + 焦点不在任何文本框即可。旧的"主焦点必须落在 keyboardFocus
    // 子树"判定依赖外部有人 requestFocus——全工程从没人请求过它，导致播放
    // 时所有快捷键在这里被静默拒绝。
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusContext = primaryFocus?.context;
    if (focusContext == null) {
      return true;
    }
    return focusContext.widget is! EditableText &&
        focusContext.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  String? _findActionName(String keyLabel) {
    for (final entry in _shortcuts.entries) {
      if (entry.value.contains(keyLabel)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Identity of the key including non-shift modifiers, so a bare '1' entry
  /// matches Digit1 but not Ctrl+Digit1 — modified keys fall through to the
  /// app shell instead (1.x keeps Ctrl+1..5 for page switching, and forwards
  /// everything unhandled to mpv's own key layer). Shift stays implicit:
  /// Flutter already reflects it in the label of letter keys.
  String _keyIdentity(KeyEvent event) {
    final modifiers = <String>[
      if (HardwareKeyboard.instance.isControlPressed) 'ctrl',
      if (HardwareKeyboard.instance.isAltPressed) 'alt',
      if (HardwareKeyboard.instance.isMetaPressed) 'meta',
    ];
    final label = event.logicalKey.keyLabel.isNotEmpty
        ? event.logicalKey.keyLabel
        : event.logicalKey.debugName ?? '';
    return [...modifiers, label].join('+');
  }

  void _releaseAllLongPressShortcuts() {
    final actions = _activeLongPressKeys.values.toSet();
    _activeLongPressKeys.clear();
    for (final action in actions) {
      _invokeAction(action.onRelease);
    }
  }

  void _invokeAction(PlayerShortcutAction action) {
    unawaited(_runAction(action));
  }

  Future<void> _runAction(PlayerShortcutAction action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'player keyboard shortcuts',
          context: ErrorDescription('while invoking a player shortcut'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Shortcut action implementations extracted from player_item.dart (M3-T0
/// god-class split; pure move, no behavior change).
///
/// Builds the action maps consumed by [PlayerKeyboardShortcuts] and hosts the
/// handler bodies behind them (seek/speed/volume/sub-delay/fullscreen/playlist
/// stepping). The host state stays responsible for timers, panel holds and the
/// screenshot flow, which arrive as callbacks.
class PlayerShortcutHandlers {
  PlayerShortcutHandlers({
    required this.playerSetState,
    required this.playerController,
    required this.playerPageController,
    required this.hud,
    required this.seekWithPlayerTimer,
    required this.onSelectItem,
    required this.onScreenshot,
  }) : longPressPlaySpeed =
            GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);

  /// Wraps the host's [State.setState] (long-press speed restore toggles
  /// widget-local state the same way the inline closure did).
  final void Function(VoidCallback fn) playerSetState;
  final PlayerController playerController;
  final PlayerPageController playerPageController;
  final PlayerAdjustmentHudScheduler hud;

  /// Cancels the 1s heartbeat for the duration of a shortcut seek and
  /// restarts it afterwards (player_item _seekWithPlayerTimer).
  final Future<void> Function(Future<void> Function() seekAction)
      seekWithPlayerTimer;

  /// Switches the player to the playlist entry at the given index
  /// (player_item widget.onSelectItem).
  final Future<void> Function(int index) onSelectItem;

  /// Desktop screenshot capture entry (player_item handleScreenshot).
  final Future<void> Function() onScreenshot;

  double lastPlayerSpeed = 1.0;

  /// Temporary long-press speed (SettingsKeys.defaultShortcutForwardPlaySpeed,
  /// read at initState timing as before).
  late final double longPressPlaySpeed;

  /// True while a long press has switched to the temporary speed and the
  /// matching end/cancel must restore it (PiliPlus setLongPressStatus).
  bool _longPressSpeedEngaged = false;

  late final Map<String, PlayerShortcutAction> actions = _buildActions();
  late final Map<String, PlayerLongPressShortcutActions> longPressActions =
      _buildLongPressActions();

  Map<String, PlayerShortcutAction> _buildActions() {
    return {
      'playorpause': () => playerController.playOrPause(),
      'forward': handleShortcutForwardDown,
      'rewind': handleShortcutRewind,
      'next': () => handlePreNextItem('next'),
      'prev': () => handlePreNextItem('prev'),
      'volumeup': () => handleShortcutVolumeChange('up'),
      'volumedown': () => handleShortcutVolumeChange('down'),
      'togglemute': () => handleShortcutVolumeChange('mute'),
      'fullscreen': () => handleShortcutFullscreen(),
      'screenshot': onScreenshot,
      'skip': skipOP,
      'exitfullscreen': () => handleShortcutExitFullscreen(),
      'speed1': () => setPlaybackSpeed(1.0),
      'speed2': () => setPlaybackSpeed(2.0),
      'speed3': () => setPlaybackSpeed(3.0),
      'speedup': () => handleSpeedChange('up'),
      'speeddown': () => handleSpeedChange('down'),
      // M3 字幕管理：sub-delay ±0.5s 步进（无播放器/无媒体时是安全空操作）。
      'subdelaydown': () => handleSubDelayChange(-1),
      'subdelayup': () => handleSubDelayChange(1),
      // M3-T2 章节导航：无章节的文件上这两个动作是安全的空操作。
      'nextchapter': () => playerController.chapters.nextChapter(),
      'prevchapter': () => playerController.chapters.previousChapter(),
      // M3 施工件 C「A-B 循环 + 逐帧」：无播放器时均为安全空操作。
      'abloop': () => playerController.cycleAbLoop(),
      'framestep': () => playerController.frameStep(1),
      'framebackstep': () => playerController.frameStep(-1),
    };
  }

  Map<String, PlayerLongPressShortcutActions> _buildLongPressActions() {
    return {
      'forward': PlayerLongPressShortcutActions(
        onRepeat: handleShortcutForwardRepeat,
        onRelease: handleShortcutForwardUp,
      ),
      // PiliPlus player_focus.dart holds ArrowUp/ArrowDown to keep changing
      // the volume; the repeat rate is the system key-repeat rate.
      'volumeup': PlayerLongPressShortcutActions(
        onRepeat: () => handleShortcutVolumeChange('up'),
        onRelease: () {},
      ),
      'volumedown': PlayerLongPressShortcutActions(
        onRepeat: () => handleShortcutVolumeChange('down'),
        onRelease: () {},
      ),
    };
  }

  Future<void> handlePreNextItem(String direction) async {
    if (playerPageController.loading) return;
    final index = playerPageController.currentIndex;
    final length = playerPageController.playlist.length;
    int targetIndex;
    if (direction == 'next') {
      targetIndex = index + 1;
    } else if (direction == 'prev') {
      targetIndex = index - 1;
    } else {
      return;
    }

    if (targetIndex >= length) {
      EmoDialog.showToast(message: '已经是最后一个条目');
      return;
    }
    if (targetIndex < 0) {
      EmoDialog.showToast(message: '已经是第一个条目');
      return;
    }

    final target = playerPageController.itemAt(targetIndex);
    if (target != null) {
      EmoDialog.showToast(message: '正在加载${target.title}');
    }
    onSelectItem(targetIndex);
  }

  Future<void> handleShortcutRewind() async {
    try {
      await seekWithPlayerTimer(
        () => playerController.seekBy(
          Duration(seconds: -playerController.playback.arrowKeySkipTime),
        ),
      );
    } catch (e) {
      EmoLogger().e('PlayerController: seek failed', error: e);
    }
  }

  void handleShortcutForwardDown() {
    lastPlayerSpeed = playerController.playback.playerSpeed;
  }

  Future<void> handleShortcutForwardRepeat() async {
    final double defaultShortcutForwardPlaySpeed =
        GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);
    if (playerController.playback.playerSpeed <
        defaultShortcutForwardPlaySpeed) {
      playerController.panel
        ..showSubDelay = false
        ..showAbLoop = false
        ..showPlaySpeed = true;
      await setPlaybackSpeed(defaultShortcutForwardPlaySpeed);
    }
  }

  Future<void> handleShortcutForwardUp() async {
    if (playerController.panel.showPlaySpeed) {
      playerController.panel.showPlaySpeed = false;
      await setPlaybackSpeed(lastPlayerSpeed);
    } else {
      try {
        await seekWithPlayerTimer(
          () => playerController.seekBy(
            Duration(seconds: playerController.playback.arrowKeySkipTime),
          ),
        );
      } catch (e) {
        EmoLogger().e('PlayerController: seek failed', error: e);
      }
    }
  }

  void handleShortcutFullscreen() {
    if (!playerPageController.isPip) handleFullscreen();
  }

  /// ESC 优先级链（1.x qml/Main.qml:93 handleEscape）：对话框 → 播放器面板
  /// → 全屏 → 应用。M2 分层落地：
  /// - 对话框：Flutter 的 ModalRoute 自带 ESC 关闭；对话框打开时本快捷键层
  ///   被 `route.isCurrent` 守卫跳过，事件交还给对话框。
  /// - 播放器面板：音轨/播放列表面板未接线（SPEC §5 后续阶段），接入后应
  ///   在全屏之前先关面板（1.x PlayerPage.closeTopPanel）。
  /// - 全屏：退出窗口全屏。
  /// - 应用兜底：Kazumi 行为（桌面暂停并隐藏窗口）。
  void handleShortcutExitFullscreen() {
    if (playerPageController.isFullscreen) {
      unawaited(playerPageController.setFullscreen(false));
    } else if (isDesktop() && !Platform.isMacOS) {
      playerController.pause();
      windowManager.hide();
    }
  }

  void handleFullscreen() {
    if (!playerPageController.isPip) {
      unawaited(playerPageController.toggleFullscreen());
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await playerController.setPlaybackSpeed(speed);
  }

  Future<void> handleSpeedChange(String type) async {
    try {
      final currentSpeed = playerController.playback.playerSpeed;
      int index = defaultPlaySpeedList.indexOf(currentSpeed);
      if (type == "up") {
        if (index < defaultPlaySpeedList.length - 1) {
          index++;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          EmoDialog.showToast(message: '已达倍速上限');
        }
      } else if (type == "down") {
        if (index > 0) {
          index--;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          EmoDialog.showToast(message: '已达倍速下限');
        }
      }
    } catch (e) {
      EmoLogger().e('PlayerController: speed change failed', error: e);
    }
  }

  Future<void> handleShortcutVolumeChange(String type) async {
    try {
      switch (type) {
        case 'up':
          await playerController
              .setVolume(playerController.playback.volume + 10);
          break;
        case 'down':
          await playerController
              .setVolume(playerController.playback.volume - 10);
          break;
        case 'mute':
          await playerController.toggleMute();
          break;
        default:
          return;
      }
      hud.showVolumeAdjustmentHud();
      hud.scheduleAdjustmentHudHide(delay: const Duration(seconds: 1));
    } catch (e) {
      EmoLogger().e('PlayerController: volume change failed', error: e);
    }
  }

  /// M3 字幕管理：sub-delay ±0.5s（[direction] +1/-1），步骤到达引擎才弹
  /// HUD；无播放器/无媒体时 adjustSubDelay 是安全空操作。
  Future<void> handleSubDelayChange(int direction) async {
    try {
      final applied =
          await playerController.subtitles.adjustSubDelay(direction);
      if (!applied) {
        return;
      }
      hud.showSubDelayAdjustmentHud();
      hud.scheduleAdjustmentHudHide(delay: const Duration(seconds: 1));
    } catch (e) {
      EmoLogger().e('PlayerController: sub-delay change failed', error: e);
    }
  }

  Future<void> skipOP() async {
    await playerController.seekBy(
      Duration(seconds: playerController.playback.buttonSkipTime),
    );
  }

  /// Long-press speed engage (player_item GestureDetector onLongPressStart).
  void beginLongPressSpeed() {
    // PiliPlus setLongPressStatus: the temporary speed
    // only engages while playing, and the matching
    // end/cancel restores the previous speed.
    if (playerController.panel.lockPanel ||
        !playerController.playback.playerPlaying) {
      return;
    }
    playerSetState(() {
      _longPressSpeedEngaged = true;
      playerController.panel
        ..showSubDelay = false
        ..showAbLoop = false
        ..showPlaySpeed = true;
    });
    lastPlayerSpeed = playerController.playback.playerSpeed;
    setPlaybackSpeed(longPressPlaySpeed);
  }

  /// Long-press speed restore (player_item _finishLongPressSpeed).
  void finishLongPressSpeed() {
    if (!_longPressSpeedEngaged) {
      return;
    }
    playerSetState(() {
      _longPressSpeedEngaged = false;
      playerController.panel.showPlaySpeed = false;
    });
    setPlaybackSpeed(lastPlayerSpeed);
  }
}
