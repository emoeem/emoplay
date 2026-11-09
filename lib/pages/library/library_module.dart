import 'package:flutter_modular/flutter_modular.dart';
import 'package:emoplay/pages/library/library_page.dart';

final libraryModule = createModule(
  path: '/library',
  register: (c) {
    c.route('/', child: (context, state) => const LibraryPage());
  },
);
