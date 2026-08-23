import 'package:bible_recite/src/features/plans/domain/plan_draft_builder.dart';
import 'package:bible_recite/src/features/plans/domain/plan_entry_splitter.dart';
import 'package:bible_recite/src/features/plans/presentation/plan_editor_dialog.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
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

  test(
    'rebases unfinished passages onto today after an edited plan saves',
    () async {
      final draft = PlanEditorDraft(
        title: '重排计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 2),
        passages: const [
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
      );
      final completed = PlanTask(
        id: 1,
        planId: 1,
        dayIndex: 0,
        dueDate: DateTime(2026, 8, 1),
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 16,
        completed: true,
      );

      final normalized = normalizeDraftForPendingWork(draft, [
        completed,
      ], now: DateTime(2026, 8, 5));
      final plan = await buildPlanFromDraft(
        _ScriptureFixture(),
        normalized,
        completedTasks: [completed],
        now: DateTime(2026, 8, 5),
      );

      expect(normalized.endDate, DateTime(2026, 8, 5));
      expect(
        plan.tasks.where((task) => task.startVerse == 17).single.dayIndex,
        4,
      );
    },
  );

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

  test(
    'creates one default entry with every selected passage as blocks',
    () async {
      final plan = await buildPlanFromDraft(
        _ScriptureFixture(),
        PlanEditorDraft(
          title: '多选一条',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          startChapter: 3,
          endChapter: 3,
          startDate: DateTime(2026, 8, 23),
          endDate: DateTime(2026, 8, 23),
          passages: const [
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
              startVerse: 18,
              endChapter: 3,
              endVerse: 18,
            ),
          ],
        ),
        now: DateTime(2026, 8, 23),
      );

      expect(plan.tasks, hasLength(1));
      expect(plan.tasks.single.dayIndex, 0);
      expect(
        plan.tasks.single
            .effectiveBlocks('JHN')
            .map((block) => block.startVerse),
        [16, 18],
      );
    },
  );

  test(
    'creates one entry per verse on consecutive days when requested',
    () async {
      final plan = await buildPlanFromDraft(
        _ScriptureFixture(),
        PlanEditorDraft(
          title: '按节背诵',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          startChapter: 3,
          endChapter: 3,
          startDate: DateTime(2026, 8, 23),
          endDate: DateTime(2026, 8, 23),
          splitStrategy: const PlanEntrySplitStrategy.byVerse(),
          passages: const [
            PlanPassageSelection(
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 17,
            ),
          ],
        ),
        now: DateTime(2026, 8, 23),
      );

      expect(plan.days, 2);
      expect(plan.tasks.map((task) => task.dayIndex), [0, 1]);
      expect(plan.tasks.map((task) => task.startVerse), [16, 17]);
    },
  );

  test('keeps every added passage in a book-specific default entry', () async {
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
      now: DateTime(2026, 7, 25),
    );

    expect(plan.tasks, hasLength(1));
    final blocks = plan.tasks.single.effectiveBlocks('GEN');
    expect(blocks.map((block) => block.bookId).toSet(), {'GEN', 'JHN'});
    expect(
      blocks.any((block) => block.bookId == 'JHN' && block.startVerse == 16),
      isTrue,
    );
    expect(
      blocks.any((block) => block.bookId == 'JHN' && block.endVerse == 17),
      isTrue,
    );
    expect(
      blocks.where((block) => block.bookId == 'JHN' && block.startVerse == 16),
      hasLength(1),
    );
  });

  test(
    'keeps passages together in the default entry despite a short schedule',
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

      expect(plan.tasks, hasLength(1));
      expect(plan.tasks.single.dayIndex, 0);
      expect(
        plan.tasks.single
            .effectiveBlocks('GEN')
            .where((block) => block.startVerse == 16)
            .single
            .endVerse,
        16,
      );
    },
  );

  test(
    'schedules a 9999-year-range plan without allocating every day',
    () async {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(9999, 12, 31);
      final plan = await buildPlanFromDraft(
        _ScriptureFixture(),
        PlanEditorDraft(
          title: '长期计划',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          startChapter: 3,
          endChapter: 3,
          startDate: start,
          endDate: end,
          passages: const [
            PlanPassageSelection(
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 17,
            ),
          ],
        ),
        now: start,
      );

      expect(plan.days, 1);
      expect(plan.tasks, hasLength(1));
      expect(plan.tasks.first.dayIndex, 0);
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
