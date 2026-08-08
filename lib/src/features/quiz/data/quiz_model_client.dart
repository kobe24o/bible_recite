import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/quiz_models.dart';
import '../domain/quiz_model_settings.dart';

/// Friendly error whose message never includes the API key.
final class QuizModelException implements Exception {
  const QuizModelException(this.message);
  final String message;

  @override
  String toString() => 'QuizModelException: $message';
}

typedef QuizHttpClient = http.Client;

final class QuizModelClient {
  QuizModelClient({
    QuizHttpClient? httpClient,
    this.timeout = const Duration(seconds: 40),
    this.maxResponseBytes = 1024 * 1024,
  }) : _httpClient = httpClient ?? http.Client();

  final QuizHttpClient _httpClient;
  final Duration timeout;
  final int maxResponseBytes;

  /// Sends exactly one non-streaming chat completion request containing the
  /// scripture verses, and decodes the raw JSON (untrusted) for the caller.
  Future<Object> generate(
    QuizModelSettings settings,
    List<QuizGenerationVerse> verses,
  ) async {
    if (!settings.isConfigured) {
      throw const QuizModelException('尚未配置答题模型');
    }
    if (settings.apiKey.isEmpty) {
      throw const QuizModelException('尚未填写答题模型 API Key');
    }
    if (verses.isEmpty) {
      throw const QuizModelException('没有可生成题目的经文');
    }
    final requestBody = <String, Object?>{
      'model': settings.model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt()},
        {'role': 'user', 'content': _userPrompt(verses)},
      ],
      'temperature': 0.2,
      'max_tokens': 4096,
      // The page consumes only message.content.  Explicitly disabling
      // provider-side thinking prevents the response budget being spent in
      // reasoning_content while content is empty or incomplete.
      'thinking': {'type': 'disabled'},
    };
    if (_isOpenRouter(settings.baseUrl)) {
      requestBody['response_format'] = _quizResponseFormat();
    }
    final body = jsonEncode(requestBody);
    final uri = _chatUri(settings.baseUrl);
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer ${settings.apiKey}',
        'accept': 'application/json',
      })
      ..body = body;
    try {
      final response = await _httpClient
          .send(request)
          .timeout(timeout)
          .then((streamed) => http.Response.fromStream(streamed))
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuizModelException('答题模型服务返回 HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > maxResponseBytes) {
        throw const QuizModelException('答题模型响应过大');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final choices = switch (decoded) {
        {'choices': List<Object?> choices} => choices,
        _ => throw const QuizModelException('答题模型响应缺少 choices'),
      };
      if (choices.isEmpty) {
        throw const QuizModelException('答题模型没有返回内容');
      }
      final first = choices.first;
      final content = first is Map<String, Object?>
          ? first['message'] is Map<String, Object?>
                ? (first['message'] as Map<String, Object?>)['content']
                : null
          : null;
      if (content is! String || content.isEmpty) {
        throw const QuizModelException('答题模型没有返回文本');
      }
      final start = content.indexOf('[');
      final end = content.lastIndexOf(']');
      if (start < 0 || end <= start) {
        throw const QuizModelException('答题模型没有返回 JSON 数组');
      }
      return jsonDecode(content.substring(start, end + 1));
    } on QuizModelException {
      rethrow;
    } on Object catch (error) {
      throw QuizModelException('无法连接答题模型：$error');
    }
  }

  /// Sends a small fixed JSON request with no scripture to verify the
  /// configured endpoint and key work.  Throws [QuizModelException] on any
  /// failure or non-2xx response.
  Future<void> testConnection(QuizModelSettings settings) async {
    if (!settings.isConfigured) {
      throw const QuizModelException('尚未配置答题模型');
    }
    if (settings.apiKey.isEmpty) {
      throw const QuizModelException('尚未填写答题模型 API Key');
    }
    final body = jsonEncode({
      'model': settings.model,
      'messages': [
        {'role': 'user', 'content': '只返回 JSON 数组：[]'},
      ],
      'max_tokens': 8,
    });
    final request = http.Request('POST', _chatUri(settings.baseUrl))
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer ${settings.apiKey}',
        'accept': 'application/json',
      })
      ..body = body;
    try {
      final response = await _httpClient
          .send(request)
          .timeout(timeout)
          .then((streamed) => http.Response.fromStream(streamed))
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuizModelException('答题模型服务返回 HTTP ${response.statusCode}');
      }
    } on QuizModelException {
      rethrow;
    } on Object catch (error) {
      throw QuizModelException('无法连接答题模型：$error');
    }
  }

  static Uri _chatUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized/chat/completions');
  }

  static bool _isOpenRouter(String baseUrl) =>
      Uri.tryParse(baseUrl)?.host.toLowerCase() == 'openrouter.ai';

  static Map<String, Object?> _quizResponseFormat() => {
    'type': 'json_schema',
    'json_schema': {
      'name': 'quiz_questions',
      'strict': true,
      'schema': {
        'type': 'array',
        'minItems': 1,
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'reference',
            'start',
            'end',
            'length',
            'partOfSpeech',
            'meaning',
          ],
          'properties': {
            'reference': {'type': 'string'},
            'start': {'type': 'integer'},
            'end': {'type': 'integer'},
            'length': {'type': 'integer'},
            'partOfSpeech': {'type': 'string'},
            'meaning': {'type': 'string'},
          },
        },
      },
    },
  };

  /// The system prompt.  The only caller-configurable values are the
  /// translation/language and verse reference, which come from the input
  /// payload rather than being embedded as separate configuration.
  static String _systemPrompt() => '''
你是一位严格的圣经经文出题助手。根据用户提供的每节经文，挑选语义丰富、可朗读的词作为隐藏词，用于“听词填空”练习。
要求：
1. 只返回一个 JSON 数组，不要输出任何其他文字、解释或前后缀。
2. 数组元素字段固定为：reference、start、end、length、partOfSpeech、meaning。
3. reference 必须一字不差地来自输入；start 和 end 是该节原文的 UTF-16 下标（含 start、不含 end），length 等于 end - start。
4. 只选择词语或词组，不要选择：连接词、介词、助词、语气词、叹词、标点、数字或没有完整语义的碎片。选择语义丰富、适合朗读回答的实词（名词、动词、形容词等）。
5. meaning 用中文给出简短的字面解释，1-10 字，不要解释词语在文中的引申义之外的内容，不要给出读音。
6. 同一节不要重复选择相同位置或相同词。
只输出 JSON。''';

  static String _userPrompt(List<QuizGenerationVerse> verses) {
    final rendered = <String>[];
    String? currentLanguage;
    for (final verse in verses) {
      currentLanguage ??= verse.translationId;
      rendered.add('${verse.reference}：${verse.text}');
    }
    final header = StringBuffer()
      ..writeln('经文语言版本：$currentLanguage')
      ..writeln('请逐节最多各生成一题；只返回 JSON 数组。')
      ..writeln('经文列表：');
    return '$header${rendered.join('\n')}';
  }
}
