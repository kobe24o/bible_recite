import '../domain/quiz_result.dart';
import '../domain/quiz_scope.dart';

final class QuizPracticeRequest {
  const QuizPracticeRequest({
    required this.scope,
    required this.questions,
    this.preparationNotice,
  });

  final QuizScope scope;
  final List<PendingQuizQuestion> questions;
  final String? preparationNotice;
}
