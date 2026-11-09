import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/home/home_page.dart';

final homeModule = createModule(
  path: '/home',
  register: (c) {
    c.route('/', child: (context, state) => const HomePage());
  },
);
