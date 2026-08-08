import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/statistics/presentation/recitation_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
  testWidgets('shows quiz accuracy alongside recitation accuracy on the map', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.saveQuizQuestions([
      const ValidatedQuizQuestion(
        translationId: 'eng-web',
        bookId: 'JHN',
        chapter: 3,
        verse: 16,
        start: 4,
        end: 8,
        word: 'God',
        partOfSpeech: 'noun',
        meaning: 'God',
        reference: 'John 3:16',
        verseText: 'For God so loved the world',
      ),
    ]);
    final question = (await repository.listPendingQuizQuestions(
      const QuizScope(
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 16,
      ),
    )).single;
    await repository.completeQuizQuestion(
      questionId: question.id,
      correct: true,
      answeredAt: DateTime.now(),
    );

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const RecitationMapScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('背诵准确率 0%'), findsWidgets);
    expect(find.textContaining('答题准确率 100%'), findsOneWidget);
  });
}
