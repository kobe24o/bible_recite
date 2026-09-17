import 'dart:convert';
import 'dart:io';

import '../domain/devotion_models.dart';

typedef DevotionTextLoader = Future<String> Function(Uri uri);

final class DevotionFeedException implements Exception {
  const DevotionFeedException(this.message);

  final String message;

  @override
  String toString() => 'DevotionFeedException: $message';
}

final class DevotionFeedClient {
  DevotionFeedClient({
    this.loader,
    this.maxBytes = 1024 * 1024,
    this.timeout = const Duration(seconds: 15),
  });

  final DevotionTextLoader? loader;
  final int maxBytes;
  final Duration timeout;

  Future<DevotionManifest> fetchFirst(Iterable<Uri> uris) async {
    final errors = <String>[];
    for (final uri in uris) {
      try {
        return await fetch(uri);
      } on DevotionFeedException catch (error) {
        errors.add('${uri.host}: ${error.message}');
      }
    }
    if (errors.isEmpty) {
      throw const DevotionFeedException('No devotion URL provided');
    }
    throw DevotionFeedException(
      'All devotion sources failed: ${errors.join('; ')}',
    );
  }

  Future<DevotionManifest> fetch(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Devotion URL must use HTTPS');
    }
    final text = await (loader == null ? _load(uri) : loader!(uri));
    if (utf8.encode(text).length > maxBytes) {
      throw DevotionFeedException('Devotion response exceeds $maxBytes bytes');
    }
    try {
      return DevotionManifest.parse(text);
    } on FormatException catch (error) {
      throw DevotionFeedException(error.message);
    }
  }

  Future<String> _load(Uri uri) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 3;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw DevotionFeedException(
          'Devotion server returned HTTP ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw DevotionFeedException(
          'Devotion response exceeds $maxBytes bytes',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw DevotionFeedException(
            'Devotion response exceeds $maxBytes bytes',
          );
        }
      }
      return utf8.decode(bytes);
    } on DevotionFeedException {
      rethrow;
    } on Object catch (error) {
      throw DevotionFeedException('Unable to download devotion plans: $error');
    } finally {
      client.close(force: true);
    }
  }
}
