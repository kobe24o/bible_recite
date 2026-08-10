import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../data/quiz_bank_feed_client.dart';
import 'quiz_bank_local_validator.dart';
import '../domain/quiz_bank_exchange.dart';
import '../domain/quiz_bank_index.dart';

const officialQuizBankGcoreBaseUrl =
    'https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankFastlyBaseUrl =
    'https://fastly.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankCdnBaseUrl =
    'https://cdn.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankRawBaseUrl =
    'https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/';

const quizBankIndexPath = 'quiz-bank.index.json';
const _quizBankEtagKey = 'quiz_bank_index_etag';
const _quizBankRevisionKey = 'quiz_bank_revision';
const _quizBankShardHashesKey = 'quiz_bank_shard_hashes';
const _quizBankLastSyncAtKey = 'quiz_bank_last_sync_at';
const _quizBankLastStatusKey = 'quiz_bank_last_status';

List<Uri> quizBankSourceCandidates(String path) => [
  Uri.parse('$officialQuizBankGcoreBaseUrl$path'),
  Uri.parse('$officialQuizBankFastlyBaseUrl$path'),
  Uri.parse('$officialQuizBankCdnBaseUrl$path'),
  Uri.parse('$officialQuizBankRawBaseUrl$path'),
];

final class QuizBankSyncResult {
  const QuizBankSyncResult({
    required this.imported,
    required this.duplicates,
    required this.rejected,
    required this.downloadedShards,
    required this.upToDate,
  });

  final int imported;
  final int duplicates;
  final int rejected;
  final int downloadedShards;
  final bool upToDate;
}

final class QuizBankSyncStatus {
  const QuizBankSyncStatus({
    required this.lastSyncedAt,
    required this.lastStatus,
    required this.revision,
  });

  final DateTime? lastSyncedAt;
  final String lastStatus;
  final int revision;
}

/// Syncs a public, question-only bank. An index ETag is checked first. If it
/// changed, only shards with a different SHA-256 are fetched and imported.
Future<QuizBankSyncResult> syncQuizBank({
  required SqlitePlanRepository repository,
  required ScriptureRepository scripture,
  required QuizBankFeedClient client,
}) async {
  final previousEtag = await repository.getSetting(_quizBankEtagKey, '');
  final indexResponse = await client.fetchFirst(
    quizBankSourceCandidates(quizBankIndexPath),
    ifNoneMatch: previousEtag,
  );
  if (indexResponse.notModified) {
    await _saveStatus(repository, '题库已是最新', revision: null);
    return const QuizBankSyncResult(
      imported: 0,
      duplicates: 0,
      rejected: 0,
      downloadedShards: 0,
      upToDate: true,
    );
  }
  final index = QuizBankIndex.parse(indexResponse.text);
  final knownHashes = await _loadShardHashes(repository);
  var imported = 0;
  var duplicates = 0;
  var rejected = 0;
  var downloaded = 0;
  final nextHashes = <String, String>{...knownHashes};
  for (final shard in index.shards) {
    if (knownHashes[shard.path] == shard.sha256) continue;
    final response = await client.fetchFirst(
      quizBankSourceCandidates(shard.path),
    );
    if (utf8.encode(response.text).length != shard.bytes) {
      throw QuizBankFeedException('题库分片 ${shard.path} 的文件大小校验失败');
    }
    final digest = await Sha256().hash(utf8.encode(response.text));
    final actual = digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actual != shard.sha256) {
      throw QuizBankFeedException('题库分片 ${shard.path} 的 SHA-256 校验失败');
    }
    final validated = await QuizBankLocalValidator(
      scripture,
    ).validate(QuizBankExchange.decode(response.text));
    final result = await repository.importQuizBankQuestions(validated.accepted);
    imported += result.imported;
    duplicates += result.duplicates;
    rejected += validated.rejected;
    downloaded++;
    nextHashes[shard.path] = shard.sha256;
  }
  nextHashes.removeWhere(
    (path, _) => !index.shards.any((shard) => shard.path == path),
  );
  await repository.setSetting(_quizBankShardHashesKey, jsonEncode(nextHashes));
  await repository.setSetting(_quizBankRevisionKey, '${index.revision}');
  if (indexResponse.etag != null && indexResponse.etag!.isNotEmpty) {
    await repository.setSetting(_quizBankEtagKey, indexResponse.etag!);
  }
  await _saveStatus(
    repository,
    downloaded == 0 ? '题库已是最新' : '同步新增 $imported 道题目',
    revision: index.revision,
  );
  return QuizBankSyncResult(
    imported: imported,
    duplicates: duplicates,
    rejected: rejected,
    downloadedShards: downloaded,
    upToDate: downloaded == 0,
  );
}

Future<QuizBankSyncStatus> loadQuizBankSyncStatus(
  SqlitePlanRepository repository,
) async {
  final rawTime = await repository.getSetting(_quizBankLastSyncAtKey, '');
  return QuizBankSyncStatus(
    lastSyncedAt: DateTime.tryParse(rawTime)?.toLocal(),
    lastStatus: await repository.getSetting(_quizBankLastStatusKey, '尚未同步'),
    revision:
        int.tryParse(await repository.getSetting(_quizBankRevisionKey, '0')) ??
        0,
  );
}

Future<Map<String, String>> _loadShardHashes(
  SqlitePlanRepository repository,
) async {
  try {
    final value = jsonDecode(
      await repository.getSetting(_quizBankShardHashesKey, '{}'),
    );
    if (value is! Map<String, Object?>) return <String, String>{};
    return {
      for (final entry in value.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  } on FormatException {
    return <String, String>{};
  }
}

Future<void> _saveStatus(
  SqlitePlanRepository repository,
  String status, {
  required int? revision,
}) async {
  await repository.setSetting(
    _quizBankLastSyncAtKey,
    DateTime.now().toUtc().toIso8601String(),
  );
  await repository.setSetting(_quizBankLastStatusKey, status);
  if (revision != null) {
    await repository.setSetting(_quizBankRevisionKey, '$revision');
  }
}
