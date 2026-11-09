import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/about/about_page.dart';
import 'package:emoplay/pages/about/credits_page.dart';
import 'package:emoplay/pages/about/notice_page.dart';

final aboutModule = createModule(
  path: '/about',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const AboutPage(),
      )
      ..route('/credits', child: (context, state) => const CreditsPage())
      ..route('/notice', child: (context, state) => const NoticePage());
  },
);
