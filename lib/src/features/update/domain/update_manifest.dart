import 'dart:convert';

import 'app_version.dart';

const _androidPackageName = 'app.biblerecite';
const _androidSigningCertificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';
final _apkFileNamePattern = RegExp(r'^BibleRecite-.+\.apk$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

final class SignedUpdateEnvelope {
  SignedUpdateEnvelope._({
    required this.protocol,
    required List<int> payloadBytes,
    required List<int> signatureBytes,
  }) : payloadBytes = List.unmodifiable(payloadBytes),
       signatureBytes = List.unmodifiable(signatureBytes);

  final int protocol;
  final List<int> payloadBytes;
  final List<int> signatureBytes;

  factory SignedUpdateEnvelope.decode(List<int> bytes) {
    final envelope = _jsonObject(jsonDecode(utf8.decode(bytes)));
    final protocol = _requiredInt(envelope, 'protocol');
    if (protocol != 1) {
      throw const FormatException('Unsupported update envelope protocol');
    }

    final payloadBytes = _decodeBase64(_requiredString(envelope, 'payload'));
    final signatureBytes = _decodeBase64(
      _requiredString(envelope, 'signature'),
    );
    if (payloadBytes.isEmpty || signatureBytes.length != 64) {
      throw const FormatException('Invalid signed update envelope');
    }

    return SignedUpdateEnvelope._(
      protocol: protocol,
      payloadBytes: payloadBytes,
      signatureBytes: signatureBytes,
    );
  }
}

final class UpdateManifest {
  const UpdateManifest._({
    required this.version,
    required this.sourceCommit,
    required this.publishedAt,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.android,
  });

  final AppVersion version;
  final String sourceCommit;
  final DateTime publishedAt;
  final String releaseNotes;
  final Uri releasePageUrl;
  final AndroidUpdateAsset android;

  factory UpdateManifest.fromPayloadBytes(List<int> bytes) {
    final payload = _jsonObject(jsonDecode(utf8.decode(bytes)));
    final publishedAt = DateTime.tryParse(
      _requiredString(payload, 'publishedAt'),
    );
    if (publishedAt == null) {
      throw const FormatException('Invalid update publication timestamp');
    }

    return UpdateManifest._(
      version: AppVersion.parse(
        _requiredString(payload, 'versionName'),
        _requiredString(payload, 'buildNumber'),
      ),
      sourceCommit: _requiredString(payload, 'sourceCommit'),
      publishedAt: publishedAt,
      releaseNotes: _requiredString(payload, 'releaseNotes', allowEmpty: true),
      releasePageUrl: _httpsUri(_requiredString(payload, 'releasePageUrl')),
      android: AndroidUpdateAsset._fromJson(
        _jsonObject(_requiredValue(payload, 'android')),
      ),
    );
  }
}

final class AndroidUpdateAsset {
  AndroidUpdateAsset._({
    required this.packageName,
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.signingCertificateSha256,
    required List<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  final String packageName;
  final String fileName;
  final int size;
  final String sha256;
  final String signingCertificateSha256;
  final List<Uri> urls;

  factory AndroidUpdateAsset._fromJson(Map<String, Object?> json) {
    final packageName = _requiredString(json, 'packageName');
    final fileName = _requiredString(json, 'fileName');
    final size = _requiredInt(json, 'size');
    final sha256 = _requiredString(json, 'sha256');
    final signingCertificateSha256 = _requiredString(
      json,
      'signingCertificateSha256',
    );
    final urls = _httpsUrls(_requiredValue(json, 'urls'));

    if (packageName != _androidPackageName ||
        !_apkFileNamePattern.hasMatch(fileName) ||
        size < 0 ||
        !_sha256Pattern.hasMatch(sha256) ||
        signingCertificateSha256 != _androidSigningCertificateSha256) {
      throw const FormatException('Invalid Android update asset');
    }

    return AndroidUpdateAsset._(
      packageName: packageName,
      fileName: fileName,
      size: size,
      sha256: sha256,
      signingCertificateSha256: signingCertificateSha256,
      urls: urls,
    );
  }
}

Map<String, Object?> _jsonObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a JSON object');
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('JSON object keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Object? _requiredValue(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing update manifest field: $key');
  }
  return json[key];
}

String _requiredString(
  Map<String, Object?> json,
  String key, {
  bool allowEmpty = false,
}) {
  final value = _requiredValue(json, key);
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException('Invalid update manifest field: $key');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = _requiredValue(json, key);
  if (value is! int) {
    throw FormatException('Invalid update manifest field: $key');
  }
  return value;
}

List<int> _decodeBase64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    throw const FormatException('Invalid Base64 update envelope field');
  }
}

Uri _httpsUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('Update URLs must use HTTPS');
  }
  return uri;
}

List<Uri> _httpsUrls(Object? value) {
  if (value is! List || value.isEmpty || value.length > 2) {
    throw const FormatException('Invalid Android update URLs');
  }
  return [
    for (final url in value)
      if (url is String)
        _httpsUri(url)
      else
        throw const FormatException('Invalid Android update URL'),
  ];
}
