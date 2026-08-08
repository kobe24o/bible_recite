import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/recitation/application/plan_recitation_builder.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a recitation request for a completed selected task', () async {
    final task = PlanTask(
      id: 1,
      planId: 1,
      dayIndex: 0,
      dueDate: DateTime(2026, 7, 30),
      bookId: 'JHN',
      startChapter: 3,
      startVerse: 16,
      endChapter: 3,
      endVerse: 16,
      completed: true,
    );
    final plan = MemorizationPlan(
      id: 1,
      title: '计划',
      translationId: 'eng-web',
      bookId: 'JHN',
      startChapter: 3,
      endChapter: 3,
      days: 1,
      startDate: DateTime(2026, 7, 30),
      endDate: DateTime(2026, 7, 30),
      totalTasks: 1,
      completedTasks: 1,
      sourceKind: PlanSourceKind.local,
      sourceUrl: null,
      externalId: null,
      revision: 0,
      contentLocked: false,
    );

    final request = await buildPlanRecitationRequest(
      scripture: _PassageRepository(),
      plan: plan,
      tasks: [task],
      selected: task,
    );

    expect(request, isNotNull);
    expect(request!.planTaskId, 1);
  });

  test(
    'attaches the exact full-plan quiz scope to the selected request',
    () async {
      final first = PlanTask(
        id: 1,
        planId: 1,
        dayIndex: 0,
        dueDate: DateTime(2026, 7, 30),
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 18,
        completed: false,
      );
      final second = PlanTask(
        id: 2,
        planId: 1,
        dayIndex: 1,
        dueDate: DateTime(2026, 7, 31),
        bookId: 'JHN',
        startChapter: 4,
        startVerse: 1,
        endChapter: 4,
        endVerse: 3,
        completed: false,
      );
      final plan = MemorizationPlan(
        id: 1,
        title: '计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 4,
        days: 2,
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 7, 31),
        totalTasks: 2,
        completedTasks: 0,
        sourceKind: PlanSourceKind.local,
        sourceUrl: null,
        externalId: null,
        revision: 0,
        contentLocked: false,
      );

      final request = await buildPlanRecitationRequest(
        scripture: _PassageRepository(),
        plan: plan,
        tasks: [first, second],
        selected: first,
      );

      expect(request!.quizScope, isNotNull);
      expect(request.quizScope!.startChapter, 3);
      expect(request.quizScope!.startVerse, 16);
      expect(request.quizScope!.endChapter, 4);
      expect(request.quizScope!.endVerse, 3);
    },
  );
}

class _PassageRepository implements ScriptureRepository {
  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async =>
      Passage(
        translationId: translationId,
        range: range,
        units: [
          VerseUnit(
            translationId: translationId,
            start: range.start,
            end: range.end,
            text: '经文',
            status: SourceTextStatus.present,
          ),
        ],
      );
  @override
  Future<List<VerseUnit>> getChapter(String a, String b, int c) =>
      throw UnimplementedError();
  @override
  Future<TranslationInfo> getTranslation(String a) =>
      throw UnimplementedError();
  @override
  Future<List<TranslationInfo>> listTranslations() =>
      throw UnimplementedError();
  @override
  Future<List<BibleBook>> listBooks(String a, CanonId b) =>
      throw UnimplementedError();
  @override
  Future<SelectedPassage> getSelection(String a, PassageSelection b) =>
      throw UnimplementedError();
  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange a,
    String b,
  ) => throw UnimplementedError();
}
