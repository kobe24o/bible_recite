import 'dart:convert';

import 'package:bible_recite/src/features/scripture/data/scripture_pack_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest digest is stable across LF and CRLF checkouts', () async {
    const lf = '{\n  "schemaVersion": 1\n}\n';
    final crlf = lf.replaceAll('\n', '\r\n');

    expect(
      await canonicalManifestSha256(utf8.encode(crlf)),
      await canonicalManifestSha256(utf8.encode(lf)),
    );
  });
}
