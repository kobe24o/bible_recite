/// Where a quiz question came from. This is persisted so later bank
/// cleaning can distinguish shared questions from model-generated ones.
enum QuizQuestionSource { local, cloud, model }

extension QuizQuestionSourcePresentation on QuizQuestionSource {
  String get storageValue => switch (this) {
    QuizQuestionSource.local => 'local',
    QuizQuestionSource.cloud => 'cloud',
    QuizQuestionSource.model => 'model',
  };

  String get labelZh => switch (this) {
    QuizQuestionSource.local => '本地题库',
    QuizQuestionSource.cloud => '云端题库',
    QuizQuestionSource.model => '大模型生成',
  };

  String get labelEn => switch (this) {
    QuizQuestionSource.local => 'Local bank',
    QuizQuestionSource.cloud => 'Cloud bank',
    QuizQuestionSource.model => 'Model-generated',
  };

  static QuizQuestionSource fromStorage(Object? value) => switch (value) {
    'cloud' => QuizQuestionSource.cloud,
    'model' => QuizQuestionSource.model,
    _ => QuizQuestionSource.local,
  };
}
