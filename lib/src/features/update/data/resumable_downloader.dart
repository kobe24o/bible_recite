import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/update_manifest.dart';

const _connectTimeout = Duration(seconds: 15);
final _strongEtagPattern = RegExp(r'^"[\x21\x23-\x7e]*"$');
final _contentRangePattern = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$');

final class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;
}

final class DownloadedUpdate {
  const DownloadedUpdate({required this.file});

  final File file;
}

final class DownloadCancellation {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const DownloadCancelled();
    }
  }
}

final class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

final class DownloadException implements Exception {
  DownloadException(List<String> failures)
    : failures = List.unmodifiable(failures);

  final List<String> failures;
}

/// Downloads a manifest-validated APK without buffering it in memory.
final class ResumableDownloader {
  ResumableDownloader() : this._(HttpClient.new, _identityUri);

  /// Provides a real-HTTP test seam without weakening HTTPS asset validation.
  ResumableDownloader.forTesting({
    HttpClient Function()? httpClientFactory,
    required Uri Function(Uri) requestUriResolver,
  }) : this._(httpClientFactory ?? HttpClient.new, requestUriResolver);

  ResumableDownloader._(this._httpClientFactory, this._requestUriResolver);

  final HttpClient Function() _httpClientFactory;
  final Uri Function(Uri) _requestUriResolver;

  Future<DownloadedUpdate> download(
    AndroidUpdateAsset asset,
    Directory directory, {
    required void Function(DownloadProgress) onProgress,
    required DownloadCancellation cancellation,
  }) async {
    await directory.create(recursive: true);
    final partFile = File(_partPath(directory, asset));
    final sidecarFile = File(_sidecarPath(directory, asset));
    final completedFile = File(_completedPath(directory, asset));
    final resume = await _readResumeState(partFile, sidecarFile, asset);
    final failures = <String>[];

    for (final source in asset.urls) {
      cancellation.throwIfCancelled();
      final canResume = resume != null && resume.url == source.toString();
      if (resume != null && !canResume) {
        await _deleteIfExists(partFile);
        await _deleteIfExists(sidecarFile);
      }

      try {
        await _downloadSource(
          source: source,
          asset: asset,
          partFile: partFile,
          sidecarFile: sidecarFile,
          resume: canResume ? resume : null,
          onProgress: onProgress,
          cancellation: cancellation,
        );
        cancellation.throwIfCancelled();
        if (await completedFile.exists()) {
          throw StateError('Completed update file already exists');
        }
        await partFile.rename(completedFile.path);
        await _deleteIfExists(sidecarFile);
        return DownloadedUpdate(file: completedFile);
      } on DownloadCancelled {
        rethrow;
      } catch (error) {
        failures.add('${source.host}: $error');
      }
    }

    throw DownloadException(failures);
  }

  Future<void> _downloadSource({
    required Uri source,
    required AndroidUpdateAsset asset,
    required File partFile,
    required File sidecarFile,
    required _ResumeState? resume,
    required void Function(DownloadProgress) onProgress,
    required DownloadCancellation cancellation,
  }) async {
    var activeResume = resume;
    while (true) {
      cancellation.throwIfCancelled();
      final opened = await _open(source, activeResume, cancellation);
      try {
        final response = opened.response;
        if (response.statusCode == HttpStatus.partialContent) {
          if (activeResume == null) {
            throw const FormatException('Unexpected partial-content response');
          }
          _validatePartialResponse(response, asset, activeResume);
          final etag = _requiredStrongEtag(response);
          if (etag != activeResume.etag) {
            await response.drain<void>();
            await _deleteIfExists(partFile);
            await _deleteIfExists(sidecarFile);
            activeResume = null;
            continue;
          }
          await _writeResponse(
            response: response,
            source: source,
            etag: etag,
            asset: asset,
            partFile: partFile,
            sidecarFile: sidecarFile,
            initialBytes: activeResume.receivedBytes,
            append: true,
            onProgress: onProgress,
            cancellation: cancellation,
          );
          return;
        }

        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Unexpected HTTP status ${response.statusCode}');
        }
        _validateFullResponse(response, asset);
        final etag = _requiredStrongEtag(response);
        if (activeResume != null) {
          await _deleteIfExists(partFile);
          await _deleteIfExists(sidecarFile);
          activeResume = null;
        }
        await _writeResponse(
          response: response,
          source: source,
          etag: etag,
          asset: asset,
          partFile: partFile,
          sidecarFile: sidecarFile,
          initialBytes: 0,
          append: false,
          onProgress: onProgress,
          cancellation: cancellation,
        );
        return;
      } finally {
        opened.client.close(force: true);
      }
    }
  }

  Future<_OpenedResponse> _open(
    Uri source,
    _ResumeState? resume,
    DownloadCancellation cancellation,
  ) async {
    final client = _httpClientFactory()..connectionTimeout = _connectTimeout;
    try {
      cancellation.throwIfCancelled();
      final request = await client.getUrl(_requestUriResolver(source));
      if (resume != null) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${resume.receivedBytes}-',
        );
        request.headers.set(HttpHeaders.ifRangeHeader, resume.etag);
      }
      cancellation.throwIfCancelled();
      return _OpenedResponse(client, await request.close());
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> _writeResponse({
    required HttpClientResponse response,
    required Uri source,
    required String etag,
    required AndroidUpdateAsset asset,
    required File partFile,
    required File sidecarFile,
    required int initialBytes,
    required bool append,
    required void Function(DownloadProgress) onProgress,
    required DownloadCancellation cancellation,
  }) async {
    var receivedBytes = initialBytes;
    await _writeSidecar(
      sidecarFile,
      _ResumeState(
        url: source.toString(),
        etag: etag,
        expectedSize: asset.size,
        receivedBytes: receivedBytes,
      ),
    );
    final sink = partFile.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response) {
        cancellation.throwIfCancelled();
        receivedBytes += chunk.length;
        if (receivedBytes > asset.size) {
          throw const FormatException('Update response exceeded expected size');
        }
        sink.add(chunk);
        await sink.flush();
        await _writeSidecar(
          sidecarFile,
          _ResumeState(
            url: source.toString(),
            etag: etag,
            expectedSize: asset.size,
            receivedBytes: receivedBytes,
          ),
        );
        onProgress(
          DownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: asset.size,
          ),
        );
        cancellation.throwIfCancelled();
      }
      if (receivedBytes != asset.size) {
        throw const FormatException('Update response had an unexpected size');
      }
    } finally {
      await sink.close();
    }
  }
}

