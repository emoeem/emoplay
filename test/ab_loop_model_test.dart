import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/pages/player/controller/ab_loop_model.dart';

// Pure half of the M3 施工件 C「A-B 循环」tests: the three-state machine
// (none → aSet → looping → none), its guards, and the mpv property-string
// parsing — no mpv handle involved. The live half (real libmpv driving the
// properties) lives in test/frame_step_live_test.dart.
void main() {
  group('PlayerAbLoopPhase.of', () {
    test('both marks unset → none', () {
      expect(PlayerAbLoopPhase.of(null, null), PlayerAbLoopPhase.none);
    });

    test('A only → aSet', () {
      expect(PlayerAbLoopPhase.of(10.0, null), PlayerAbLoopPhase.aSet);
    });

    test('A and B → looping', () {
      expect(PlayerAbLoopPhase.of(10.0, 20.0), PlayerAbLoopPhase.looping);
    });

    test('B without A is treated as none (B never leads)', () {
      expect(PlayerAbLoopPhase.of(null, 20.0), PlayerAbLoopPhase.none);
    });
  });

  group('applyAbLoopAction cycle (mpv ab-loop 惯例的 L 三态)', () {
    test('none + cycle marks A at the current position', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: null,
        positionB: null,
        position: 12.345,
      );
      expect(t.accepted, isTrue);
      expect(t.positionA, 12.345);
      expect(t.positionB, isNull);
      expect(t.phase, PlayerAbLoopPhase.aSet);
    });

    test('aSet + cycle marks B and arms the loop', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: 12.345,
        positionB: null,
        position: 30.0,
      );
      expect(t.accepted, isTrue);
      expect(t.positionA, 12.345);
      expect(t.positionB, 30.0);
      expect(t.phase, PlayerAbLoopPhase.looping);
    });

    test('looping + cycle clears both marks', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: 12.345,
        positionB: 30.0,
        position: 40.0,
      );
      expect(t.accepted, isTrue);
      expect(t.positionA, isNull);
      expect(t.positionB, isNull);
      expect(t.phase, PlayerAbLoopPhase.none);
    });

    test('cycle keeps position untouched on the clear step', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: 1.0,
        positionB: 2.0,
        position: 99.0,
      );
      expect(t.positionA, isNull);
      expect(t.positionB, isNull);
    });
  });

  group('applyAbLoopAction guards', () {
    test('markB before A is rejected (B 点必须晚于 A 点)', () {
      final t = applyAbLoopAction(
        AbLoopAction.markB,
        positionA: 30.0,
        positionB: null,
        position: 12.0,
      );
      expect(t.accepted, isFalse);
      expect(t.reason, 'B 点必须晚于 A 点');
      // Rejection keeps the previous state (still aSet, same A).
      expect(t.positionA, 30.0);
      expect(t.positionB, isNull);
      expect(t.phase, PlayerAbLoopPhase.aSet);
    });

    test('markB exactly at A is rejected (empty range)', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: 30.0,
        positionB: null,
        position: 30.0,
      );
      expect(t.accepted, isFalse);
      expect(t.reason, 'B 点必须晚于 A 点');
    });

    test('markB without A is rejected (请先标记 A 点)', () {
      final t = applyAbLoopAction(
        AbLoopAction.markB,
        positionA: null,
        positionB: null,
        position: 5.0,
      );
      expect(t.accepted, isFalse);
      expect(t.reason, '请先标记 A 点');
    });

    test('markA without a position is rejected', () {
      final t = applyAbLoopAction(
        AbLoopAction.markA,
        positionA: null,
        positionB: null,
        position: null,
      );
      expect(t.accepted, isFalse);
      expect(t.reason, '无法获取当前位置');
    });

    test('markA with NaN is rejected', () {
      final t = applyAbLoopAction(
        AbLoopAction.markA,
        positionA: null,
        positionB: null,
        position: double.nan,
      );
      expect(t.accepted, isFalse);
    });

    test('markA with a negative position is rejected', () {
      final t = applyAbLoopAction(
        AbLoopAction.markA,
        positionA: null,
        positionB: null,
        position: -1.0,
      );
      expect(t.accepted, isFalse);
    });

    test('re-marking A drops a stale B (restart the pair)', () {
      final t = applyAbLoopAction(
        AbLoopAction.markA,
        positionA: 10.0,
        positionB: 20.0,
        position: 5.0,
      );
      expect(t.accepted, isTrue);
      expect(t.positionA, 5.0);
      expect(t.positionB, isNull);
      expect(t.phase, PlayerAbLoopPhase.aSet);
    });

    test('explicit clear works from every phase', () {
      for (final (a, b) in [(null, null), (1.0, null), (1.0, 2.0)]) {
        final t = applyAbLoopAction(
          AbLoopAction.clear,
          positionA: a,
          positionB: b,
          position: 9.0,
        );
        expect(t.accepted, isTrue, reason: 'from A=$a B=$b');
        expect(t.positionA, isNull);
        expect(t.positionB, isNull);
      }
    });
  });

  group('parseMpvAbLoopPosition', () {
    test('no / empty → null', () {
      expect(parseMpvAbLoopPosition('no'), isNull);
      expect(parseMpvAbLoopPosition(''), isNull);
      expect(parseMpvAbLoopPosition('  '), isNull);
    });

    test('plain seconds (mpv echo format) parse', () {
      expect(parseMpvAbLoopPosition('12.345'), 12.345);
      expect(parseMpvAbLoopPosition('2.000000'), 2.0);
      expect(parseMpvAbLoopPosition('0.000000'), 0.0);
      expect(parseMpvAbLoopPosition('120'), 120.0);
    });

    test('mpv time grammar parses (M:SS.mmm / H:MM:SS.mmm)', () {
      expect(parseMpvAbLoopPosition('0:12.345'), closeTo(12.345, 1e-9));
      expect(parseMpvAbLoopPosition('1:02.500'), 62.5);
      expect(parseMpvAbLoopPosition('1:02:03.250'),
          closeTo(3723.25, 1e-9));
    });

    test('garbage and out-of-range values → null (display hides them)', () {
      expect(parseMpvAbLoopPosition('abc'), isNull);
      expect(parseMpvAbLoopPosition('1:2:3:4'), isNull);
      expect(parseMpvAbLoopPosition('-5'), isNull);
    });
  });

  group('formatAbLoopPosition', () {
    test('minutes range', () {
      expect(formatAbLoopPosition(0), '0:00.0');
      expect(formatAbLoopPosition(12.34), '0:12.3');
      expect(formatAbLoopPosition(62.5), '1:02.5');
    });

    test('rounds at the tenth boundary (59.96 → 1:00.0)', () {
      expect(formatAbLoopPosition(59.96), '1:00.0');
    });

    test('hours carry into H:MM:SS.d', () {
      expect(formatAbLoopPosition(3723.0), '1:02:03.0');
      expect(formatAbLoopPosition(3661.5), '1:01:01.5');
    });

    test('negative values clamp to zero', () {
      expect(formatAbLoopPosition(-3), '0:00.0');
    });
  });

  group('AbLoopCycleOutcome message (OSD 文案)', () {
    AbLoopCycleOutcome outcomeOf(AbLoopTransition t) => AbLoopCycleOutcome(
          accepted: t.accepted,
          phase: t.phase,
          positionA: t.positionA,
          positionB: t.positionB,
          reason: t.reason,
        );

    test('accepted steps describe the new state', () {
      expect(
        outcomeOf(applyAbLoopAction(AbLoopAction.cycle, positionA: null,
                positionB: null, position: 12.3)).message,
        contains('A 点'),
      );
      expect(
        outcomeOf(applyAbLoopAction(AbLoopAction.cycle, positionA: 12.0,
                positionB: null, position: 30.0)).message,
        contains('循环'),
      );
      expect(
        outcomeOf(applyAbLoopAction(AbLoopAction.clear, positionA: 12.0,
                positionB: 30.0)).message,
        'A-B 循环已清除',
      );
    });

    test('rejected steps surface the reason', () {
      final t = applyAbLoopAction(
        AbLoopAction.cycle,
        positionA: 30.0,
        positionB: null,
        position: 12.0,
      );
      expect(outcomeOf(t).message, 'B 点必须晚于 A 点');
    });
  });
}
