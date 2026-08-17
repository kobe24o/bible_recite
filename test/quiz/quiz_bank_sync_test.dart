import 'dart:convert';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_bank_sync.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_bank_feed_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'uses ETag index check to avoid downloading an unchanged cloud bank',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final bank = QuizBankExchange.encode(const [
        QuizBankQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
        ),
      ]);
      final digest = await Sha256().hash(utf8.encode(bank));
      final sha256 = digest.bytes
          .map((item) => item.toRadixString(16).padLeft(2, '0'))
          .join();
      final index = jsonEncode({
        'format': 'bible-recite-quiz-bank-index',
        'version': 1,
        'revision': 1,
        'shards': [
          {
            'path': 'quiz-bank.json',
            'sha256': sha256,
            'bytes': utf8.encode(bank).length,
          },
        ],
      });
      var shardRequests = 0;
      final client = QuizBankFeedClient(
        loader: (uri, ifNoneMatch) async {
          if (uri.path.endsWith(quizBankIndexPath)) {
            return ifNoneMatch == '"r1"'
                ? const QuizBankFeedResponse(statusCode: 304)
                : QuizBankFeedResponse(
                    statusCode: 200,
                    text: index,
                    etag: '"r1"',
                  );
          }
          shardRequests++;
          return QuizBankFeedResponse(statusCode: 200, text: bank);
        },
      );

      final scripture = _FakeScripture();
      final first = await syncQuizBank(
        repository: repository,
        scripture: scripture,
        client: client,
      );
      final second = await syncQuizBank(
        repository: repository,
        scripture: scripture,
        client: client,
      );

      expect(first.imported, 1);
      expect(second.upToDate, isTrue);
      expect(shardRequests, 1);
      expect((await repository.listQuizBankQuestions()), hasLength(1));
    },
  );

  test(
    'refreshes a local meaning when a newer cloud shard changes it',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      var bank = QuizBankExchange.encode(const [
        QuizBankQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
        ),
      ]);
      var index = await _indexFor(revision: 1, bank: bank);
      final client = QuizBankFeedClient(
        loader: (uri, _) async => uri.path.endsWith(quizBankIndexPath)
            ? QuizBankFeedResponse(statusCode: 200, text: index, etag: '"live"')
            : QuizBankFeedResponse(statusCode: 200, text: bank),
      );

      await syncQuizBank(
        repository: repository,
        scripture: _FakeScripture(),
        client: client,
      );
      bank = QuizBankExchange.encode(const [
        QuizBankQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上所有的人',
        ),
      ]);
      index = await _indexFor(revision: 2, bank: bank);

      final refreshed = await syncQuizBank(
        repository: repository,
        scripture: _FakeScripture(),
        client: client,
      );

      expect(refreshed.imported, 0);
      expect(refreshed.updated, 1);
      expect(
        (await repository.listQuizBankQuestions()).single.meaning,
        '世上所有的人',
      );
    },
  );

  test(
    'checks every mirror, selects the highest revision and skips stale shards',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final staleBank = QuizBankExchange.encode(const [
        QuizBankQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 0,
          end: 1,
          word: '神',
          partOfSpeech: '名词',
          meaning: '神明',
        ),
      ]);
      final newestBank = QuizBankExchange.encode(const [
        QuizBankQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
        ),
      ]);
      final staleIndex = await _indexFor(revision: 4, bank: staleBank);
      final newestIndex = await _indexFor(revision: 16, bank: newestBank);
      final checkedIndexes = <String>{};
      final downloadedShards = <String>[];
      final client = QuizBankFeedClient(
        loader: (uri, _) async {
          if (uri.path.endsWith(quizBankIndexPath)) {
            checkedIndexes.add(uri.host);
            return QuizBankFeedResponse(
              statusCode: 200,
              text: uri.host == 'gcore.jsdelivr.net' ? staleIndex : newestIndex,
              etag: '"${uri.host}"',
            );
          }
          downloadedShards.add(uri.host);
          // Simulate a stale Fastly shard even though its index is current.
          // The SHA check must make the client continue to cdn.jsdelivr.net.
          return QuizBankFeedResponse(
            statusCode: 200,
            text: uri.host == 'fastly.jsdelivr.net' ? staleBank : newestBank,
          );
        },
      );

      final result = await syncQuizBank(
        repository: repository,
        scripture: _FakeScripture(),
        client: client,
      );

      expect(result.imported, 1);
      expect(result.downloadedShards, 1);
      expect(checkedIndexes, {
        'fastly.jsdelivr.net',
        'cdn.jsdelivr.net',
        'raw.githubusercontent.com',
        'gcore.jsdelivr.net',
      });
      expect(downloadedShards, ['fastly.jsdelivr.net', 'cdn.jsdelivr.net']);
      expect(await repository.getSetting('quiz_bank_revision', ''), '16');
      expect((await repository.listQuizBankQuestions()).single.word, '世人');
    },
  );

  test('imports the latest packaged bank once for offline practice', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final bank = QuizBankExchange.encode(const [
      QuizBankQuestion(
        reference: '约翰福音 3:16',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        verse: 16,
        start: 2,
        end: 4,
        word: '世人',
        partOfSpeech: '名词',
        meaning: '世上的人',
      ),
    ]);
    final index = await _indexFor(revision: 16, bank: bank);
    Future<String> loader(String path) async => switch (path) {
      bundledQuizBankIndexAsset => index,
      bundledQuizBankShardAsset => bank,
      _ => throw StateError('unknown asset $path'),
    };

    final first = await importBundledQuizBank(
      repository: repository,
      scripture: _FakeScripture(),
      assetLoader: loader,
    );
    final second = await importBundledQuizBank(
      repository: repository,
      scripture: _FakeScripture(),
      assetLoader: loader,
    );

    expect(first.imported, 1);
    expect(second.imported, 0);
    expect(await repository.getSetting('quiz_bank_revision', ''), '16');
    expect((await repository.listQuizBankQuestions()), hasLength(1));
  });
}

Future<String> _indexFor({required int revision, required String bank}) async {
  final digest = await Sha256().hash(utf8.encode(bank));
  final sha256 = digest.bytes
      .map((item) => item.toRadixString(16).padLeft(2, '0'))
      .join();
  return jsonEncode({
    'format': 'bible-recite-quiz-bank-index',
    'version': 1,
    'revision': revision,
    'shards': [
      {
        'path': 'quiz-bank.json',
        'sha256': sha256,
        'bytes': utf8.encode(bank).length,
      },
    ],
  });
}

final class _FakeScripture implements ScriptureRepository {
  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String book,
    int chapter,
  ) async => [
    VerseUnit(
      translationId: translationId,
      start: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 16,
      ),
      end: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 16,
      ),
      text: '神爱世人',
      status: SourceTextStatus.present,
    ),
  ];

  @override
  Future<List<TranslationInfo>> listTranslations() =>
      throw UnimplementedError();
  @override
  Future<TranslationInfo> getTranslation(String id) =>
      throw UnimplementedError();
  @override
  Future<List<BibleBook>> listBooks(String translationId, CanonId canonId) =>
      throw UnimplementedError();
  @override
  Future<Passage> getPassage(String translationId, PassageRange range) =>
      throw UnimplementedError();
  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) => throw UnimplementedError();
  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) => throw UnimplementedError();
}
