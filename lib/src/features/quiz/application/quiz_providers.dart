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

/// Refreshes widgets that display local question-bank state after a background
/// sync, import, or export-independent bank mutation.
final quizBankRevisionProvider = NotifierProvider<QuizBankRevision, int>(
  QuizBankRevision.new,
);

final class QuizBankRevision extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

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
