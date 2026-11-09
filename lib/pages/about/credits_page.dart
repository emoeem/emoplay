import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/pages/about/about_widgets.dart';

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('致谢'),
        body: AboutContent(
          children: [
            ContentSection.group(
              title: '开源项目',
              children: const [
                AboutLinkTile(
                  icon: Icons.flutter_dash_rounded,
                  title: 'Flutter',
                  subtitle: '应用框架',
                  url: 'https://flutter.dev',
                ),
                AboutLinkTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'media-kit',
                  subtitle: '视频播放',
                  url: 'https://github.com/media-kit/media-kit',
                ),
                AboutLinkTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Anime4K',
                  subtitle: '实时超分辨率',
                  url: 'https://github.com/bloc97/Anime4K',
                ),
                AboutLinkTile(
                  icon: Icons.storage_rounded,
                  title: 'Hive CE',
                  subtitle: '本地存储',
                  url: 'https://github.com/IO-Design-Team/hive_ce',
                ),
                AboutLinkTile(
                  icon: Icons.favorite_outline_rounded,
                  title: 'Kazumi',
                  subtitle: '播放器框架来源（GPL-3.0）',
                  url: 'https://github.com/Predidit/Kazumi',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ContentSection.group(
              title: '许可',
              children: const [
                AboutLinkTile(
                  icon: Icons.description_outlined,
                  title: '开源许可',
                  subtitle: 'GPL-3.0 与上游声明',
                  url:
                      'https://github.com/Predidit/Kazumi/blob/main/LICENSE',
                ),
              ],
            ),
          ],
        ),
      );
}
