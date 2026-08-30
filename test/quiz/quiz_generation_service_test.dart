import 'dart:convert';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_generation_service.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_question_source.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  const settings = QuizModelSettings(
    baseUrl: 'https://example.test/v1',
    model: 'GLM-4.7-Flash',
    apiKey: 'test-key',
    modelAnsweringEnabled: true,
  );

  late SqlitePlanRepository repository;
  late Database database;

  setUp(() {
    database = sqlite3.openInMemory();
    repository = SqlitePlanRepository(database);
  });
  tearDown(() => repository.close());

  QuizScope scope() => const QuizScope(
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    startChapter: 3,
    startVerse: 16,
    endChapter: 3,
    endVerse: 16,
  );

  QuizScope scopeThroughVerse17() => const QuizScope(
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    startChapter: 3,
    startVerse: 16,
    endChapter: 3,
    endVerse: 17,
  );

  VerseUnit unit(int verse) => VerseUnit(
    translationId: 'cmn-cu89s',
    start: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: 3,
      verse: verse,
    ),
    end: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: 3,
      verse: verse,
    ),
    text: '神爱世人',
    status: SourceTextStatus.present,
  );

  VerseUnit unitAt(int chapter, int verse) => VerseUnit(
    translationId: 'cmn-cu89s',
    start: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: chapter,
      verse: verse,
    ),
    end: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: chapter,
      verse: verse,
    ),
    text: '神爱世人',
    status: SourceTextStatus.present,
  );

  _FakeScripture scripture() => _FakeScripture([unit(16), unit(17)]);

  test('generates and saves validated questions', () async {
    var calls = 0;
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode([
                    {
                      'reference': '3:16',
                      'word': '世人',
                      'start': 2,
                      'end': 4,
                      'length': 2,
                      'partOfSpeech': '名词',
                      'meaning': '世人：世上的人',
                    },
                  ]),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final service = QuizGenerationService(
      repository: repository,
      scripture: scripture(),
      client: client,
      settingsLoader: () async => settings,
    );
    final outcome = await service.prepare(scope());
    expect(outcome.success, isTrue);
    expect(outcome.generated, 1);
    expect(calls, 1);
    final pending = await repository.listPendingQuizQuestions(scope());
    expect(pending, hasLength(1));
    expect(pending.single.word, '世人');
    expect(pending.single.source, QuizQuestionSource.model);
  });

  test(
    'falls back to an existing local question when model generation fails',
    () async {
      await repository.saveQuizQuestions([
        ValidatedQuizQuestion(
          reference: '3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
          verseText: '神爱世人',
        ),
      ]);
      await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      final service = QuizGenerationService(
        repository: repository,
        scripture: scripture(),
        client: QuizModelClient(
          httpClient: MockClient((_) async => http.Response('失败', 503)),
        ),
        settingsLoader: () async => settings,
      );

      final outcome = await service.prepare(scope());

      expect(outcome.success, isTrue, reason: outcome.error);
      final pending = await repository.listPendingQuizQuestions(scope());
      expect(pending, hasLength(1));
      expect(pending.single.source, QuizQuestionSource.local);
    },
  );

  test('skips cached pending verses without invoking the model', () async {
    await repository.saveQuizQuestions([
      ValidatedQuizQuestion(
        reference: '3:16',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        verse: 16,
        start: 2,
        end: 4,
        word: '世人',
        partOfSpeech: '名词',
        meaning: '世上的人',
        verseText: '神爱世人',
      ),
    ]);
    var calls = 0;
    final client = QuizModelClient(
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('{"choices":[]}', 200);
      }),
    );
    final service = QuizGenerationService(
      repository: repository,
      scripture: _FakeScripture([unit(16)]),
      client: client,
      settingsLoader: () async => settings,
    );
    final outcome = await service.prepare(scope());
    expect(outcome.success, isTrue);
    expect(outcome.generated, 0);
    expect(calls, 0);
  });

  test(
    'uses local questions without requesting the model when model answering is disabled',
    () async {
      await repository.saveQuizQuestions([
        ValidatedQuizQuestion(
          reference: '3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
          verseText: '神爱世人',
        ),
      ]);
      var calls = 0;
      final service = QuizGenerationService(
        repository: repository,
        scripture: scripture(),
        client: QuizModelClient(
          httpClient: MockClient((request) async {
            calls++;
            return http.Response('{"choices":[]}', 200);
          }),
        ),
        settingsLoader: () async =>
            settings.copyWith(modelAnsweringEnabled: false),
      );

      final outcome = await service.prepare(scopeThroughVerse17());

      expect(calls, 0);
      expect(outcome.success, isFalse);
      expect(
        await repository.listQuizQuestionsForPractice(scopeThroughVerse17()),
        hasLength(1),
      );
    },
  );

  test(
    'excludes only the cached verse when equal verse numbers span chapters',
    () async {
      await repository.saveQuizQuestions([
        ValidatedQuizQuestion(
          reference: '3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
          verseText: '神爱世人',
        ),
      ]);
      String? prompt;
      final client = QuizModelClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final messages = body['messages']! as List<Object?>;
          prompt =
              ((messages.last! as Map<String, Object?>)['content'] as String);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode([
                      {
                        'reference': '4:16',
                        'word': '世人',
                        'start': 2,
                        'end': 4,
                        'length': 2,
                        'partOfSpeech': '名词',
                        'meaning': '世人：世上的人',
                      },
                    ]),
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final service = QuizGenerationService(
        repository: repository,
        scripture: _FakeScripture([unitAt(3, 16), unitAt(4, 16)]),
        client: client,
        settingsLoader: () async => settings,
      );
      const crossChapterScope = QuizScope(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 4,
        endVerse: 16,
      );

      final outcome = await service.prepare(crossChapterScope);

      expect(outcome.success, isTrue, reason: outcome.error);
      expect(prompt, isNot(contains('3:16')));
      expect(prompt, contains('4:16'));
      expect(
        await repository.listPendingQuizQuestions(crossChapterScope),
        hasLength(2),
      );
    },
  );

  test(
    'regenerates unanswered questions from an older quality version',
    () async {
      await repository.saveQuizQuestions([
        ValidatedQuizQuestion(
          reference: '3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世人：世上的人',
          verseText: '神爱世人',
        ),
      ]);
      database.execute('UPDATE quiz_question SET quality_version = 1');

      expect(await repository.listPendingQuizQuestions(scope()), isEmpty);
      expect(
        await repository.hasPendingQuizQuestion(
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
        ),
        isFalse,
      );
    },
  );

  test('reports incomplete model configuration before generation', () async {
    const incomplete = QuizModelSettings(
      baseUrl: 'https://example.test',
      model: 'GLM-4.7-Flash',
      apiKey: '',
      modelAnsweringEnabled: true,
    );
    expect(incomplete.isConfigured, isFalse);
    expect(incomplete.missingConfigurationMessage, contains('API Key'));

    final service = QuizGenerationService(
      repository: repository,
      scripture: scripture(),
      client: QuizModelClient(),
      settingsLoader: () async => incomplete,
    );
    final outcome = await service.prepare(scope());
    expect(outcome.success, isFalse);
    expect(outcome.error, contains('缺少答题模型配置'));
    expect(outcome.error, contains('API Key'));
  });

  test(
    'uses cached questions even when model configuration is incomplete',
    () async {
      await repository.saveQuizQuestions([
        ValidatedQuizQuestion(
          reference: '3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
          verseText: '神爱世人',
        ),
      ]);
      final service = QuizGenerationService(
        repository: repository,
        scripture: _FakeScripture([unit(16)]),
        client: QuizModelClient(),
        settingsLoader: () async => const QuizModelSettings(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: '',
        ),
      );

      final outcome = await service.prepare(scope());

      expect(outcome.success, isTrue);
      expect(outcome.error, isNull);
    },
  );

  test(
    'requeues one cached question when a verse has five questions',
    () async {
      await repository.saveQuizQuestions([
        for (var offset = 0; offset < 5; offset++)
          ValidatedQuizQuestion(
            reference: '3:16',
            translationId: 'cmn-cu89s',
            bookId: 'JHN',
            chapter: 3,
            verse: 16,
            start: offset,
            end: offset + 1,
            word: '神',
            partOfSpeech: '名词',
            meaning: '测试',
            verseText: '神爱世人',
          ),
      ]);
      for (var id = 1; id <= 5; id++) {
        await repository.completeQuizQuestion(
          questionId: id,
          correct: true,
          answeredAt: DateTime.now(),
        );
      }
      final service = QuizGenerationService(
        repository: repository,
        scripture: _FakeScripture([unit(16)]),
        client: QuizModelClient(),
        settingsLoader: () async => const QuizModelSettings(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: '',
        ),
      );

      final outcome = await service.prepare(scope());

      expect(outcome.success, isTrue);
      expect(await repository.listPendingQuizQuestions(scope()), hasLength(1));
    },
  );

  test(
    'prepares disjoint task scopes without filling their chapter gap',
    () async {
      final firstScope = scope();
      const laterScope = QuizScope(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 5,
        startVerse: 2,
        endChapter: 5,
        endVerse: 2,
      );
      await repository.saveQuizQuestions([
        for (final target in <({int chapter, int verse, String reference})>[
          (chapter: 3, verse: 16, reference: '3:16'),
          (chapter: 5, verse: 2, reference: '5:2'),
        ])
          ValidatedQuizQuestion(
            reference: target.reference,
            translationId: 'cmn-cu89s',
            bookId: 'JHN',
            chapter: target.chapter,
            verse: target.verse,
            start: 2,
            end: 4,
            word: '世人',
            partOfSpeech: '名词',
            meaning: '世上的人',
            verseText: '神爱世人',
          ),
      ]);
      final fake = _FakeScripture([unitAt(3, 16), unitAt(4, 1), unitAt(5, 2)]);
      final service = QuizGenerationService(
        repository: repository,
        scripture: fake,
        client: QuizModelClient(),
        settingsLoader: () async => const QuizModelSettings(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: '',
        ),
      );

      final outcome = await service.prepareScopes([firstScope, laterScope]);

      expect(outcome.success, isTrue);
      expect(fake.requestedRanges.map((range) => range.start.chapter), [3, 5]);
    },
  );

  test(
    'strictly filters an exact multi-chapter plan range before generation',
    () async {
      const planScope = QuizScope(
        translationId: 'cmn-cu89s',
        bookId: 'GEN',
        startChapter: 11,
        startVerse: 6,
        endChapter: 12,
        endVerse: 7,
      );
      VerseUnit genesisUnit(int chapter, int verse) => VerseUnit(
        translationId: 'cmn-cu89s',
        start: (
          canonId: CanonId.protestant66,
          osisBookId: 'GEN',
          chapter: chapter,
          verse: verse,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: 'GEN',
          chapter: chapter,
          verse: verse,
        ),
        text: '神爱世人',
        status: SourceTextStatus.present,
      );
      String? prompt;
      final client = QuizModelClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final messages = body['messages']! as List<Object?>;
          prompt =
              ((messages.last! as Map<String, Object?>)['content'] as String);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode([
                      for (final reference in ['11:6', '11:32', '12:1', '12:7'])
                        {
                          'reference': reference,
                          'word': '世人',
                          'start': 2,
                          'end': 4,
                          'length': 2,
                          'partOfSpeech': '名词',
                          'meaning': '世人：世上的人',
                        },
                    ]),
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final service = QuizGenerationService(
        repository: repository,
        // Deliberately simulate an over-wide source result. The service must
        // still use only 创世记 11:6–12:7.
        scripture: _FakeScripture([
          genesisUnit(11, 5),
          genesisUnit(11, 6),
          genesisUnit(11, 32),
          genesisUnit(12, 1),
          genesisUnit(12, 7),
          genesisUnit(12, 8),
        ], ignoreRequestedRange: true),
        client: client,
        settingsLoader: () async => settings,
      );

      final outcome = await service.prepare(planScope);

      expect(outcome.success, isTrue, reason: outcome.error);
      expect(prompt, contains('11:6'));
      expect(prompt, contains('12:7'));
      expect(prompt, isNot(contains('11:5')));
      expect(prompt, isNot(contains('12:8')));
      final questions = await repository.listQuizQuestionsForPractice(
        planScope,
      );
      expect(
        questions.map((question) => '${question.chapter}:${question.verse}'),
        ['11:6', '11:32', '12:1', '12:7'],
      );
    },
  );
}

