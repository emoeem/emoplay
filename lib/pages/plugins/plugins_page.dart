import 'package:flutter/material.dart';

import 'package:emoplay/bean/widget/empty_state_widget.dart';

/// 插件 Tab.
///
/// M1 skeleton: the six bundled scripts (uosc/uosc_danmaku/anime4k/
/// file_browser/hdr-toys/trakt_scrobble), online sources and the three-step
/// install flow (planOperation → confirm → execute) arrive with the ported
/// PluginManager in M6 (docs/SPEC.md §5, docs/PORT-MAP.md §1).
class PluginsPage extends StatelessWidget {
  const PluginsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件'),
        centerTitle: false,
      ),
      body: GeneralEmptyState(
        icon: Icons.extension_outlined,
        title: '插件服务尚未接入',
        actions: [
          FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新在线源'),
          ),
        ],
      ),
    );
  }
}
