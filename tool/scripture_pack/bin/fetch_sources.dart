import 'dart:io';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/source_fetcher.dart';

Future<void> main() async {
  final root = Directory.current;
  final catalog = await SourceCatalog.load(
    File(
      '${root.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}scripture_pack'
      '${Platform.pathSeparator}source_catalog.json',
    ),
  );
  final cache = Directory(
    '${root.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}scripture_pack'
    '${Platform.pathSeparator}.cache',
  );
  final fetcher = SourceFetcher();

  for (final source in catalog.sources) {
    final archive = await fetcher.fetch(source, cache);
    stdout.writeln('${source.id} ${source.sha256} ${archive.path}');
  }
}
