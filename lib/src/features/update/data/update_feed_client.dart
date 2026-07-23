import 'package:cryptography/cryptography.dart';

import '../domain/update_manifest.dart';

abstract interface class UpdateBytesTransport {
  Future<List<int>> get(Uri uri);
}

const updateFeedFallbacks = [
  'https://raw.githubusercontent.com/kobe24o/bible_recite/update-feed/updates/latest.json',
  'https://fastly.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
  'https://cdn.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
  'https://gcore.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
];

List<Uri> buildUpdateFeedSources({Uri? r2PublicBaseUrl}) {
  if (r2PublicBaseUrl == null) {
    return List.unmodifiable([
      for (final fallback in updateFeedFallbacks) Uri.parse(fallback),
    ]);
  }
  if (r2PublicBaseUrl.scheme != 'https' || r2PublicBaseUrl.host.isEmpty) {
    throw ArgumentError.value(
      r2PublicBaseUrl,
      'r2PublicBaseUrl',
      'The R2 public base URL must use HTTPS and include a host.',
    );
  }

  final r2Feed = Uri(
    scheme: r2PublicBaseUrl.scheme,
    userInfo: r2PublicBaseUrl.userInfo,
    host: r2PublicBaseUrl.host,
    port: r2PublicBaseUrl.hasPort ? r2PublicBaseUrl.port : null,
    pathSegments: [
      ...r2PublicBaseUrl.pathSegments.where((segment) => segment.isNotEmpty),
      'updates',
      'latest.json',
    ],
  );

  return List.unmodifiable([
    r2Feed,
    for (final fallback in updateFeedFallbacks) Uri.parse(fallback),
  ]);
}

final class UpdateFeedClient {
  const UpdateFeedClient({
    required this.sources,
    required this.transport,
    required this.publicKey,
  });

  final List<Uri> sources;
  final UpdateBytesTransport transport;
  final SimplePublicKey publicKey;

  Future<UpdateManifest> fetchLatest() async {
    final failures = <String>[];
    UpdateManifest? newest;
    for (final source in sources) {
      try {
        final envelope = SignedUpdateEnvelope.decode(
          await transport.get(source),
        );
        final valid = await Ed25519().verify(
          envelope.payloadBytes,
          signature: Signature(envelope.signatureBytes, publicKey: publicKey),
        );
        if (!valid) {
          throw const FormatException('Invalid update signature');
        }
        final manifest = UpdateManifest.fromPayloadBytes(envelope.payloadBytes);
        if (newest == null || manifest.version.isNewerThan(newest.version)) {
          newest = manifest;
        }
      } catch (error) {
        failures.add('${source.host}: $error');
      }
    }
    if (newest != null) return newest;
    throw UpdateFeedException(List.unmodifiable(failures));
  }
}

final class UpdateFeedException implements Exception {
  UpdateFeedException(List<String> failures)
    : failures = List.unmodifiable(failures);

  final List<String> failures;

  @override
  String toString() => 'UpdateFeedException: ${failures.join('; ')}';
}
