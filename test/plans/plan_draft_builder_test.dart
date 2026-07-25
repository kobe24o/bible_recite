import 'package:bible_recite/src/features/plans/domain/plan_draft_builder.dart';
import 'package:bible_recite/src/features/plans/presentation/plan_editor_dialog.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a user-shortened end date when pending work fits it', () {
    final draft = PlanEditorDraft(
      title: '缩短日期',
      translationId: 'cmn-cu89s',
      bookId: 'JHN',
      startChapter: 3,
      endChapter: 3,
      startDate: DateTime(2026, 7, 25),
      endDate: DateTime(2026, 7, 26),
    );

    final normalized = normalizeDraftForPendingWork(
      draft,
      const [],
      now: DateTime(2026, 7, 25),
    );

    expect(normalized.endDate, DateTime(2026, 7, 26));
  });

  test('never splits one verse across multiple days', () async {
    final plan = await buildPlanFromDraft(
      _ScriptureFixture(),
      PlanEditorDraft(
        title: '单节计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 7, 25),
        endDate: DateTime(2026, 7, 30),
        passages: const [
          PlanPassageSelection(
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
        ],
      ),
      now: DateTime(2026, 7, 25),
    );

    expect(plan.tasks, hasLength(1));
    expect(plan.tasks.single.startVerse, 16);
    expect(plan.tasks.single.endVerse, 16);
  });

  test('keeps every added passage in a book-specific scheduled task', () async {
    final plan = await buildPlanFromDraft(
      _ScriptureFixture(),
      PlanEditorDraft(
        title: '跨卷计划',
        translationId: 'cmn-cu89s',
        bookId: 'GEN',
        startChapter: 1,
        endChapter: 1,
        startDate: DateTime(2026, 7, 25),
        endDate: DateTime(2026, 7, 28),
        passages: const [
          PlanPassageSelection(
            bookId: 'GEN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 2,
          ),
          PlanPassageSelection(
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 17,
          ),
        ],
      ),
    );

    expect(plan.tasks, hasLength(4));
    expect(plan.tasks.map((task) => task.bookId).toSet(), {'GEN', 'JHN'});
    expect(
      plan.tasks.any((task) => task.bookId == 'JHN' && task.startVerse == 16),
      isTrue,
    );
    expect(
      plan.tasks.any((task) => task.bookId == 'JHN' && task.endVerse == 17),
      isTrue,
    );
    expect(
      plan.tasks.where((task) => task.bookId == 'JHN' && task.startVerse == 16),
      hasLength(1),
    );
  });

  test(
    'combines passages on shortened days without splitting verses',
    () async {
      final plan = await buildPlanFromDraft(
        _ScriptureFixture(),
        PlanEditorDraft(
          title: '压缩计划',
          translationId: 'cmn-cu89s',
          bookId: 'GEN',
          startChapter: 1,
          endChapter: 1,
          startDate: DateTime(2026, 7, 25),
          endDate: DateTime(2026, 7, 26),
          passages: const [
            PlanPassageSelection(
              bookId: 'GEN',
              startChapter: 1,
              startVerse: 1,
              endChapter: 1,
              endVerse: 1,
            ),
            PlanPassageSelection(
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 16,
            ),
            PlanPassageSelection(
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 17,
              endChapter: 3,
              endVerse: 17,
            ),
          ],
        ),
        now: DateTime(2026, 7, 25),
      );

      expect(plan.tasks, hasLength(3));
      expect(plan.tasks.map((task) => task.dayIndex).toSet(), hasLength(2));
      final taskCountsByDay = <int, int>{};
      for (final task in plan.tasks) {
        taskCountsByDay.update(
          task.dayIndex,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      expect(taskCountsByDay.values, contains(greaterThan(1)));
      expect(
        plan.tasks.where((task) => task.startVerse == 16).single.endVerse,
        16,
      );
    },
  );
}

final class _ScriptureFixture implements ScriptureRepository {
  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async =>
      Passage(
        translationId: translationId,
        range: range,
        units: [
          for (var verse = range.start.verse; verse <= range.end.verse; verse++)
            VerseUnit(
              translationId: translationId,
              start: (
                canonId: CanonId.protestant66,
                osisBookId: range.start.osisBookId,
                chapter: range.start.chapter,
                verse: verse,
              ),
              end: (
                canonId: CanonId.protestant66,
                osisBookId: range.start.osisBookId,
                chapter: range.start.chapter,
                verse: verse,
              ),
              text: '经文$verse',
              status: SourceTextStatus.present,
            ),
        ],
      );

  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String osisBookId,
    int chapter,
  ) => throw UnimplementedError();

  @override
  Future<TranslationInfo> getTranslation(String id) =>
      throw UnimplementedError();

  @override
  Future<List<TranslationInfo>> listTranslations() =>
      throw UnimplementedError();

  @override
  Future<List<BibleBook>> listBooks(String translationId, CanonId canonId) =>
      throw UnimplementedError();

  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) => throw UnimplementedError();

  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) => throw UnimplementedError();
}
