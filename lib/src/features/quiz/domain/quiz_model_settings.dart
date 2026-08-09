/// Persistent settings for the OpenAI-compatible quiz generation model.
///
/// The default base URL and model name belong to Zhipu's compatible
/// endpoint.  The API key defaults to empty and is never written into
/// source code, logs, exception text, test fixtures, or exports.
final class QuizModelSettings {
  const QuizModelSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  static const defaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';

  static const defaultModel = 'glm-4.7-flash';

  static const defaultSettings = QuizModelSettings(
    baseUrl: defaultBaseUrl,
    model: defaultModel,
    apiKey: '',
  );

  final String baseUrl;
  final String model;
  final String apiKey;

  List<String> get missingConfigurationFields => [
    if (baseUrl.trim().isEmpty) '服务地址',
    if (model.trim().isEmpty) '模型 ID',
    if (apiKey.trim().isEmpty) 'API Key',
  ];

  bool get isConfigured => missingConfigurationFields.isEmpty;

  String get missingConfigurationMessage =>
      '缺少答题模型配置：${missingConfigurationFields.join('、')}';

  QuizModelSettings copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) => QuizModelSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
  );
}
