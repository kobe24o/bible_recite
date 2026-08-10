import 'dart:convert';

/// Small manifest fetched before any shared-bank shard. Its revision, ETag
/// and per-shard SHA-256 allow ordinary launches to avoid downloading a large
/// bank that has not changed.
final class QuizBankIndex {
  const QuizBankIndex({required this.revision, required this.shards});

  static const format = 'bible-recite-quiz-bank-index';
  static const version = 1;

  final int revision;
  final List<QuizBankShard> shards;

  factory QuizBankIndex.parse(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, Object?> ||
        root['format'] != format ||
        root['version'] != version ||
        root['revision'] is! int ||
        (root['revision'] as int) < 0 ||
        root['shards'] is! List<Object?>) {
      throw const FormatException('云端题库索引格式无效');
    }
    final paths = <String>{};
    final shards = <QuizBankShard>[];
    for (final item in root['shards']! as List<Object?>) {
      if (item is! Map<String, Object?> ||
          item['path'] is! String ||
          item['sha256'] is! String ||
          item['bytes'] is! int) {
        throw const FormatException('云端题库分片格式无效');
      }
      final path = item['path'] as String;
      final sha256 = (item['sha256'] as String).toLowerCase();
      final bytes = item['bytes'] as int;
      if (!_safePath(path) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
          bytes < 0 ||
          !paths.add(path)) {
        throw const FormatException('云端题库分片内容无效');
      }
      shards.add(QuizBankShard(path: path, sha256: sha256, bytes: bytes));
    }
    return QuizBankIndex(revision: root['revision']! as int, shards: shards);
  }

  static bool _safePath(String path) =>
      path.endsWith('.json') &&
      !path.contains('..') &&
      !path.contains('\\') &&
      !path.startsWith('/') &&
      path.isNotEmpty;
}

final class QuizBankShard {
  const QuizBankShard({
    required this.path,
    required this.sha256,
    required this.bytes,
  });

  final String path;
  final String sha256;
  final int bytes;
}
