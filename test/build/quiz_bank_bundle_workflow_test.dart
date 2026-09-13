import 'dart:io';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/quiz_bank/lib/offline_quiz_bank_bundle.dart';

void main() {
  const workflows = [
    '.github/workflows/android-apk.yml',
    '.github/workflows/testflight-renewal.yml',
  ];

  for (final path in workflows) {
    test('$path bundles every quiz-bank shard for offline practice', () {
      final workflow = File(path).readAsStringSync();

      expect(workflow, contains("jq -r '.shards[].path'"));
      expect(workflow, contains('dart run tool/bundle_quiz_bank.dart'));
      expect(workflow, isNot(contains('shards[0]')));
    });
  }

  test('combines every validated shard into the offline bank asset', () async {
    final directory = await Directory.systemTemp.createTemp('quiz-bank-bundle-');
    addTearDown(() => directory.delete(recursive: true));
    final first = QuizBankExchange.encode(const [
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
    final second = QuizBankExchange.encode(const [
      QuizBankQuestion(
        reference: '约翰二书 1:6',
        translationId: 'cmn-cu89s',
        bookId: '2JN',
        chapter: 1,
        verse: 6,
        start: 8,
        end: 10,
        word: '爱',
        partOfSpeech: '名词',
        meaning: '按主的命令彼此相待的生命实践',
      ),
    ]);
    await File('${directory.path}/quiz-bank-01.json').writeAsString(first);
    await File('${directory.path}/quiz-bank-02.json').writeAsString(second);
    final index = jsonEncode({
      'format': 'bible-recite-quiz-bank-index',
      'version': 1,
      'revision': 727,
      'snapshotMode': 'replace',
      'qualityVersion': 3,
      'shards': [
        await _shard('quiz-bank-01.json', first),
        await _shard('quiz-bank-02.json', second),
      ],
    });
    await File('${directory.path}/quiz-bank.index.json').writeAsString(index);

    await OfflineQuizBankBundle.build(
      indexFile: File('${directory.path}/quiz-bank.index.json'),
      shardDirectory: directory,
      outputBank: File('${directory.path}/offline.json'),
      outputIndex: File('${directory.path}/offline.index.json'),
    );

    expect(
      QuizBankExchange.decode(
        await File('${directory.path}/offline.json').readAsString(),
      ),
      hasLength(2),
    );
    final bundledIndex = jsonDecode(
      await File('${directory.path}/offline.index.json').readAsString(),
    ) as Map<String, Object?>;
    expect(bundledIndex['revision'], 727);
    expect(bundledIndex, isNot(contains('snapshotMode')));
    expect(bundledIndex['shards'], hasLength(1));
    expect((bundledIndex['shards'] as List).single['path'], 'quiz-bank.json');
  });
}

Future<Map<String, Object>> _shard(String path, String contents) async {
  final hash = await Sha256().hash(utf8.encode(contents));
  return {
    'path': path,
    'sha256': hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
    'bytes': utf8.encode(contents).length,
  };
}
