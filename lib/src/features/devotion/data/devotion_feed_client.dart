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
    final String text;
    try {
      text = await (loader == null
          ? _load(uri)
          : loader!(uri).timeout(timeout));
    } on DevotionFeedException {
      rethrow;
    } on Object catch (error) {
      throw DevotionFeedException('Unable to download devotion plans: $error');
    }
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
    final deadline = DateTime.now().add(timeout);
    var current = uri;
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        final request = await client
            .getUrl(current)
            .timeout(_remaining(deadline));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(_remaining(deadline));
        if (_isRedirect(response.statusCode)) {
          if (redirects == 3) {
            throw const DevotionFeedException(
              'Devotion redirect limit exceeded',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw const DevotionFeedException(
              'Devotion redirect has no location',
            );
          }
          final redirect = current.resolve(location);
          if (redirect.scheme != 'https' || redirect.host.isEmpty) {
            throw const DevotionFeedException(
              'Devotion redirect must use HTTPS',
            );
          }
          await response.drain<void>().timeout(_remaining(deadline));
          current = redirect;
          continue;
        }
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
        final bytes = await response
            .fold(<int>[], (result, chunk) {
              result.addAll(chunk);
              if (result.length > maxBytes) {
                throw DevotionFeedException(
                  'Devotion response exceeds $maxBytes bytes',
                );
              }
              return result;
            })
            .timeout(_remaining(deadline));
        return utf8.decode(bytes);
      }
      throw const DevotionFeedException('Devotion redirect limit exceeded');
    } on DevotionFeedException {
      rethrow;
    } on Object catch (error) {
      throw DevotionFeedException('Unable to download devotion plans: $error');
    } finally {
      client.close(force: true);
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
