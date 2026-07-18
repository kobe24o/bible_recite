import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/update/data/resumable_downloader.dart';
import 'package:bible_recite/src/features/update/data/update_verifier.dart';
import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _certificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';

void main() {
  late Directory directory;
  late HttpServer server;
  late Uri serverBaseUri;
  late _RequestHandler handler;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('apk-downloader-test-');
    handler = _RequestHandler();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverBaseUri = Uri.parse(
      'http://${server.address.address}:${server.port}',
    );
    server.listen(handler.handle);
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  ResumableDownloader downloader() => ResumableDownloader.forTesting(
    requestUriResolver: (uri) => serverBaseUri.replace(path: uri.path),
  );

  test('downloads a complete 200 response without buffering the APK', () async {
    final payload = utf8.encode('complete APK payload');
    final asset = await _asset(payload, const ['/download']);
    final progress = <DownloadProgress>[];
    handler.routes['/download'] = (request) async {
      _send(request.response, HttpStatus.ok, payload, etag: '"v1"');
    };

    final result = await downloader().download(
      asset,
      directory,
      onProgress: progress.add,
      cancellation: DownloadCancellation(),
    );

    expect(await result.file.readAsBytes(), payload);
    expect(progress.last.receivedBytes, payload.length);
    expect(progress.last.totalBytes, payload.length);
    expect(await _partFile(directory, asset).exists(), isFalse);
    expect(await _sidecarFile(directory, asset).exists(), isFalse);
  });

  test('resumes a 206 response at the persisted byte range', () async {
    final payload = utf8.encode('resumable APK payload');
    final asset = await _asset(payload, const ['/resume']);
    final split = 7;
    await _partFile(
      directory,
      asset,
    ).writeAsBytes(payload.take(split).toList());
    await _sidecarFile(directory, asset).writeAsString(
      jsonEncode({
        'url': asset.urls.single.toString(),
        'etag': '"v1"',
        'expectedSize': payload.length,
        'receivedBytes': split,
      }),
    );
    handler.routes['/resume'] = (request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=$split-');
      _send(
        request.response,
        HttpStatus.partialContent,
        payload.sublist(split),
        etag: '"v1"',
        contentRange: 'bytes $split-${payload.length - 1}/${payload.length}',
      );
    };

    final result = await downloader().download(
      asset,
      directory,
      onProgress: (_) {},
      cancellation: DownloadCancellation(),
    );

    expect(await result.file.readAsBytes(), payload);
  });

  test('restarts from zero when a resumed response changes its ETag', () async {
    final payload = utf8.encode('new immutable APK bytes');
    final asset = await _asset(payload, const ['/changed-etag']);
    const split = 3;
    await _partFile(directory, asset).writeAsBytes(utf8.encode('old'));
    await _sidecarFile(directory, asset).writeAsString(
      jsonEncode({
        'url': asset.urls.single.toString(),
        'etag': '"old"',
        'expectedSize': payload.length,
        'receivedBytes': split,
      }),
    );
    var requests = 0;
    handler.routes['/changed-etag'] = (request) async {
      requests++;
      if (requests == 1) {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=$split-');
        _send(
          request.response,
          HttpStatus.partialContent,
          payload.sublist(split),
          etag: '"new"',
          contentRange: 'bytes $split-${payload.length - 1}/${payload.length}',
        );
        return;
      }
      expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
      _send(request.response, HttpStatus.ok, payload, etag: '"new"');
    };

    final result = await downloader().download(
      asset,
      directory,
      onProgress: (_) {},
      cancellation: DownloadCancellation(),
    );

    expect(requests, 2);
    expect(await result.file.readAsBytes(), payload);
  });

  test('falls back from an R2 failure to the GitHub release URL', () async {
    final payload = utf8.encode('fallback APK payload');
    final asset = await _asset(payload, const ['/r2', '/github-release']);
    handler.routes['/r2'] = (request) async {
      _send(request.response, HttpStatus.internalServerError, const []);
    };
    handler.routes['/github-release'] = (request) async {
      _send(request.response, HttpStatus.ok, payload, etag: '"v1"');
    };

    final result = await downloader().download(
      asset,
      directory,
      onProgress: (_) {},
      cancellation: DownloadCancellation(),
    );

    expect(await result.file.readAsBytes(), payload);
    expect(handler.paths, ['/r2', '/github-release']);
  });

  test(
    'keeps a partial download and sidecar when cancellation is requested',
    () async {
      final payload = List<int>.generate(1024, (index) => index % 251);
      final asset = await _asset(payload, const ['/cancel']);
      final cancellation = DownloadCancellation();
      handler.routes['/cancel'] = (request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers
          ..set(HttpHeaders.etagHeader, '"v1"')
          ..contentLength = payload.length;
        request.response.add(payload.sublist(0, 256));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        request.response.add(payload.sublist(256));
        await request.response.close();
      };

      await expectLater(
        downloader().download(
          asset,
          directory,
          onProgress: (progress) {
            if (progress.receivedBytes > 0) {
              cancellation.cancel();
            }
          },
          cancellation: cancellation,
        ),
        throwsA(isA<DownloadCancelled>()),
      );

      expect(await _partFile(directory, asset).length(), greaterThan(0));
      expect(await _sidecarFile(directory, asset).exists(), isTrue);
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}${asset.fileName}',
        ).exists(),
        isFalse,
      );
    },
  );

  test('cancels promptly while response headers are stalled', () async {
    final payload = utf8.encode('stalled response payload');
    final asset = await _asset(payload, const [
      '/stalled-headers',
      '/fallback',
    ]);
    final requestStarted = Completer<void>();
    final releaseServer = Completer<void>();
    handler.routes['/stalled-headers'] = (request) async {
      requestStarted.complete();
      await releaseServer.future;
      await request.response.close();
    };
    handler.routes['/fallback'] = (request) async {
      _send(request.response, HttpStatus.ok, payload, etag: '"fallback"');
    };
    final cancellation = DownloadCancellation();
    final pending = downloader().download(
      asset,
      directory,
      onProgress: (_) {},
      cancellation: cancellation,
    );

    await requestStarted.future.timeout(const Duration(seconds: 1));
    cancellation.cancel();

    await expectLater(
      pending.timeout(const Duration(seconds: 1)),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(handler.paths, ['/stalled-headers']);
    releaseServer.complete();
  });

  test(
    'cancels promptly while an otherwise idle body stream is open',
    () async {
      final payload = utf8.encode('stalled body payload');
      final asset = await _asset(payload, const ['/stalled-body', '/fallback']);
      final bodyIsIdle = Completer<void>();
      final releaseServer = Completer<void>();
      handler.routes['/stalled-body'] = (request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers
          ..set(HttpHeaders.etagHeader, '"v1"')
          ..contentLength = payload.length;
        await request.response.flush();
        bodyIsIdle.complete();
        await releaseServer.future;
        request.response.add(payload);
        await request.response.close();
      };
      handler.routes['/fallback'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"fallback"');
      };
      final cancellation = DownloadCancellation();
      final pending = downloader().download(
        asset,
        directory,
        onProgress: (_) {},
        cancellation: cancellation,
      );

      await bodyIsIdle.future.timeout(const Duration(seconds: 1));
      cancellation.cancel();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(handler.paths, ['/stalled-body']);
      releaseServer.complete();
    },
  );

  test(
    'promotes a complete cancelled part without another network request',
    () async {
      final payload = utf8.encode('complete retained part');
      final asset = await _asset(payload, const ['/complete-retained']);
      final cancellation = DownloadCancellation();
      handler.routes['/complete-retained'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"v1"');
      };

      await expectLater(
        downloader().download(
          asset,
          directory,
          onProgress: (_) => cancellation.cancel(),
          cancellation: cancellation,
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(await _partFile(directory, asset).length(), payload.length);

      final promoted = await downloader().download(
        asset,
        directory,
        onProgress: (_) {},
        cancellation: DownloadCancellation(),
      );

      expect(await promoted.file.readAsBytes(), payload);
      expect(handler.paths, ['/complete-retained']);
    },
  );

  test(
    'propagates progress callback errors without trying a fallback source',
    () async {
      final payload = utf8.encode('callback failure payload');
      final asset = await _asset(payload, const ['/callback', '/fallback']);
      handler.routes['/callback'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"v1"');
      };
      handler.routes['/fallback'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"fallback"');
      };

      await expectLater(
        downloader().download(
          asset,
          directory,
          onProgress: (_) => throw StateError('progress callback failed'),
          cancellation: DownloadCancellation(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(handler.paths, ['/callback']);
    },
  );

  test(
    'propagates final APK collisions before making a source request',
    () async {
      final payload = utf8.encode('final collision payload');
      final asset = await _asset(payload, const ['/collision', '/fallback']);
      final finalFile = File(
        '${directory.path}${Platform.pathSeparator}${asset.fileName}',
      );
      await finalFile.writeAsBytes(payload);
      handler.routes['/collision'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"v1"');
      };
      handler.routes['/fallback'] = (request) async {
        _send(request.response, HttpStatus.ok, payload, etag: '"fallback"');
      };

      await expectLater(
        downloader().download(
          asset,
          directory,
          onProgress: (_) {},
          cancellation: DownloadCancellation(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(handler.paths, isEmpty);
    },
  );

  test(
    'rejects a 206 response whose Content-Range starts at the wrong byte',
    () async {
      final payload = utf8.encode('content range guard');
      final asset = await _asset(payload, const ['/bad-range']);
      const split = 4;
      await _partFile(
        directory,
        asset,
      ).writeAsBytes(payload.take(split).toList());
      await _sidecarFile(directory, asset).writeAsString(
        jsonEncode({
          'url': asset.urls.single.toString(),
          'etag': '"v1"',
          'expectedSize': payload.length,
          'receivedBytes': split,
        }),
      );
      handler.routes['/bad-range'] = (request) async {
        _send(
          request.response,
          HttpStatus.partialContent,
          payload.sublist(split),
          etag: '"v1"',
          contentRange:
              'bytes 0-${payload.length - split - 1}/${payload.length}',
        );
      };

      await expectLater(
        downloader().download(
          asset,
          directory,
          onProgress: (_) {},
          cancellation: DownloadCancellation(),
        ),
        throwsA(isA<DownloadException>()),
      );
      expect(await _partFile(directory, asset).exists(), isTrue);
      expect(await _sidecarFile(directory, asset).exists(), isTrue);
    },
  );

  test('verifies the streamed SHA-256 after checking the file size', () async {
    final payload = utf8.encode('verified APK payload');
    final asset = await _asset(payload, const ['/verify']);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${asset.fileName}',
    );
    await file.writeAsBytes(payload);

    await UpdateVerifier().verifyFile(file, asset);

    expect(await file.exists(), isTrue);
  });

  test(
    'deletes final and partial files when SHA-256 verification fails',
    () async {
      final payload = utf8.encode('expected payload');
      final asset = await _asset(payload, const ['/verify-failure']);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${asset.fileName}',
      );
      await file.writeAsBytes(utf8.encode('tampered payload'));
      await _partFile(directory, asset).writeAsBytes(payload.take(2).toList());
      await _sidecarFile(directory, asset).writeAsString('{}');

      await expectLater(
        UpdateVerifier().verifyFile(file, asset),
        throwsA(
          isA<UpdateVerificationException>().having(
            (error) => error.reason,
            'reason',
            'sha256_mismatch',
          ),
        ),
      );
      expect(await file.exists(), isFalse);
      expect(await _partFile(directory, asset).exists(), isFalse);
      expect(await _sidecarFile(directory, asset).exists(), isFalse);
    },
  );
}

Future<AndroidUpdateAsset> _asset(List<int> payload, List<String> paths) async {
  final digest = await Sha256().hash(payload);
  final manifest = UpdateManifest.fromPayloadBytes(
    utf8.encode(
      jsonEncode({
        'versionName': '1.0.5',
        'buildNumber': '6',
        'sourceCommit': '0123456789abcdef',
        'publishedAt': '2026-07-18T12:00:00Z',
        'releaseNotes': '',
        'releasePageUrl':
            'https://github.com/kobe24o/bible_recite/releases/tag/v1.0.5',
        'android': {
          'packageName': 'app.biblerecite',
          'fileName': 'BibleRecite-1.0.5+6.apk',
          'size': payload.length,
          'sha256': _hex(digest.bytes),
          'signingCertificateSha256': _certificateSha256,
          'urls': [
            for (final path in paths) 'https://updates.example.test$path',
          ],
        },
      }),
    ),
  );
  return manifest.android;
}

File _partFile(Directory directory, AndroidUpdateAsset asset) =>
    File('${directory.path}${Platform.pathSeparator}${asset.fileName}.part');

File _sidecarFile(Directory directory, AndroidUpdateAsset asset) => File(
  '${directory.path}${Platform.pathSeparator}${asset.fileName}.part.json',
);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void _send(
  HttpResponse response,
  int status,
  List<int> bytes, {
  String? etag,
  String? contentRange,
}) {
  response.statusCode = status;
  if (etag != null) {
    response.headers.set(HttpHeaders.etagHeader, etag);
  }
  if (contentRange != null) {
    response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
  }
  response.headers.contentLength = bytes.length;
  response.add(bytes);
  response.close();
}

typedef _Route = Future<void> Function(HttpRequest request);

final class _RequestHandler {
  final Map<String, _Route> routes = {};
  final List<String> paths = [];

  Future<void> handle(HttpRequest request) async {
    paths.add(request.uri.path);
    final route = routes[request.uri.path];
    if (route == null) {
      _send(request.response, HttpStatus.notFound, const []);
      return;
    }
    await route(request);
  }
}
