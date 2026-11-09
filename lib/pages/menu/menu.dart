import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/widget/embedded_native_control_area.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/navigation.dart';
import 'package:emoplay/pages/menu/route_visibility.dart';
import 'package:emoplay/pages/router.dart';

/// Localized labels for the five EmoPlay tabs (docs/SPEC.md §5), in
/// navigation order. The bottom NavigationBar and the landscape
/// NavigationRail share this one list so the two shells can never drift
/// apart (1.x kept both label sets on the same tab model in qml/Main.qml).
/// First strings migrated to AppLocalizations (OVERNIGHT-LOOP §四 backlog 8:
/// the arb keys were established in R2 `b61dff2`; this is the page wiring).
List<String> menuTabLabels(AppLocalizations l10n) => <String>[
      l10n.tabHome,
      l10n.tabLibrary,
      l10n.tabPlayer,
      l10n.tabPlugins,
      l10n.tabSettings,
    ];

/// Tab shell: portrait NavigationBar / landscape NavigationRail, hosting the
/// five EmoPlay tabs (docs/SPEC.md §5). Page state survives tab switches via
/// the RouterOutlet.
class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      EmoDialog.showToast(
          message: AppLocalizations.of(context).doubleBackToExit,
          context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  /// Page-switch shortcuts ported from 1.x `qml/Main.qml:502-506`
  /// (Ctrl+1..5 → 首页/媒体库/播放/插件/设置). Only fires for focus inside
  /// the tab shell: dialogs run in their own focus path and the player's
  /// shortcut layer ignores modified keys, so Ctrl+1..5 fall through to here.
  Map<ShortcutActivator, VoidCallback> get _tabSwitchShortcuts => {
        for (var i = 0; i < menu.menuList.length; i++)
          SingleActivator(
            [
              LogicalKeyboardKey.digit1,
              LogicalKeyboardKey.digit2,
              LogicalKeyboardKey.digit3,
              LogicalKeyboardKey.digit4,
              LogicalKeyboardKey.digit5,
            ][i],
            control: true,
          ): () => _selectDestination(i),
      };

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: CallbackShortcuts(
        bindings: _tabSwitchShortcuts,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _handleSystemBack(context);
            }
          },
          child: OrientationBuilder(
            builder: (context, orientation) {
              return orientation == Orientation.portrait
                  ? _bottomMenu(context, _selectedIndex)
                  : _sideMenu(context, _selectedIndex);
            },
          ),
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    final labels = menuTabLabels(AppLocalizations.of(context));
    return Scaffold(
      body: _outlet(context),
      bottomNavigationBar: NavigationBar(
        destinations: <Widget>[
          NavigationDestination(
            selectedIcon: const Icon(Icons.home),
            icon: const Icon(Icons.home_outlined),
            label: labels[0],
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.video_library),
            icon: const Icon(Icons.video_library_outlined),
            label: labels[1],
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.play_circle),
            icon: const Icon(Icons.play_circle_outline),
            label: labels[2],
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.extension),
            icon: const Icon(Icons.extension_outlined),
            label: labels[3],
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.settings),
            icon: const Icon(Icons.settings_outlined),
            label: labels[4],
          ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _sideMenu(BuildContext context, int selectedIndex) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    final labels = menuTabLabels(AppLocalizations.of(context));
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              labelType: NavigationRailLabelType.selected,
              destinations: <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: const Icon(Icons.home),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(labels[0]),
                ),
                NavigationRailDestination(
                  selectedIcon: const Icon(Icons.video_library),
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(labels[1]),
                ),
                NavigationRailDestination(
                  selectedIcon: const Icon(Icons.play_circle),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(labels[2]),
                ),
                NavigationRailDestination(
                  selectedIcon: const Icon(Icons.extension),
                  icon: const Icon(Icons.extension_outlined),
                  label: Text(labels[3]),
                ),
                NavigationRailDestination(
                  selectedIcon: const Icon(Icons.settings),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(labels[4]),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectDestination,
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }
}
