import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../data/quiz_bank_feed_client.dart';
import 'quiz_bank_local_validator.dart';
import '../domain/quiz_bank_exchange.dart';
import '../domain/quiz_bank_index.dart';
import '../domain/quiz_models.dart';
import '../domain/quiz_question_source.dart';

const officialQuizBankGcoreBaseUrl =
    'https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankFastlyBaseUrl =
    'https://fastly.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankCdnBaseUrl =
    'https://cdn.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/';
const officialQuizBankRawBaseUrl =
    'https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/';

const quizBankIndexPath = 'quiz-bank.index.json';
const bundledQuizBankIndexAsset = 'assets/quiz_bank/quiz-bank.index.json';
const bundledQuizBankShardAsset = 'assets/quiz_bank/quiz-bank.json';
const _quizBankIndexEtagsKey = 'quiz_bank_index_etags';
const _quizBankRevisionKey = 'quiz_bank_revision';
const _quizBankShardHashesKey = 'quiz_bank_shard_hashes';
const _quizBankBundledHashKey = 'quiz_bank_bundled_hash';
const _quizBankLastSyncAtKey = 'quiz_bank_last_sync_at';
const _quizBankLastStatusKey = 'quiz_bank_last_status';

List<Uri> quizBankSourceCandidates(String path) => [
  Uri.parse('$officialQuizBankFastlyBaseUrl$path'),
  Uri.parse('$officialQuizBankCdnBaseUrl$path'),
  Uri.parse('$officialQuizBankRawBaseUrl$path'),
  Uri.parse('$officialQuizBankGcoreBaseUrl$path'),
];

typedef QuizBankAssetLoader = Future<String> Function(String assetPath);

final class _QuizBankIndexCandidate {
  const _QuizBankIndexCandidate({required this.source, required this.index});

  final Uri source;
  final QuizBankIndex index;
}

final class QuizBankSyncResult {
  const QuizBankSyncResult({
    required this.imported,
    required this.duplicates,
    required this.rejected,
    required this.downloadedShards,
    required this.upToDate,
    this.updated = 0,
    this.replacedSnapshot = false,
  });

