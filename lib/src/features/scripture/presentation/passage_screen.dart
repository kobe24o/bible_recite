import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import '../domain/scripture_repository.dart';

class PassageScreen extends ConsumerStatefulWidget {
  const PassageScreen({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    super.key,
  });

  final String translationId;
  final String bookId;
  final int chapter;

  @override
  ConsumerState<PassageScreen> createState() => _PassageScreenState();
}

class _PassageScreenState extends ConsumerState<PassageScreen> {
  String? _parallelTranslationId;

  Future<_PassageData> _load(ScriptureRepository repository) async {
    final translations = await repository.listTranslations();
    final units = await repository.getChapter(
      widget.translationId,
      widget.bookId,
      widget.chapter,
    );
    ParallelPassage? parallel;
    if (_parallelTranslationId != null && units.isNotEmpty) {
      parallel = await repository.resolveParallelPassage(
        LocatedPassageRange(
          translationId: widget.translationId,
          range: PassageRange(start: units.first.start, end: units.last.end),
        ),
        _parallelTranslationId!,
      );
    }
    return _PassageData(
      translations: translations,
      units: units,
      parallel: parallel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(scriptureRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.bookId} ${widget.chapter}')),
      body: repository.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            AppLocalizations.of(context)?.unableLoadPassage ??
                'Unable to load the passage',
          ),
        ),
        data: (repository) => FutureBuilder<_PassageData>(
          future: _load(repository),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: const Key('parallel-translation-selector'),
                          initialValue: _parallelTranslationId,
                          decoration: const InputDecoration(
                            labelText: 'Parallel translation',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Single translation'),
                            ),
                            for (final translation in data.translations)
                              if (translation.id != widget.translationId)
                                DropdownMenuItem(
                                  value: translation.id,
                                  child: Text(translation.name),
                                ),
                          ],
                          onChanged: (value) =>
                              setState(() => _parallelTranslationId = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Scripture sources',
                        onPressed: () => GoRouter.maybeOf(
                          context,
                        )?.push('/about/scripture-sources'),
                        icon: const Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: data.parallel == null
                      ? _SinglePassage(units: data.units)
                      : _ParallelPassageView(passage: data.parallel!),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SinglePassage extends StatelessWidget {
  const _SinglePassage({required this.units});
  final List<VerseUnit> units;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: units.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _VerseRow(unit: units[index]),
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({required this.unit});
  final VerseUnit unit;

  @override
  Widget build(BuildContext context) {
    final label = unit.start.verse == unit.end.verse
        ? '${unit.start.verse}'
        : '${unit.start.verse}–${unit.end.verse}';
    return Semantics(
      label:
          '${unit.translationId} ${unit.start.osisBookId} '
          '${unit.start.chapter}:$label',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Text(
              unit.status == SourceTextStatus.omitted
                  ? AppLocalizations.of(context)?.omittedVerse ??
                        'This verse is omitted in this translation.'
                  : unit.text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParallelPassageView extends StatelessWidget {
  const _ParallelPassageView({required this.passage});
  final ParallelPassage passage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: passage.groups.length,
      separatorBuilder: (context, index) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final group = passage.groups[index];
        return Semantics(
          label: '${group.relation.name}; ${group.provenance}',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final source = _UnitColumn(units: group.sourceUnits);
              final target = _UnitColumn(units: group.targetUnits);
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [source, const SizedBox(height: 12), target],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: source),
                  const VerticalDivider(),
                  Expanded(child: target),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _UnitColumn extends StatelessWidget {
  const _UnitColumn({required this.units});
  final List<VerseUnit> units;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return const Text('No counterpart in this translation');
    }
    return Column(children: [for (final unit in units) _VerseRow(unit: unit)]);
  }
}

final class _PassageData {
  const _PassageData({
    required this.translations,
    required this.units,
    required this.parallel,
  });

  final List<TranslationInfo> translations;
  final List<VerseUnit> units;
  final ParallelPassage? parallel;
}
