import 'dart:convert';
import 'dart:io';

typedef QuizBankHttpLoader =
    Future<QuizBankFeedResponse> Function(Uri uri, String? ifNoneMatch);

final class QuizBankFeedException implements Exception {
  const QuizBankFeedException(this.message);
  final String message;

  @override
  String toString() => 'QuizBankFeedException: $message';
}

final class QuizBankFeedResponse {
  const QuizBankFeedResponse({
    required this.statusCode,
    this.text = '',
    this.etag,
  });

  final int statusCode;
  final String text;
  final String? etag;

  bool get notModified => statusCode == HttpStatus.notModified;
}

/// HTTPS-only client with bounded payloads. The index request supports ETag
/// validation; bank shards are only downloaded when their index SHA changes.
final class QuizBankFeedClient {
  QuizBankFeedClient({
    this.loader,
    this.maxBytes = 10 * 1024 * 1024,
    this.timeout = const Duration(seconds: 15),
  });

  final QuizBankHttpLoader? loader;
  final int maxBytes;
  final Duration timeout;

  Future<QuizBankFeedResponse> fetchFirst(
    Iterable<Uri> uris, {
    String? ifNoneMatch,
  }) async {
    final errors = <String>[];
    for (final uri in uris) {
      try {
        return await fetch(uri, ifNoneMatch: ifNoneMatch);
      } on QuizBankFeedException catch (error) {
        errors.add('${uri.host}: ${error.message}');
      }
    }
    throw QuizBankFeedException(
      errors.isEmpty ? '未提供云端题库地址' : errors.join('；'),
    );
  }

  Future<QuizBankFeedResponse> fetch(Uri uri, {String? ifNoneMatch}) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', '云端题库地址必须使用 HTTPS');
    }
    final response = await (loader == null
        ? _load(uri, ifNoneMatch)
        : loader!(uri, ifNoneMatch));
    if (response.notModified) return response;
    if (response.statusCode != HttpStatus.ok) {
      throw QuizBankFeedException('服务器返回 HTTP ${response.statusCode}');
    }
    if (utf8.encode(response.text).length > maxBytes) {
      throw QuizBankFeedException(
        '题库文件超过 ${(maxBytes / 1024 / 1024).round()} MB',
      );
    }
    return response;
  }

  Future<QuizBankFeedResponse> _load(Uri uri, String? ifNoneMatch) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 3;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
      }
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notModified) {
        return QuizBankFeedResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.contentLength > maxBytes) {
        throw QuizBankFeedException(
          '题库文件超过 ${(maxBytes / 1024 / 1024).round()} MB',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw QuizBankFeedException(
            '题库文件超过 ${(maxBytes / 1024 / 1024).round()} MB',
          );
        }
      }
      return QuizBankFeedResponse(
        statusCode: response.statusCode,
        text: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } on QuizBankFeedException {
      rethrow;
    } on Object catch (error) {
      throw QuizBankFeedException('下载云端题库失败：$error');
    } finally {
      client.close(force: true);
    }
  }
}
