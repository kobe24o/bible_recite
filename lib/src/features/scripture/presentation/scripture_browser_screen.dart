import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import 'book_grid.dart';
import 'chapter_grid.dart';
import 'translation_selector.dart';

class ScriptureBrowserScreen extends ConsumerStatefulWidget {
  const ScriptureBrowserScreen({super.key});

  @override
  ConsumerState<ScriptureBrowserScreen> createState() =>
      _ScriptureBrowserScreenState();
}

class _ScriptureBrowserScreenState
    extends ConsumerState<ScriptureBrowserScreen> {
  String? _translationId;
  bool? _newTestament;
  BibleBook? _book;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(scriptureRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.bibleTitle ?? 'Bible'),
      ),
      body: repository.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const _ErrorView(),
        data: (repository) => FutureBuilder(
          future: repository.listTranslations(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final translations = snapshot.data!;
            final translationId = _translationId ?? translations.first.id;
            return FutureBuilder(
              future: repository.listBooks(translationId, CanonId.protestant66),
              builder: (context, booksSnapshot) {
                if (!booksSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allBooks = booksSnapshot.data!;
                final filtered = _newTestament == null
                    ? const <BibleBook>[]
                    : allBooks
                          .where(
                            (book) => _newTestament!
                                ? book.ordinal >= 40
                                : book.ordinal < 40,
                          )
                          .toList(growable: false);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TranslationSelector(
                      translations: translations,
                      value: translationId,
                      onChanged: (value) => setState(() {
                        _translationId = value;
                        _book = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      emptySelectionAllowed: true,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            AppLocalizations.of(context)?.oldTestament ??
                                'Old Testament',
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            AppLocalizations.of(context)?.newTestament ??
                                'New Testament',
                          ),
                        ),
                      ],
                      selected: _newTestament == null ? {} : {_newTestament!},
                      onSelectionChanged: (selection) => setState(() {
                        _newTestament = selection.firstOrNull;
                        _book = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_newTestament != null)
                      BookGrid(
                        books: filtered,
                        onSelected: (book) => setState(() => _book = book),
                      ),
                    if (_book != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        _book!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      ChapterGrid(
                        chapterCount: _book!.chapterCount,
                        onSelected: (chapter) => context.go(
                          '/bible/$translationId/${_book!.osisId}/$chapter',
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      AppLocalizations.of(context)?.unableLoadBible ??
          'Unable to load the Bible',
    ),
  );
}