Future<_ResumeState?> _readResumeState(
  File partFile,
  File sidecarFile,
  AndroidUpdateAsset asset,
) async {
  if (!await partFile.exists() || !await sidecarFile.exists()) {
    await _deleteIfExists(partFile);
    await _deleteIfExists(sidecarFile);
    return null;
  }
  try {
    final decoded = jsonDecode(await sidecarFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Invalid download sidecar');
    }
    final state = _ResumeState.fromJson(Map<Object?, Object?>.from(decoded));
    if (state.expectedSize != asset.size ||
        state.receivedBytes <= 0 ||
        state.receivedBytes >= asset.size ||
        !asset.urls.map((url) => url.toString()).contains(state.url) ||
        await partFile.length() != state.receivedBytes) {
      throw const FormatException('Invalid download sidecar state');
    }
    return state;
  } on FormatException {
    await _deleteIfExists(partFile);
    await _deleteIfExists(sidecarFile);
    return null;
  }
}

void _validateFullResponse(
  HttpClientResponse response,
  AndroidUpdateAsset asset,
) {
  if (response.contentLength != asset.size) {
    throw const FormatException('Invalid full update response size');
  }
}

void _validatePartialResponse(
  HttpClientResponse response,
  AndroidUpdateAsset asset,
  _ResumeState resume,
) {
  final range = response.headers.value(HttpHeaders.contentRangeHeader);
  final match = range == null ? null : _contentRangePattern.firstMatch(range);
  if (match == null) {
    throw const FormatException('Invalid partial update Content-Range');
  }
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  final total = int.tryParse(match.group(3)!);
  if (start != resume.receivedBytes ||
      end != asset.size - 1 ||
      total != asset.size ||
      response.contentLength != asset.size - resume.receivedBytes) {
    throw const FormatException('Invalid partial update response size');
  }
}

String _requiredStrongEtag(HttpClientResponse response) {
  final etag = response.headers.value(HttpHeaders.etagHeader);
  if (etag == null || !_strongEtagPattern.hasMatch(etag)) {
    throw const FormatException('Invalid update ETag');
  }
  return etag;
}

Future<void> _writeSidecar(File file, _ResumeState state) =>
    file.writeAsString(jsonEncode(state.toJson()), flush: true);

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

String _completedPath(Directory directory, AndroidUpdateAsset asset) =>
    '${directory.path}${Platform.pathSeparator}${asset.fileName}';

String _partPath(Directory directory, AndroidUpdateAsset asset) =>
    '${_completedPath(directory, asset)}.part';

String _sidecarPath(Directory directory, AndroidUpdateAsset asset) =>
    '${_partPath(directory, asset)}.json';

Uri _identityUri(Uri uri) => uri;

final class _OpenedResponse {
  const _OpenedResponse(this.client, this.response);

  final HttpClient client;
  final HttpClientResponse response;
}

final class _ResumeState {
  const _ResumeState({
    required this.url,
    required this.etag,
    required this.expectedSize,
    required this.receivedBytes,
  });

  final String url;
  final String etag;
  final int expectedSize;
  final int receivedBytes;

  factory _ResumeState.fromJson(Map<Object?, Object?> json) {
    final url = json['url'];
    final etag = json['etag'];
    final expectedSize = json['expectedSize'];
    final receivedBytes = json['receivedBytes'];
    if (url is! String ||
        etag is! String ||
        !_strongEtagPattern.hasMatch(etag) ||
        expectedSize is! int ||
        receivedBytes is! int) {
      throw const FormatException('Invalid download sidecar');
    }
    return _ResumeState(
      url: url,
      etag: etag,
      expectedSize: expectedSize,
      receivedBytes: receivedBytes,
    );
  }

  Map<String, Object> toJson() => {
    'url': url,
    'etag': etag,
    'expectedSize': expectedSize,
    'receivedBytes': receivedBytes,
  };
}
