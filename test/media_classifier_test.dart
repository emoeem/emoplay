import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/media_classifier.dart';

/// Drop classification and drop->plan rules (1.x book §4). Pure logic: no
/// mpv, no GUI.
///
/// Case-for-case port of mpv-emo tests/test_media_classifier.cpp; the
/// assertion values are the behavioural contract and are copied verbatim.
/// The C++ slots write plain stub files in a QTemporaryDir (no ffmpeg
/// fixtures in that test — tests/fixtures/media/ belongs to the playback
/// tests), so the Dart port does the same in a per-test temp directory.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-classifier-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String filePath(String name) => '${tempDir.path}/$name';

  Future<void> writeFile(String name) async {
    final file = File(filePath(name));
    await file.writeAsString('x');
  }

  test('classifiesByExtension', () async {
    expect(MediaKind.video.kindName, 'video');

    for (final name in ['a.mp4', 'b.MKV', 'c.webm']) {
      await writeFile(name);
      final row = MediaClassifier.classify(filePath(name));
      expect(row.kind, MediaKind.video);
      expect(row.reason, isEmpty);
    }

    await writeFile('d.flac');
    expect(MediaClassifier.classify(filePath('d.flac')).kind, MediaKind.audio);

    await writeFile('e.srt');
    expect(
        MediaClassifier.classify(filePath('e.srt')).kind, MediaKind.subtitle);
  });

  test('missingAndUnreadableCarryReason', () {
    final missing = MediaClassifier.classify(filePath('nope.mp4'));
    expect(missing.kind, MediaKind.missing);
    expect(missing.reason, isNotEmpty);
  });

  test('foldersAreFolders', () {
    final row = MediaClassifier.classify(tempDir.path);
    expect(row.kind, MediaKind.folder);
    expect(row.reason, isEmpty);
  });

  test('unsupportedTypeIsRejectedWithReason', () async {
    await writeFile('readme.txt');
    final row = MediaClassifier.classify(filePath('readme.txt'));
    expect(row.kind, MediaKind.unknown);
    expect(row.reason, contains('txt'));
  });

  test('remoteUrlRules', () {
    final ok = MediaClassifier.classify('https://example.com/a.mp4');
    expect(ok.kind, MediaKind.remoteUrl);

    final bad = MediaClassifier.classify('https://example.com/page.html');
    expect(bad.kind, MediaKind.unknown);
    expect(bad.reason, isNotEmpty);
  });

  test('planPlayKeepsOrderAndReportsRejects', () async {
    final a = filePath('one.mp4');
    final b = filePath('two.mp3');
    final c = filePath('three.mkv');
    await writeFile('one.mp4');
    await writeFile('two.mp3');
    await writeFile('three.mkv');

    final plan = MediaClassifier.planDrop(
      [c, a, '/definitely/missing.mp4', b],
      false,
    );
    expect(plan.action, 'play');
    expect(plan.paths, [c, a, b]);
    expect(plan.rejected.length, 1);
  });

  test('planSubtitleNeedsMedia', () async {
    await writeFile('x.srt');
    final sub = filePath('x.srt');

    expect(MediaClassifier.planDrop([sub], true).action, 'subtitle');
    expect(MediaClassifier.planDrop([sub], false).action, 'needs-media');
  });

  test('planFolderAsks', () {
    final plan = MediaClassifier.planDrop([tempDir.path], false);
    expect(plan.action, 'folder');
    expect(plan.folders.length, 1);
  });

  test('planRejectsEverything', () async {
    await writeFile('notes.txt');
    final plan = MediaClassifier.planDrop([filePath('notes.txt')], true);
    expect(plan.action, 'reject');
    expect(plan.rejected.length, 1);
  });

  test('folderMediaCollectsBoundedDepth', () async {
    // The depth walk gets its own tree instead of counting the other cases'
    // files (1.x made the same split inside the shared QTemporaryDir).
    final root = Directory('${tempDir.path}/bounded');
    await Directory('${root.path}/sub/deep').create(recursive: true);
    for (final name in ['top.mkv', 'sub/b.mp4', 'sub/deep/c.flac']) {
      await File('${root.path}/$name').writeAsString('x');
    }
    await File('${root.path}/notes.txt').writeAsString('x');
    final tree = root.path;

    // maxDepth is the number of subdirectory levels below the root:
    // 0 = root only, 1 = root + sub/, 2 = root + sub/ + sub/deep/.
    expect(MediaClassifier.folderMedia(tree, maxDepth: 0).length, 1);
    expect(MediaClassifier.folderMedia(tree, maxDepth: 1).length, 2);
    expect(MediaClassifier.folderMedia(tree, maxDepth: 2).length, 3);

    // Nothing playable -> empty list, so the UI can say so.
    expect(MediaClassifier.folderMedia('${tree}x', maxDepth: 2), isEmpty);
  });
}
