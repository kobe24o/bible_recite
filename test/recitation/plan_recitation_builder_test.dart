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
    'keeps a selected entry isolated from later scheduled entries',
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

      expect(request!.quizScopes, hasLength(1));
      expect(request.quizScopes.first.startChapter, 3);
      expect(request.quizScopes.first.startVerse, 16);
      expect(request.quizScopes.first.endChapter, 3);
      expect(request.quizScopes.first.endVerse, 18);
      expect(request.next, isNull);
    },
  );

  test(
    'does not fill gaps or drop another book from a plan quiz scope',
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
        endVerse: 16,
        completed: false,
        blocks: const [
          PlanTaskBlock(
            id: 1,
            taskId: 1,
            sortOrder: 0,
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
          PlanTaskBlock(
            id: 2,
            taskId: 1,
            sortOrder: 1,
            bookId: 'JHN',
            startChapter: 5,
            startVerse: 2,
            endChapter: 5,
            endVerse: 2,
          ),
          PlanTaskBlock(
            id: 3,
            taskId: 1,
            sortOrder: 2,
            bookId: 'EXO',
            startChapter: 1,
            startVerse: 15,
            endChapter: 1,
            endVerse: 15,
          ),
        ],
      );
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

  test('Today quiz scopes contain only the selected task passage', () async {
    final selected = PlanTask(
      id: 1,
      planId: 1,
      dayIndex: 0,
      dueDate: DateTime(2026, 8, 11),
      bookId: 'GEN',
      startChapter: 11,
      startVerse: 6,
      endChapter: 12,
      endVerse: 7,
      completed: false,
    );
    final later = PlanTask(
      id: 2,
      planId: 1,
      dayIndex: 1,
      dueDate: DateTime(2026, 8, 12),
      bookId: 'GEN',
      startChapter: 50,
      startVerse: 1,
      endChapter: 50,
      endVerse: 26,
      completed: false,
    );
    final plan = MemorizationPlan(
      id: 1,
      title: '整卷计划',
      translationId: 'cmn-cu89s',
      bookId: 'GEN',
      startChapter: 1,
      endChapter: 50,
      days: 2,
      startDate: DateTime(2026, 8, 11),
      endDate: DateTime(2026, 8, 12),
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
      tasks: [selected, later],
      selected: selected,
      todayQuizEntry: true,
    );

    expect(request, isNotNull);
    expect(request!.quizScopes, hasLength(1));
    final scope = request.quizScopes.single;
    expect(scope.bookId, 'GEN');
    expect(scope.startChapter, 11);
    expect(scope.startVerse, 6);
    expect(scope.endChapter, 12);
    expect(scope.endVerse, 7);
  });

  test(
    'recites only the selected entry blocks and completes after its last block',
    () async {
      final selected = PlanTask(
        id: 1,
        planId: 1,
        dayIndex: 0,
        dueDate: DateTime(2026, 8, 11),
        bookId: 'JHN',
        startChapter: 1,
        startVerse: 1,
        endChapter: 1,
        endVerse: 1,
        completed: false,
        blocks: const [
          PlanTaskBlock(
            id: 11,
            taskId: 1,
            sortOrder: 0,
            bookId: 'JHN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 2,
          ),
          PlanTaskBlock(
            id: 12,
            taskId: 1,
            sortOrder: 1,
            bookId: 'JHN',
            startChapter: 1,
            startVerse: 5,
            endChapter: 1,
            endVerse: 6,
          ),
        ],
      );
      final later = _task(id: 2, day: 1, book: 'JHN', chapter: 2, verse: 1);
      final plan = MemorizationPlan(
        id: 1,
        title: '组合条目',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 2,
        days: 2,
        startDate: DateTime(2026, 8, 11),
        endDate: DateTime(2026, 8, 12),
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
        tasks: [selected, later],
        selected: selected,
        todayQuizEntry: true,
      );

      expect(request!.units.single.start.verse, 1);
      expect(request.planTaskId, isNull);
      expect(request.next!.units.single.start.verse, 5);
      expect(request.next!.planTaskId, 1);
      expect(request.next!.next, isNull);
      expect(request.quizScopes.map((scope) => scope.startVerse).toList(), [
        1,
        5,
      ]);
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
