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
    'carries every exact plan task range through to the final request',
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

      expect(request!.quizScopes, hasLength(2));
      expect(request.quizScopes.first.startChapter, 3);
      expect(request.quizScopes.first.startVerse, 16);
      expect(request.quizScopes.first.endChapter, 3);
      expect(request.quizScopes.first.endVerse, 18);
      expect(request.quizScopes.last.startChapter, 4);
      expect(request.quizScopes.last.startVerse, 1);
      expect(request.quizScopes.last.endChapter, 4);
      expect(request.quizScopes.last.endVerse, 3);
      expect(request.next, isNotNull);
      expect(request.next!.quizScopes, request.quizScopes);
    },
  );

  test(
    'does not fill gaps or drop another book from a plan quiz scope',
    () async {
      final first = _task(id: 1, day: 0, book: 'JHN', chapter: 3, verse: 16);
      final later = _task(id: 2, day: 1, book: 'JHN', chapter: 5, verse: 2);
      final otherBook = _task(
        id: 3,
        day: 2,
        book: 'EXO',
        chapter: 1,
        verse: 15,
      );
      final plan = MemorizationPlan(
        id: 1,
        title: '离散经文计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 5,
        days: 3,
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 8, 1),
        totalTasks: 3,
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
        tasks: [first, later, otherBook],
        selected: first,
      );

      expect(
        request!.quizScopes
            .map(
              (scope) =>
                  '${scope.bookId}:${scope.startChapter}:${scope.startVerse}',
            )
            .toList(),
        ['JHN:3:16', 'JHN:5:2', 'EXO:1:15'],
      );
    },
  );
}

PlanTask _task({
  required int id,
  required int day,
  required String book,
  required int chapter,
  required int verse,
}) => PlanTask(
  id: id,
  planId: 1,
  dayIndex: day,
  dueDate: DateTime(2026, 7, 30 + day),
  bookId: book,
  startChapter: chapter,
  startVerse: verse,
  endChapter: chapter,
  endVerse: verse,
  completed: false,
);

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