  final int imported;
  final int duplicates;
  final int rejected;
  final int downloadedShards;
  final bool upToDate;
  final int updated;
  final bool replacedSnapshot;
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

/// Syncs a public, question-only bank. Every mirror is checked and the
/// highest valid index revision wins, so one CDN's stale branch cache cannot
/// make a newer bank look up to date. Index ETags are stored per source; a
/// validator from one CDN is never sent to another CDN.
Future<QuizBankSyncResult> syncQuizBank({
  required SqlitePlanRepository repository,
  required ScriptureRepository scripture,
  required QuizBankFeedClient client,
}) async {
  final newest = await _loadNewestIndex(repository, client);
  if (newest == null) {
    await _saveStatus(repository, '题库已是最新', revision: null);
    return const QuizBankSyncResult(
      imported: 0,
      duplicates: 0,
      rejected: 0,
      downloadedShards: 0,
      upToDate: true,
    );
  }
  final index = newest.index;
  final knownRevision =
      int.tryParse(await repository.getSetting(_quizBankRevisionKey, '0')) ?? 0;
  // A temporarily stale set of mirrors must not roll a newer packaged/local
  // bank backward. Revisions are append-only in the shared bank.
  if (index.revision < knownRevision) {
    throw QuizBankFeedException(
      '云端题库索引版本回退（云端 ${index.revision}，本机 $knownRevision）',
    );
  }
  final knownHashes = await _loadShardHashes(repository);
  final replacing = index.snapshotMode == QuizBankSnapshotMode.replace;
  var imported = 0;
  var updated = 0;
  var duplicates = 0;
  var rejected = 0;
  var downloaded = 0;
  final nextHashes = <String, String>{...knownHashes};
  if (replacing) await repository.discardStagedQuizBankSnapshot(index.revision);
  try {
    for (final shard in index.shards) {
      if (!replacing && knownHashes[shard.path] == shard.sha256) continue;
      final response = await _downloadMatchingShard(
        client: client,
        shard: shard,
        indexSource: newest.source,
      );
      final validated = await QuizBankLocalValidator(scripture).validate(
        QuizBankExchange.decode(response.text),
        source: QuizQuestionSource.cloud,
      );
      if (replacing) {
        await repository.stageQuizBankSnapshot(
          index.revision,
          validated.accepted,
        );
      } else {
        final result = await repository.importQuizBankQuestions(
          validated.accepted,
        );
        imported += result.imported;
        updated += result.updated;
        duplicates += result.duplicates;
      }
      rejected += validated.rejected;
      downloaded++;
      nextHashes[shard.path] = shard.sha256;
    }
    if (replacing) {
      await repository.activateStagedQuizBankSnapshot(index.revision);
      imported = (await repository.listQuizBankQuestions()).length;
    }
  } catch (_) {
    if (replacing)
      await repository.discardStagedQuizBankSnapshot(index.revision);
    rethrow;
  }
  nextHashes.removeWhere(
    (path, _) => !index.shards.any((shard) => shard.path == path),
  );
  await repository.setSetting(_quizBankShardHashesKey, jsonEncode(nextHashes));
  await repository.setSetting(_quizBankRevisionKey, '${index.revision}');
  await _saveStatus(
    repository,
    downloaded == 0
        ? '题库已是最新'
        : replacing
        ? '题库质量更新完成：已替换 $imported 道题；历史答题记录已保留。'
        : '同步新增 $imported 道题目，更新 $updated 道释义',
    revision: index.revision,
  );
  return QuizBankSyncResult(
    imported: imported,
    duplicates: duplicates,
    rejected: rejected,
    downloadedShards: downloaded,
    upToDate: downloaded == 0,
    updated: updated,
    replacedSnapshot: replacing,
  );
}

/// Imports the bank packaged with this app version. This makes the newest
/// shipped questions usable offline; existing answer history is preserved.
/// The asset digest makes repeat launches a constant-time no-op.
Future<QuizBankImportResult> importBundledQuizBank({
  required SqlitePlanRepository repository,
  required ScriptureRepository scripture,
  QuizBankAssetLoader? assetLoader,
}) async {
  final load = assetLoader ?? rootBundle.loadString;
  final indexText = await load(bundledQuizBankIndexAsset);
  final bankText = await load(bundledQuizBankShardAsset);
  final bankHash = await _sha256(utf8.encode(bankText));
  if (await repository.getSetting(_quizBankBundledHashKey, '') == bankHash) {
    return const QuizBankImportResult();
  }
  final index = QuizBankIndex.parse(indexText);
  if (index.shards.length != 1 ||
      index.shards.single.path != 'quiz-bank.json') {
    throw const FormatException('内置题库索引不支持的分片格式');
  }
  final shard = index.shards.single;
  final bytes = utf8.encode(bankText);
  if (bytes.length != shard.bytes || bankHash != shard.sha256) {
    throw const FormatException('内置题库文件校验失败');
  }
  final validation = await QuizBankLocalValidator(scripture).validate(
    QuizBankExchange.decode(bankText),
    source: QuizQuestionSource.cloud,
  );
  final result = await repository.importQuizBankQuestions(validation.accepted);
  await repository.setSetting(_quizBankBundledHashKey, bankHash);
  await repository.setSetting(
    _quizBankShardHashesKey,
    jsonEncode({shard.path: shard.sha256}),
  );
  await repository.setSetting(_quizBankRevisionKey, '${index.revision}');
  return result;
}

/// Checks every index mirror. A 304 means only that *that source* has not
/// changed; it never prevents another mirror from supplying a newer index.
Future<_QuizBankIndexCandidate?> _loadNewestIndex(
  SqlitePlanRepository repository,
  QuizBankFeedClient client,
) async {
  final etags = await _loadIndexEtags(repository);
  final nextEtags = <String, String>{...etags};
  final candidates = <_QuizBankIndexCandidate>[];
  final errors = <String>[];
  var notModified = 0;
  for (final source in quizBankSourceCandidates(quizBankIndexPath)) {
    try {
      final response = await client.fetch(
        source,
        ifNoneMatch: etags[source.toString()],
      );
      final etag = response.etag;
      if (etag != null && etag.isNotEmpty) nextEtags[source.toString()] = etag;
      if (response.notModified) {
        notModified++;
        continue;
      }
      candidates.add(
        _QuizBankIndexCandidate(
          source: source,
          index: QuizBankIndex.parse(response.text),
        ),
      );
    } on FormatException catch (error) {
      errors.add('${source.host}: 索引格式无效（$error）');
    } on QuizBankFeedException catch (error) {
      errors.add('${source.host}: ${error.message}');
    }
  }
  await _saveIndexEtags(repository, nextEtags);
  if (candidates.isEmpty) {
    if (notModified > 0) return null;
    throw QuizBankFeedException(
      errors.isEmpty ? '未获取到云端题库索引' : errors.join('；'),
    );
  }
  candidates.sort(
    (left, right) => right.index.revision.compareTo(left.index.revision),
  );
  return candidates.first;
}

/// Downloads a shard only when its bytes and SHA-256 agree with the selected
/// newest index. A stale mirror is skipped rather than aborting the sync.
Future<QuizBankFeedResponse> _downloadMatchingShard({
  required QuizBankFeedClient client,
  required QuizBankShard shard,
  required Uri indexSource,
}) async {
  final preferred = indexSource.resolve(shard.path);
  final sources = <Uri>[
    preferred,
    for (final source in quizBankSourceCandidates(shard.path))
      if (source != preferred) source,
  ];
  final errors = <String>[];
  for (final source in sources) {
    try {
      final response = await client.fetch(source);
      final bytes = utf8.encode(response.text);
      if (bytes.length != shard.bytes) {
        errors.add('${source.host}: 文件大小不匹配');
        continue;
      }
      if (await _sha256(bytes) != shard.sha256) {
        errors.add('${source.host}: SHA-256 不匹配');
        continue;
      }
      return response;
    } on QuizBankFeedException catch (error) {
      errors.add('${source.host}: ${error.message}');
    }
  }
  throw QuizBankFeedException('题库分片 ${shard.path} 无可用最新副本：${errors.join('；')}');
}

Future<String> _sha256(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  return digest.bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
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

Future<Map<String, String>> _loadIndexEtags(
  SqlitePlanRepository repository,
) async {
  try {
    final value = jsonDecode(
      await repository.getSetting(_quizBankIndexEtagsKey, '{}'),
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

Future<void> _saveIndexEtags(
  SqlitePlanRepository repository,
  Map<String, String> etags,
) => repository.setSetting(_quizBankIndexEtagsKey, jsonEncode(etags));

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
