import 'package:emoplay/pages/player/controller/pending_resume_seek.dart';
import 'package:emoplay/pages/player/player_seek_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingResumeSeek (SPEC §4.4, mpv-emo PlaybackController port)', () {
    test('armed startAt is consumed exactly once', () {
      final pending = PendingResumeSeek();
      expect(pending.hasPending, isFalse);
      expect(pending.consume(), isNull);

      pending.arm(42.5);
      expect(pending.hasPending, isTrue);
      expect(pending.consume(), 42.5);
      // 一次性消费：后续 file-loaded 不再 seek，播放列表后续文件从头播。
      expect(pending.hasPending, isFalse);
      expect(pending.consume(), isNull);
    });

    test('startAt <= 0 does not arm (1.x openAt sentinel -1)', () {
      final pending = PendingResumeSeek();
      pending.arm(0);
      expect(pending.hasPending, isFalse);
      pending.arm(-3);
      expect(pending.hasPending, isFalse);
      pending.arm(0.5);
      pending.arm(0);
      // 重复 openAt：后一次覆盖前一次（含清空）。
      expect(pending.hasPending, isFalse);
    });

    test('a later arm replaces the previous value', () {
      final pending = PendingResumeSeek();
      pending.arm(10);
      pending.arm(30);
      expect(pending.consume(), 30);
    });

    test('clear disarms without consuming', () {
      final pending = PendingResumeSeek();
      pending.arm(15);
      pending.clear();
      expect(pending.hasPending, isFalse);
      expect(pending.consume(), isNull);
    });
  });

  group('playerDoubleTapZoneFor (PiliPlus view.dart onDoubleTapDownMobile)',
      () {
    const width = 800.0;
    test('left quarter seeks backward', () {
      expect(playerDoubleTapZoneFor(0, width), PlayerDoubleTapZone.backward);
      expect(playerDoubleTapZoneFor(199.9, width), PlayerDoubleTapZone.backward);
    });

    test('middle half toggles playback', () {
      expect(playerDoubleTapZoneFor(200, width), PlayerDoubleTapZone.center);
      expect(playerDoubleTapZoneFor(400, width), PlayerDoubleTapZone.center);
      expect(playerDoubleTapZoneFor(599.9, width), PlayerDoubleTapZone.center);
    });

    test('right quarter seeks forward', () {
      expect(playerDoubleTapZoneFor(600, width), PlayerDoubleTapZone.forward);
      expect(playerDoubleTapZoneFor(800, width), PlayerDoubleTapZone.forward);
    });
  });
}
