import 'package:bible_recite/src/features/devotion/application/devotion_reading_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pause excludes background duration and stop flushes active seconds',
    () async {
      var now = DateTime(2026, 10, 4, 9);
      final flushed = <int>[];
      final session = DevotionReadingSession(
        day: DateTime(2026, 10, 4),
        clock: () => now,
        onElapsed: (_, seconds) async => flushed.add(seconds),
      );

      session.start();
      now = now.add(const Duration(seconds: 40));
      await session.pause();
      now = now.add(const Duration(hours: 2));
      session.resume();
      now = now.add(const Duration(seconds: 21));
      await session.stop();

      expect(flushed, [61]);
    },
  );

  test(
    'duplicate pause, stop, and dispose calls do not duplicate a flush',
    () async {
      var now = DateTime(2026, 10, 4, 9);
      final flushed = <int>[];
      final session = DevotionReadingSession(
        day: DateTime(2026, 10, 4),
        clock: () => now,
        onElapsed: (_, seconds) async => flushed.add(seconds),
      );

      await session.pause();
      session.start();
      now = now.add(const Duration(seconds: 1));
      await session.pause();
      await session.pause();
      await session.stop();
      await session.stop();
      await session.dispose();
      await session.dispose();

      expect(flushed, [1]);
    },
  );

  test(
    'a day change stops without attributing elapsed time to tomorrow',
    () async {
      var now = DateTime(2026, 10, 4, 23, 59, 40);
      final flushed = <int>[];
      final session = DevotionReadingSession(
        day: DateTime(2026, 10, 4),
        clock: () => now,
        onElapsed: (_, seconds) async => flushed.add(seconds),
      );

      session.start();
      now = DateTime(2026, 10, 5, 0, 0, 10);
      await session.stop();

      expect(flushed, isEmpty);
    },
  );
}
