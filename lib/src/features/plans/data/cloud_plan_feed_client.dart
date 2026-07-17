import 'dart:convert';
import 'dart:io';

import '../domain/cloud_plan_manifest.dart';

typedef CloudPlanTextLoader = Future<String> Function(Uri uri);

final class CloudPlanFeedException implements Exception {
  const CloudPlanFeedException(this.message);
  final String message;

  @override
  String toString() => 'CloudPlanFeedException: $message';
}

final class CloudPlanFeedClient {
  CloudPlanFeedClient({
    this.loader,
    this.maxBytes = 1024 * 1024,
    this.timeout = const Duration(seconds: 15),
  });

  final CloudPlanTextLoader? loader;
  final int maxBytes;
  final Duration timeout;

  Future<CloudPlanManifest> fetchFirst(Iterable<Uri> uris) async {
    CloudPlanFeedException? lastError;
    for (final uri in uris) {
      try {
        return await fetch(uri);
      } on CloudPlanFeedException catch (error) {
        lastError = error;
      }
    }
    throw lastError ??
        const CloudPlanFeedException('No cloud plan URL provided');
  }

  Future<CloudPlanManifest> fetch(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Cloud plan URL must use HTTPS');
    }
    final text = await (loader == null ? _load(uri) : loader!(uri));
    if (utf8.encode(text).length > maxBytes) {
      throw CloudPlanFeedException(
        'Cloud plan response exceeds $maxBytes bytes',
      );
    }
    try {
      return CloudPlanManifest.parse(text);
    } on FormatException catch (error) {
      throw CloudPlanFeedException(error.message);
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
        throw CloudPlanFeedException(
          'Cloud plan server returned HTTP ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw CloudPlanFeedException(
          'Cloud plan response exceeds $maxBytes bytes',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw CloudPlanFeedException(
            'Cloud plan response exceeds $maxBytes bytes',
          );
        }
      }
      return utf8.decode(bytes);
    } on CloudPlanFeedException {
      rethrow;
    } on Object catch (error) {
      throw CloudPlanFeedException('Unable to download cloud plans: $error');
    } finally {
      client.close(force: true);
    }
  }
}
