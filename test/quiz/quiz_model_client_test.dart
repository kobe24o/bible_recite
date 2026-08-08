import 'dart:async';
import 'dart:convert';

import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_question_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const zhipuApiKey = String.fromEnvironment('ZHIPU_API_KEY');
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
      expect(system, contains('恰好一题'));
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
    final schemaBody = schema['schema'] as Map<String, Object?>;
    expect(schemaBody['type'], 'array');
    final item = schemaBody['items'] as Map<String, Object?>;
    expect(item['required'], contains('word'));
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

  test('explains Zhipu rate limiting without exposing the key', () async {
    final client = QuizModelClient(
      httpClient: MockClient((request) async => http.Response('', 429)),
    );
    await expectLater(
      client.generate(settings, [verse]),
      throwsA(
        isA<QuizModelException>()
            .having((error) => error.message, 'message', contains('限流'))
            .having(
              (error) => error.message,
              'does not contain API key',
              isNot(contains('secret-key-value')),
            ),
      ),
    );
  });

  test('serializes generation requests to one active model call', () async {
    var activeRequests = 0;
    var maxActiveRequests = 0;
    final releases = <Completer<void>>[];
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        activeRequests += 1;
        maxActiveRequests = maxActiveRequests < activeRequests
            ? activeRequests
            : maxActiveRequests;
        final release = Completer<void>();
        releases.add(release);
        await release.future;
        activeRequests -= 1;
        return http.Response('{"choices":[{"message":{"content":"[]"}}]}', 200);
      }),
    );

    final first = client.generate(settings, [verse]);
    final second = client.generate(settings, [verse]);
    await Future<void>.delayed(Duration.zero);
    expect(activeRequests, 1);
    releases.removeAt(0).complete();

    await Future<void>.delayed(Duration.zero);
    expect(activeRequests, 1);
    releases.removeAt(0).complete();
    await Future.wait([first, second]);
    expect(maxActiveRequests, 1);
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

  test(
    'Zhipu integration validates one meaningful word per verse',
    () async {
      final verses = [
        const QuizGenerationVerse(
          reference: '约翰福音 3:16',
          text: '神爱世人，甚至将他的独生子赐给他们，叫一切信他的，不至灭亡，反得永生。',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
        ),
        const QuizGenerationVerse(
          reference: '约翰福音 3:17',
          text: '因为神差他的儿子降世，不是要定世人的罪，乃是要叫世人因他得救。',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 17,
        ),
      ];
      final decoded =
          await QuizModelClient(timeout: const Duration(seconds: 60)).generate(
            const QuizModelSettings(
              baseUrl: QuizModelSettings.defaultBaseUrl,
              model: QuizModelSettings.defaultModel,
              apiKey: zhipuApiKey,
            ),
            verses,
          );
      final questions = const QuizQuestionValidator().validate(
        verses: verses,
        decodedJson: decoded,
      );
      expect(questions, hasLength(2));
      expect(questions.map((question) => question.reference).toSet(), {
        '约翰福音 3:16',
        '约翰福音 3:17',
      });
    },
    skip: zhipuApiKey.isEmpty ? '需要 ZHIPU_API_KEY 才运行真实服务测试' : false,
  );
}
