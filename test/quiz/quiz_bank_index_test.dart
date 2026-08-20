import 'dart:convert';

import 'package:bible_recite/src/features/quiz/domain/quiz_bank_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shard = {
    'path': 'quiz-bank-01.json',
    'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'bytes': 123,
  };

  test('parses a v3 replace snapshot', () {
    final index = QuizBankIndex.parse(
      jsonEncode({
        'format': QuizBankIndex.format,
        'version': QuizBankIndex.version,
        'revision': 702,
        'snapshotMode': 'replace',
        'qualityVersion': 3,
        'shards': [shard],
      }),
    );

    expect(index.snapshotMode, QuizBankSnapshotMode.replace);
    expect(index.qualityVersion, 3);
  });

  test('keeps a legacy index incremental', () {
    final index = QuizBankIndex.parse(
      jsonEncode({
        'format': QuizBankIndex.format,
        'version': QuizBankIndex.version,
        'revision': 701,
        'shards': [shard],
      }),
    );

    expect(index.snapshotMode, QuizBankSnapshotMode.incremental);
    expect(index.qualityVersion, 2);
  });

  test('rejects an unknown snapshot mode or invalid quality version', () {
    final base = {
      'format': QuizBankIndex.format,
      'version': QuizBankIndex.version,
      'revision': 702,
      'shards': [shard],
    };

    expect(
      () => QuizBankIndex.parse(jsonEncode({...base, 'snapshotMode': 'reset'})),
      throwsFormatException,
    );
    expect(
      () => QuizBankIndex.parse(jsonEncode({...base, 'qualityVersion': 0})),
      throwsFormatException,
    );
  });
}
