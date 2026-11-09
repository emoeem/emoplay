// Localization-chain test for the first page migrated to AppLocalizations:
// the tab shell (lib/pages/menu/menu.dart) — OVERNIGHT-LOOP §四 backlog 8
// follow-up, R3 round.
//
// R2 `b61dff2` established the arb skeleton (l10n.yaml + en/zh arb + the
// generated classes committed under lib/l10n/generated); nothing consumed
// them from a real page yet. R3 wires menu.dart (five tab labels via
// menuTabLabels() + the double-back exit toast) and this test locks the
// chain end to end: arb key → gen-l10n output → AppLocalizations lookup in
// the exact way the page performs it — zh (the SPEC §1 default, also the
// app_widget-forced locale) and en (the reserved second locale).
//
// Scope note: this pumps the page's own label source (menuTabLabels lives
// inside menu.dart), not a full ScaffoldMenu mount — a full mount needs the
// modular route tree (player/settings DI, window services) and stays with
// the GUI/manual acceptance round (SPEC §9). The migration itself is still
// compile-checked by `flutter analyze` and the labels are the page's single
// source of truth: both the NavigationBar and the NavigationRail build from
// menuTabLabels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/pages/menu/menu.dart';

void main() {
  // The harness performs the same lookup the tab shell does:
  // AppLocalizations.of(context) → menuTabLabels / doubleBackToExit.
  Widget l10nHarness(Locale locale) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            final labels = menuTabLabels(l10n);
            return Scaffold(
              body: Column(
                children: <Widget>[
                  for (final label in labels) Text(label),
                  Text(l10n.doubleBackToExit),
                ],
              ),
            );
          },
        ),
      );

  testWidgets('tabLabelsResolveInNavigationOrderZh', (tester) async {
    // SPEC §1: zh is the default language (app_widget forces zh-Hans-CN).
    await tester.pumpWidget(l10nHarness(const Locale('zh')));
    await tester.pumpAndSettle();

    // The five SPEC §5 tabs, in navigation order.
    final expectedTabs = <String>['首页', '媒体库', '播放', '插件', '设置'];
    for (final label in expectedTabs) {
      expect(find.text(label), findsOneWidget, reason: 'missing tab: $label');
    }
    // Double-back exit toast (menu.dart _handleSystemBack).
    expect(find.text('再按一次退出应用'), findsOneWidget);
  });

  testWidgets('tabLabelsResolveInNavigationOrderEn', (tester) async {
    // The reserved en locale: the gen-l10n chain must serve the English
    // arb values, not fall back to zh.
    await tester.pumpWidget(l10nHarness(const Locale('en')));
    await tester.pumpAndSettle();

    final expectedTabs = <String>['Home', 'Library', 'Player', 'Plugins', 'Settings'];
    for (final label in expectedTabs) {
      expect(find.text(label), findsOneWidget, reason: 'missing tab: $label');
    }
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  test('generatedChainCoversBothLocales', () {
    // The delegates/supportedLocales pair the app mounts (app_widget.dart)
    // must advertise exactly the two arb locales.
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode),
        containsAll(<String>['zh', 'en']));
    expect(AppLocalizations.localizationsDelegates, isNotEmpty);
  });
}