final class _FakeScripture implements ScriptureRepository {
  _FakeScripture(this.units, {this.ignoreRequestedRange = false});
  final List<VerseUnit> units;
  final bool ignoreRequestedRange;
  final List<PassageRange> requestedRanges = [];

  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async {
    requestedRanges.add(range);
    if (ignoreRequestedRange) {
      return Passage(range: range, translationId: translationId, units: units);
    }
    final visible = units
        .where((unit) {
          if (unit.start.osisBookId != range.start.osisBookId) return false;
          final chapter = unit.start.chapter;
          final verse = unit.start.verse;
          final afterStart =
              chapter > range.start.chapter ||
              (chapter == range.start.chapter && verse >= range.start.verse);
          final beforeEnd =
              chapter < range.end.chapter ||
              (chapter == range.end.chapter && verse <= range.end.verse);
          return afterStart && beforeEnd;
        })
        .toList(growable: false);
    return Passage(range: range, translationId: translationId, units: visible);
  }

  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) async => throw UnimplementedError();

  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String osisBookId,
    int chapter,
  ) async => throw UnimplementedError();

  @override
  Future<List<BibleBook>> listBooks(
    String translationId,
    CanonId canonId,
  ) async => throw UnimplementedError();

  @override
  Future<List<TranslationInfo>> listTranslations() async =>
      throw UnimplementedError();

  @override
  Future<TranslationInfo> getTranslation(String id) async =>
      throw UnimplementedError();

  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) async => throw UnimplementedError();
}
