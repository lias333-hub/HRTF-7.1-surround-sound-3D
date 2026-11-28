import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/throttle.dart';

const _d = Duration(milliseconds: 50);

void main() {
  testWidgets('many calls in one burst make one run, one delay after the first', (tester) async {
    var n = 0;
    final t = Throttle(_d, () => n++);
    for (var i = 0; i < 20; i++) {
      t.run();
    }
    expect(t.pending, isTrue);
    await tester.pump(const Duration(milliseconds: 49));
    expect(n, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(n, 1);
    expect(t.pending, isFalse);

    t.run(); // a new burst
    await tester.pump(const Duration(milliseconds: 60));
    expect(n, 2);
  });

  testWidgets('a long drag still runs every delay, not only when it stops', (tester) async {
    var n = 0;
    final t = Throttle(_d, () => n++);
    for (var i = 0; i < 10; i++) {
      t.run();
      await tester.pump(const Duration(milliseconds: 20)); // 200 ms of dragging in all
    }
    expect(n, 3); // fired at 50, 110 and 170 ms
    await tester.pump(_d);
    expect(n, 4); // the tail
    expect(t.pending, isFalse);
  });

  testWidgets('flush runs a pending run now, once, and does nothing when nothing is pending', (tester) async {
    var n = 0;
    final t = Throttle(_d, () => n++);
    t.flush();
    expect(n, 0);
    t.run();
    t.flush();
    expect(n, 1);
    expect(t.pending, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(n, 1); // the cancelled timer does not fire a second time
  });

  testWidgets('cancel forgets the pending run', (tester) async {
    var n = 0;
    final t = Throttle(_d, () => n++);
    t.run();
    t.cancel();
    expect(t.pending, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(n, 0);
  });

  testWidgets('the action reads the latest value itself, so dropped calls lose nothing', (tester) async {
    var value = 0;
    final seen = <int>[];
    final t = Throttle(_d, () => seen.add(value));
    for (final v in [1, 2, 3, 4, 5]) {
      value = v;
      t.run();
    }
    await tester.pump(_d);
    expect(seen, [5]);
  });
}
