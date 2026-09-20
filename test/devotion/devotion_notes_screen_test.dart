import 'dart:convert';

import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/devotion/presentation/devotion_notes_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'devotion_models_test.dart' show complete2026Json;

void main() {
  late SqlitePlanRepository repository;

  setUp(() async {
    repository = SqlitePlanRepository(sqlite3.openInMemory());
    final manifest = jsonDecode(complete2026Json) as Map<String, dynamic>;
    await repository.cacheDevotionManifest(jsonEncode(manifest));
    await repository.saveDevotionNote(DateTime(2026, 9, 17), '较早的领受');
    await repository.saveDevotionNote(DateTime(2026, 9, 19), '后来写下的领受');
  });

  tearDown(() => repository.close());

  testWidgets('calendar marks written notes and opens their date content', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DevotionNotesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('灵修笔记'), findsOneWidget);
    expect(find.text('2026年9月'), findsOneWidget);
    expect(
      find.byKey(const Key('devotion-note-dot-2026-09-17')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('devotion-note-dot-2026-09-19')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('devotion-note-day-2026-09-17')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('较早的领受'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('较早的领受'), findsOneWidget);
    expect(find.text('以斯拉记 1:1–11'), findsWidgets);
  });
}
