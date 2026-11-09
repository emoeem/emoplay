// 上游声明页：展示仓库根目录 NOTICE.md 的全文（GPL-3.0、Kazumi/PiliPlus/
// Anime4K/EmoPlay 1.x 的版权与许可声明）。NOTICE.md 作为资产打进应用
// （pubspec.yaml），页面只渲染、不裁决——许可以 NOTICE.md 与 LICENSE
// 原文为准（docs/SPEC.md §8）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  late Future<String> _text;

  @override
  void initState() {
    super.initState();
    _text = rootBundle.loadString('NOTICE.md', cache: false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('上游声明'),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final text = snapshot.data ??
              'NOTICE.md 读取失败。许可以仓库根目录的 NOTICE.md 与 LICENSE 原文为准。';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
            ),
          );
        },
      ),
    );
  }
}
