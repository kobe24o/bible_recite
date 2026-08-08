import 'dart:convert';

import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const settings = QuizModelSettings(
    baseUrl: 'https://example.test/api/v4',
    model: 'GLM-4.7-Flash',
    apiKey: 'secret-key-value',
  );
  const verse = QuizGenerationVerse(
    reference: '约翰福音 3:16',
    text: '神爱世人',
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    chapter: 3,
    verse: 16,
  );

  test(
    'builds the request with bearer key, model and prompt requirements',
    () async {
      late http.Request captured;
      final client = QuizModelClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '[\n'
                        '  {"reference":"约翰福音 3:16","start":2,"end":4,'
                        '"length":2,"partOfSpeech":"名词","meaning":"世上的人"}\n'
                        ']',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final decoded = await client.generate(settings, [verse]);
      expect(
        captured.url.toString(),
        'https://example.test/api/v4/chat/completions',
      );
      expect(captured.headers['authorization'], 'Bearer secret-key-value');
      final body = jsonDecode(captured.body) as Map<String, Object?>;
      expect(body['model'], 'GLM-4.7-Flash');
      expect(body['thinking'], {'type': 'disabled'});
      final content = body['messages'] as List<Object?>;
      final system = (content[0] as Map<String, Object?>)['content'] as String;
      final user = (content[1] as Map<String, Object?>)['content'] as String;
      expect(system, contains('只返回一个 JSON 数组'));
      expect(system, contains('reference'));
      expect(system, contains('meaning'));
      expect(user, contains('经文语言版本'));
      expect(user, contains('约翰福音 3:16'));
      expect(captured.body, isNot(contains('secret-key-value')));
      expect(decoded, isA<List<Object?>>());
    },
  );

  test('rejects a blank API key before any network call', () async {
    var called = false;
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.generate(
        const QuizModelSettings(
          baseUrl: 'https://example.test',
          model: 'GLM-4.7-Flash',
          apiKey: '',
        ),
        [verse],
      ),
      throwsA(isA<QuizModelException>()),
    );
    expect(called, isFalse);
  });

  test('requests a strict quiz array schema from OpenRouter', () async {
    late http.Request captured;
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '[]'},
              },
            ],
          }),
          200,
        );
      }),
    );

    await client.generate(
      const QuizModelSettings(
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'google/gemini-2.5-flash-lite',
        apiKey: 'test-key',
      ),
      [verse],
    );

    final body = jsonDecode(captured.body) as Map<String, Object?>;
    final responseFormat = body['response_format'] as Map<String, Object?>;
    expect(responseFormat['type'], 'json_schema');
    final schema = responseFormat['json_schema'] as Map<String, Object?>;
    expect(schema['name'], 'quiz_questions');
    expect((schema['schema'] as Map<String, Object?>)['type'], 'array');
  });

  test('generic non-2xx errors never echo a key', () async {
    final client = QuizModelClient(
      httpClient: MockClient(
        (request) async => http.Response('bad gateway', 502),
      ),
    );
    try {
      await client.generate(settings, [verse]);
      fail('expected exception');
    } on QuizModelException catch (error) {
      expect(error.message, isNot(contains('secret-key-value')));
      expect(error.message, contains('HTTP 502'));
    }
  });

  test('connection test sends a no-scripture fixed request', () async {
    late http.Request captured;
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"choices":[]}', 200);
      }),
    );
    await client.testConnection(settings);
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    final content = (body['messages'] as List<Object?>)
        .map((m) => ((m as Map<String, Object?>)['content'] as String))
        .join('\n');
    expect(content, isNot(contains('约翰福音')));
    expect(content, isNot(contains('经文列表')));
  });

  test('throws when the response body has no JSON array', () async {
    final client = QuizModelClient(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '抱歉，我不能生成题目。'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      client.generate(settings, [verse]),
      throwsA(isA<QuizModelException>()),
    );
  });
}
