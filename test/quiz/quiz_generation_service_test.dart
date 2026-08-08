import 'dart:convert';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_generation_service.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
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
  });

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

  test('fails gracefully when the model key is missing', () async {
    final service = QuizGenerationService(
      repository: repository,
      scripture: scripture(),
      client: QuizModelClient(),
      settingsLoader: () async => const QuizModelSettings(
        baseUrl: 'https://example.test',
        model: 'GLM-4.7-Flash',
        apiKey: '',
      ),
    );
    final outcome = await service.prepare(scope());
    expect(outcome.success, isFalse);
    expect(outcome.error, contains('API Key'));
  });
}

final class _FakeScripture implements ScriptureRepository {
  _FakeScripture(this.units);
  final List<VerseUnit> units;

  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async {
    return Passage(range: range, translationId: translationId, units: units);
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
