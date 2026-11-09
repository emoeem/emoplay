// First-run wizard for the mpv compat layer — Dart port of mpv-emo
// qml/ImportWizard.qml (1.x was three choices + "don't ask again"; SPEC/ask
// M5 makes "skip" an explicit fourth choice). Shown when a user mpv
// configuration directory was detected and no decision has been recorded.
// Every outcome persists to settings.json and the imported engine options
// take effect on the next launch (1.x contract, kept: the preset is
// assembled once at MediaStores.init).
// EmoPlay never writes into the user's mpv directory in any mode.
import 'package:flutter/material.dart';

import 'package:emoplay/bean/dialog/dialog.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/compat/compat_controller.dart'
    show CompatController;

/// Shows the import wizard for |compat|. Safe to call when MediaStores is
/// not ready (no-op) — the init failure path must not be blocked by a
/// config import prompt.
Future<void> showMpvImportWizardDialog() async {
  if (!MediaStores.isReady) {
    return;
  }
  final compat = MediaStores.instance.compat;
  if (!compat.configDetected) {
    return;
  }
  await EmoDialog.show(
    clickMaskDismiss: false,
    builder: (context) => _ImportWizardDialog(compat: compat),
  );
}

enum _ImportMode { full, selective, standalone, skip }

class _ImportWizardDialog extends StatefulWidget {
  const _ImportWizardDialog({required this.compat});

  final CompatController compat;

  @override
  State<_ImportWizardDialog> createState() => _ImportWizardDialogState();
}

class _ImportWizardDialogState extends State<_ImportWizardDialog> {
  _ImportMode _mode = _ImportMode.full;

  // relativePath -> checked state for the selective mode checklist
  // (1.x checkedMap, everything pre-checked like resetCheckList()).
  final Map<String, bool> _checked = {};

  @override
  void initState() {
    super.initState();
    for (final file in widget.compat.importFiles) {
      _checked[file['relativePath']! as String] = true;
    }
  }

  void _confirm() {
    switch (_mode) {
      case _ImportMode.full:
        widget.compat.chooseFullImport();
        break;
      case _ImportMode.selective:
        widget.compat.chooseSelectiveImport([
          for (final entry in _checked.entries)
            if (entry.value) entry.key,
        ]);
        break;
      case _ImportMode.standalone:
        widget.compat.chooseStandalone();
        break;
      case _ImportMode.skip:
        widget.compat.skipAndDontAskAgain();
        break;
    }
    EmoDialog.dismiss();
  }

  // 1.x "Not now": close without persisting. With the escape-hatch checkbox
  // it degrades to skip + don't-ask-again, exactly like the QML footer.
  void _notNow() {
    if (_dontAskAgain) {
      widget.compat.skipAndDontAskAgain();
    }
    EmoDialog.dismiss();
  }

  bool _dontAskAgain = false;

  String get _confirmLabel {
    switch (_mode) {
      case _ImportMode.full:
        return '完整导入';
      case _ImportMode.selective:
        return '导入选中项';
      case _ImportMode.standalone:
        return '使用独立配置';
      case _ImportMode.skip:
        return '跳过并不再询问';
    }
  }

  @override
  Widget build(BuildContext context) {
    final compat = widget.compat;
    final files = compat.importFiles;
    return AlertDialog(
      title: const Text('导入 mpv 配置'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '在 ${compat.sourceDir} 发现 mpv 配置，EmoPlay 应如何使用它？',
            ),
            const SizedBox(height: 8),
            RadioGroup<_ImportMode>(
              groupValue: _mode,
              onChanged: (mode) {
                if (mode != null) {
                  setState(() => _mode = mode);
                }
              },
              child: Column(
                children: [
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.full,
                    title: const Text('完整导入 — 选项、按键绑定、脚本、字体'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.selective,
                    title: const Text('选择性导入 — 从下方清单挑选'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.standalone,
                    title: const Text('独立配置 — 不使用现有 mpv 配置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.skip,
                    title: const Text('跳过 — 不导入且不再询问'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            // Selective checklist over the scanned files (entry counts from
            // the parser, sizes from the scan — 1.x ImportWizard.qml).
            Flexible(
              child: Opacity(
                opacity: _mode == _ImportMode.selective ? 1.0 : 0.35,
                child: IgnorePointer(
                  ignoring: _mode != _ImportMode.selective,
                  child: files.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('未发现可导入的文件'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: files.length,
                          itemBuilder: (context, index) {
                            final file = files[index];
                            final relativePath =
                                file['relativePath']! as String;
                            final entryCount = file['entryCount']! as int;
                            final kind = file['kind']! as String;
                            return CheckboxListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              value: _checked[relativePath] ?? false,
                              onChanged: (checked) => setState(
                                  () => _checked[relativePath] = checked ?? false),
                              title: Text(
                                '$relativePath  ($kind${entryCount > 0 ? ', $entryCount' : ''})',
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '导入的设置将在下次启动时生效。EmoPlay 绝不会修改你的 mpv 目录 — 只从中读取，写入都保存在自身数据目录内。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _dontAskAgain,
          onChanged: (checked) => setState(() => _dontAskAgain = checked ?? false),
          title: const Text('不再询问'),
        ),
        TextButton(
          onPressed: _notNow,
          child: Text(
            '稍后再说',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(_confirmLabel),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
