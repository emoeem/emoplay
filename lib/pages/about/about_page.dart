import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/widget/content_section.dart';
import 'package:emoplay/pages/about/about_widgets.dart';
import 'package:emoplay/utils/constants.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('关于'),
        body: AboutContent(
          children: [
            _ProjectHeader(),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final sections = [
                ContentSection.group(
                  title: '项目',
                  children: const [
                    AboutLinkTile.route(
                      icon: Icons.favorite_outline_rounded,
                      title: '致谢',
                      route: '/settings/about/credits',
                    ),
                    // 上游声明（SPEC §8）：Kazumi/PiliPlus/Anime4K/1.x 的
                    // 版权与重授权声明，全文来自仓库根目录 NOTICE.md。
                    AboutLinkTile.route(
                      icon: Icons.perm_contact_cal_outlined,
                      title: '上游声明（NOTICE）',
                      route: '/settings/about/notice',
                    ),
                    AboutLinkTile(
                      icon: Icons.balance_rounded,
                      title: 'GPL-3.0 许可证',
                      url:
                          'https://github.com/Predidit/Kazumi/blob/main/LICENSE',
                    ),
                    AboutLinkTile.route(
                      icon: Icons.description_outlined,
                      title: '第三方许可证',
                      route: '/settings/about/license',
                    ),
                  ],
                ),
              ];
              if (constraints.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(14) < 21) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sections[0]),
                  ],
                );
              }
              return Column(children: [sections[0]]);
            }),
          ],
        ),
      );
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              appName,
              style: theme.textTheme.displayMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            appVersion,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '本地媒体播放器',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
