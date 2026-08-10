import 'dart:convert';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_bank_sync.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_bank_feed_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
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
        ValidatedQuizQuestion(
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
          verseText: '神爱世人',
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

      final first = await syncQuizBank(repository: repository, client: client);
      final second = await syncQuizBank(repository: repository, client: client);

      expect(first.imported, 1);
      expect(second.upToDate, isTrue);
      expect(shardRequests, 1);
      expect((await repository.listQuizBankQuestions()), hasLength(1));
    },
  );
}
