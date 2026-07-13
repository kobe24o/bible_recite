import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/generated/app_localizations.dart';

class ScriptureSourcesScreen extends StatelessWidget {
  const ScriptureSourcesScreen({super.key});

  Future<List<_SourceDetails>> _load() async {
    final result = <_SourceDetails>[];
    for (final id in ['cmn-cu89s', 'cmn-cu89t', 'eng-web']) {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/scripture/$id/manifest.json',
                ),
              )
              as Map<String, Object?>;
      final translation = manifest['translation']! as Map<String, Object?>;
      final source = manifest['source']! as Map<String, Object?>;
      result.add(
        _SourceDetails(
          name: translation['name']! as String,
          sourceUrl: source['detailsUrl']! as String,
          archiveSha256: source['archiveSha256']! as String,
          semanticSha256: manifest['semanticSha256']! as String,
          retrievalDate: source['retrievalDate']! as String,
          license: await rootBundle.loadString(
            'assets/scripture/$id/LICENSE.txt',
          ),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)?.scriptureSources ?? 'Scripture sources',
        ),
      ),
      body: FutureBuilder<List<_SourceDetails>>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final source = snapshot.data![index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SelectableText('Source: ${source.sourceUrl}'),
                      SelectableText(
                        'Archive SHA-256: ${source.archiveSha256}',
                      ),
                      SelectableText(
                        'Semantic SHA-256: ${source.semanticSha256}',
                      ),
                      SelectableText('Retrieved: ${source.retrievalDate}'),
                      const Divider(height: 24),
                      SelectableText(source.license),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final class _SourceDetails {
  const _SourceDetails({
    required this.name,
    required this.sourceUrl,
    required this.archiveSha256,
    required this.semanticSha256,
    required this.retrievalDate,
    required this.license,
  });

  final String name;
  final String sourceUrl;
  final String archiveSha256;
  final String semanticSha256;
  final String retrievalDate;
  final String license;
}
