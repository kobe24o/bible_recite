import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_bank_index.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:cryptography/cryptography.dart';

/// Produces the single-file quiz-bank asset consumed by the offline app.
///
/// Cloud distribution may split a snapshot into several shards, while the app
/// deliberately imports a single, checksum-verified asset at launch. This
/// builder validates every listed shard before combining them.
final class OfflineQuizBankBundle {
  static Future<void> build({
    required File indexFile,
    required Directory shardDirectory,
    required File outputBank,
    required File outputIndex,
  }) async {
    final index = QuizBankIndex.parse(await indexFile.readAsString());
    final questions = <QuizBankQuestion>[];
    for (final shard in index.shards) {
      final file = File('${shardDirectory.path}/${shard.path}');
      final bytes = await file.readAsBytes();
      final sha256 = await _sha256(bytes);
      if (bytes.length != shard.bytes || sha256 != shard.sha256) {
        throw FormatException('题库分片校验失败：${shard.path}');
      }
      questions.addAll(QuizBankExchange.decode(utf8.decode(bytes)));
    }
    final bankText = QuizBankExchange.encode(questions);
    final bankBytes = utf8.encode(bankText);
    final bankSha256 = await _sha256(bankBytes);
    await outputBank.parent.create(recursive: true);
    await outputBank.writeAsString(bankText);
    await outputIndex.parent.create(recursive: true);
    await outputIndex.writeAsString(
      jsonEncode({
        'format': QuizBankIndex.format,
        'version': QuizBankIndex.version,
        'revision': index.revision,
        'shards': [
          {
            'path': 'quiz-bank.json',
            'sha256': bankSha256,
            'bytes': bankBytes.length,
          },
        ],
      }),
    );
  }

  static Future<String> _sha256(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
