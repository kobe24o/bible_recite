import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/source_fetcher.dart';

void main() {
  test('does not keep a source archive when sha256 differs', () async {
    final directory = await Directory.systemTemp.createTemp('source-fetcher-');
    addTearDown(() => directory.delete(recursive: true));
    final fetcher = SourceFetcher(
      download: (_) async => Uint8List.fromList([1, 2, 3]),
    );
    final source = SourceDescriptor(
      id: 'fixture',
      archiveUrl: Uri.parse('https://example.invalid/source.zip'),
      sha256: List.filled(64, '0').join(),
    );

    await expectLater(
      fetcher.fetch(source, directory),
      throwsA(isA<SourceIntegrityException>()),
    );

    expect(File('${directory.path}/fixture_vpl.zip').existsSync(), isFalse);
    expect(
      File('${directory.path}/fixture_vpl.zip.partial').existsSync(),
      isFalse,
    );
  });

  test('publishes verified bytes under the source identifier', () async {
    final directory = await Directory.systemTemp.createTemp('source-fetcher-');
    addTearDown(() => directory.delete(recursive: true));
    final fetcher = SourceFetcher(
      download: (_) async => Uint8List.fromList([1, 2, 3]),
    );
    final source = SourceDescriptor(
      id: 'fixture',
      archiveUrl: Uri.parse('https://example.invalid/source.zip'),
      sha256:
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );

    final archive = await fetcher.fetch(source, directory);

    expect(await archive.readAsBytes(), [1, 2, 3]);
    expect(archive.path, endsWith('fixture_vpl.zip'));
  });

  test('rejects a source identifier that could escape the cache', () {
    expect(
      () => SourceDescriptor(
        id: '../escape',
        archiveUrl: Uri.parse('https://example.invalid/source.zip'),
        sha256: List.filled(64, '0').join(),
      ),
      throwsArgumentError,
    );
  });

  test('loads the three pinned source revisions from the catalog', () async {
    final catalog = await SourceCatalog.load(
      File('tool/scripture_pack/source_catalog.json'),
    );

    expect(catalog.sources.map((source) => source.id), [
      'cmn-cu89s',
      'cmn-cu89t',
      'eng-web',
    ]);
    expect(catalog.sources.first.languageTag, 'zh-Hans');
    expect(catalog.sources.last.name, 'World English Bible');
    expect(
      catalog.sources.every((source) => source.licenseId == 'public-domain'),
      isTrue,
    );
  });
}
