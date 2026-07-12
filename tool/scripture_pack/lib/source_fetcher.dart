import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

typedef SourceDownload = Future<Uint8List> Function(Uri uri);

final class SourceDescriptor {
  SourceDescriptor({
    required this.id,
    required this.archiveUrl,
    required this.sha256,
    this.name = '',
    this.languageTag = '',
    this.detailsUrl,
    this.licenseId = '',
  }) {
    if (!_sourceIdPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid source identifier');
    }
    if (archiveUrl.scheme != 'https' || !archiveUrl.hasAuthority) {
      throw ArgumentError.value(
        archiveUrl,
        'archiveUrl',
        'Source URL must be absolute HTTPS',
      );
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw ArgumentError.value(sha256, 'sha256', 'Invalid SHA-256');
    }
    if (detailsUrl != null &&
        (detailsUrl!.scheme != 'https' || !detailsUrl!.hasAuthority)) {
      throw ArgumentError.value(
        detailsUrl,
        'detailsUrl',
        'Details URL must be absolute HTTPS',
      );
    }
  }

  final String id;
  final Uri archiveUrl;
  final String sha256;
  final String name;
  final String languageTag;
  final Uri? detailsUrl;
  final String licenseId;

  factory SourceDescriptor.fromJson(Map<String, Object?> json) {
    final descriptor = SourceDescriptor(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      languageTag: _requiredString(json, 'languageTag'),
      detailsUrl: Uri.parse(_requiredString(json, 'detailsUrl')),
      archiveUrl: Uri.parse(_requiredString(json, 'archiveUrl')),
      sha256: _requiredString(json, 'sha256'),
      licenseId: _requiredString(json, 'licenseId'),
    );
    if (descriptor.name.isEmpty ||
        descriptor.languageTag.isEmpty ||
        descriptor.licenseId.isEmpty) {
      throw const FormatException('Source metadata must not be empty');
    }
    return descriptor;
  }
}

final class SourceCatalog {
  SourceCatalog(List<SourceDescriptor> sources)
    : sources = List.unmodifiable(sources) {
    if (this.sources.isEmpty) {
      throw const FormatException('Source catalog must not be empty');
    }
    final ids = this.sources.map((source) => source.id).toSet();
    if (ids.length != this.sources.length) {
      throw const FormatException('Source identifiers must be unique');
    }
  }

  final List<SourceDescriptor> sources;

  static Future<SourceCatalog> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Source catalog root must be an object');
    }
    final sources = decoded['sources'];
    if (sources is! List<Object?>) {
      throw const FormatException('Source catalog sources must be a list');
    }
    return SourceCatalog(
      sources
          .map((source) {
            if (source is! Map<String, Object?>) {
              throw const FormatException('Source entry must be an object');
            }
            return SourceDescriptor.fromJson(source);
          })
          .toList(growable: false),
    );
  }
}

final class SourceIntegrityException implements Exception {
  const SourceIntegrityException({
    required this.sourceId,
    required this.expected,
    required this.actual,
  });

  final String sourceId;
  final String expected;
  final String actual;

  @override
  String toString() {
    return 'SourceIntegrityException($sourceId, expected: $expected, '
        'actual: $actual)';
  }
}

final class SourceFetcher {
  SourceFetcher({SourceDownload? download})
    : _download = download ?? _downloadHttp;

  final SourceDownload _download;

  Future<File> fetch(SourceDescriptor source, Directory cache) async {
    await cache.create(recursive: true);
    final target = File(
      '${cache.path}${Platform.pathSeparator}${source.id}_vpl.zip',
    );
    if (await target.exists() &&
        await _sha256OfStream(target.openRead()) == source.sha256) {
      return target;
    }

    final bytes = await _download(source.archiveUrl);
    final actual = await _sha256OfBytes(bytes);
    if (actual != source.sha256) {
      throw SourceIntegrityException(
        sourceId: source.id,
        expected: source.sha256,
        actual: actual,
      );
    }

    final temporary = File('${target.path}.partial');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      return await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  static Future<Uint8List> _downloadHttp(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close(force: true);
    }
  }
}

Future<String> _sha256OfBytes(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return _hex(hash.bytes);
}

Future<String> _sha256OfStream(Stream<List<int>> stream) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in stream) {
    sink.add(chunk);
  }
  sink.close();
  final hash = await sink.hash();
  return _hex(hash.bytes);
}

String _hex(List<int> bytes) {
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

final _sourceIdPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Source field "$key" must be a nonempty string');
  }
  return value;
}
