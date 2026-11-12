// Plugin operation actions, separated from the views (M6-T4,
// docs/EMOPLAY-3.0-ROADMAP.md §五; Kazumi plugin_update_actions.dart 同构 —
// updatePluginWithFeedback / updateAllPluginsWithFeedback live outside the
// catalog and detail views so every caller shares one flow).
//
// The three-stage contract (SPEC §4.6 不变量 6): planOperation → UI 确认 →
// 执行. Enable/disable is the documented exception carried over from 1.x:
// it is non-destructive and reversible (the scripts option is only
// assembled at the next launch), so it applies immediately and is never
// planned — planOperation would refuse it as an unknown action, leaving the
// switch stuck on the model value.
//
// Check-mode plugins ("本地定制永不覆盖") keep their 1.x semantics through
// the manager: updates only compare the remote HEAD with the manifest
// baseline via git ls-remote; replace-mode updates are refused when local
// modifications are detected. This module only orchestrates; it never
// touches files itself.
library;

import 'package:flutter/material.dart';

import 'package:emoplay/bean/dialog/dialog.dart';
import 'package:emoplay/plugins/plugin_manager.dart';

/// Actions that apply immediately instead of being planned (see the module
/// doc: non-destructive, reversible, refused by planOperation by design).
const Set<String> immediatePluginActions = <String>{'enable', 'disable'};

/// Stage 1 — the plan. Returns null when [action] is the immediate
/// enable/disable pair (already applied to the manager); otherwise the plan
/// map from [PluginManager.planOperation]: 'title'/'details' for a real
/// plan, 'error' when the operation is refused before anything runs.
Map<String, Object?>? planPluginOperation(
  PluginManager manager,
  String name,
  String action,
) {
  if (immediatePluginActions.contains(action)) {
    manager.setEnabled(name, action == 'enable');
    return null;
  }
  return manager.planOperation(name, action);
}

/// Stage 2 — the confirmation dialog rendering the plan's change list.
/// The manager performs nothing without this consent (不变量 6).
Future<bool> confirmPluginPlan(
  BuildContext context,
  Map<String, Object?> plan,
) async {
  final confirmed = await EmoDialog.show<bool>(
    context: context,
    clickMaskDismiss: false,
    builder: (context) => AlertDialog(
      title: Text(plan['title']! as String),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in plan['details']! as List<String>)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Stage 3 — dispatch a CONFIRMED operation. This is the only funnel from
/// the UI to the manager's destructive trio; the switch mirrors the 1.x
/// executePending() (mpv-emo qml/PluginDrawer.qml) verbatim.
Future<void> executeConfirmedPluginOperation(
  PluginManager manager,
  String name,
  String action,
) async {
  switch (action) {
    case 'install':
      await manager.install(name);
    case 'uninstall':
      await manager.uninstall(name);
    case 'update':
      await manager.update(name);
  }
}

/// The full three-stage flow — one entry point for catalog rows and the
/// detail page (Kazumi updatePluginWithFeedback 同构). Refused plans and
/// cancelled confirmations are reported through [onStatus]; nothing is
/// executed in either case.
Future<void> beginPluginOperation(
  BuildContext context, {
  required PluginManager manager,
  required String name,
  required String action,
  required void Function(String message, bool isError) onStatus,
}) async {
  final plan = planPluginOperation(manager, name, action);
  if (plan == null) {
    return; // enable/disable applied immediately
  }
  if (plan.containsKey('error')) {
    onStatus(plan['error']! as String, true);
    return;
  }
  if (!context.mounted) {
    return;
  }
  final confirmed = await confirmPluginPlan(context, plan);
  if (!confirmed) {
    return; // refused: nothing was executed
  }
  await executeConfirmedPluginOperation(manager, name, action);
}
