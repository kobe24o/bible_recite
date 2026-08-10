import 'dart:async';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_generation_service.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_preparation_controller.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
  test('uses cached unanswered questions when generation fails', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    const scope = QuizScope(
      translationId: 'eng-web',
      bookId: 'JHN',
      startChapter: 3,
      startVerse: 16,
      endChapter: 3,
      endVerse: 16,
    );
    await repository.saveQuizQuestions(const [
      ValidatedQuizQuestion(
        reference: '3:16',
        translationId: 'eng-web',
        bookId: 'JHN',
        chapter: 3,
        verse: 16,
        start: 0,
        end: 3,
        word: 'For',
        partOfSpeech: 'noun',
        meaning: 'a test word',
        verseText: 'For God so loved the world',
      ),
    ]);
    final controller = QuizPreparationController(
      scope: scope,
      serviceLoader: () async => QuizGenerationService(
        repository: repository,
        scripture: FakeRepositoryForPassage(),
        client: QuizModelClient(),
        settingsLoader: () async => const QuizModelSettings(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: '',
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.prepare();

    expect(controller.phase, QuizPreparationPhase.ready);
    expect(controller.questions, hasLength(1));
  });

  testWidgets('cancelling a started preparation ignores its late result', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final service = Completer<QuizGenerationService>();
    final controller = QuizPreparationController(
      scope: const QuizScope(
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 16,
      ),
      immediate: true,
      serviceLoader: () => service.future,
    );
    addTearDown(controller.dispose);

    controller.arm();
    await tester.pump();
    expect(controller.phase, QuizPreparationPhase.preparing);

    controller.cancel();
    service.complete(
      QuizGenerationService(
        repository: repository,
        scripture: FakeRepositoryForPassage(),
        client: QuizModelClient(),
        settingsLoader: () async => const QuizModelSettings(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.phase, QuizPreparationPhase.idle);
    expect(controller.error, isNull);
  });
}
