import 'package:bible_recite/src/features/plans/domain/plan_generator.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('balances ordered verses without duplicates across requested days', () {
    final units = List.generate(
      8,
      (index) => VerseUnit(
        translationId: 'cmn-cu89s',
        start: (
          canonId: CanonId.protestant66,
          osisBookId: 'JHN',
          chapter: 1,
          verse: index + 1,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: 'JHN',
          chapter: 1,
          verse: index + 1,
        ),
        text: '经文${'内容' * (index + 1)}',
        status: SourceTextStatus.present,
      ),
    );

    final tasks = const PlanGenerator().generate(units: units, days: 4);

    expect(tasks, hasLength(4));
    expect(tasks.expand((task) => task.units), orderedEquals(units));
    expect(tasks.every((task) => task.units.isNotEmpty), isTrue);
  });

  test('allows long plans without materializing empty daily tasks', () {
    expect(
      () => const PlanGenerator().generate(units: const [], days: 0),
      throwsArgumentError,
    );
    final units = List.generate(
      2,
      (index) => VerseUnit(
        translationId: 'cmn-cu89s',
        start: (
          canonId: CanonId.protestant66,
          osisBookId: 'JHN',
          chapter: 1,
          verse: index + 1,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: 'JHN',
          chapter: 1,
          verse: index + 1,
        ),
        text: '经文',
        status: SourceTextStatus.present,
      ),
    );
    final tasks = const PlanGenerator().generate(units: units, days: 3652425);
    expect(tasks, hasLength(2));
    expect(tasks.first.dayIndex, 0);
    expect(tasks.last.dayIndex, 3652424);
  });
}
