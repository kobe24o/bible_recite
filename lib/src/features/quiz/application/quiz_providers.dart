import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/application/plan_providers.dart';
import '../../scripture/application/scripture_providers.dart';
import '../data/quiz_bank_feed_client.dart';
import '../data/quiz_model_client.dart';
import 'quiz_generation_service.dart';

final quizModelClientProvider = Provider<QuizModelClient>(
  (ref) => QuizModelClient(),
);

final quizBankFeedClientProvider = Provider<QuizBankFeedClient>(
  (ref) => QuizBankFeedClient(),
);

final quizGenerationServiceProvider = FutureProvider<QuizGenerationService>((
  ref,
) async {
  final repository = await ref.watch(planRepositoryProvider.future);
  final scripture = await ref.watch(scriptureRepositoryProvider.future);
  return QuizGenerationService(
    repository: repository,
    scripture: scripture,
    client: ref.watch(quizModelClientProvider),
  );
});
