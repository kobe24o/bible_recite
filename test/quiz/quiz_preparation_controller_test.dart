import 'dart:async';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_generation_service.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_preparation_controller.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
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
