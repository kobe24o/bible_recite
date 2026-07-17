import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/presentation/passage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scripture_browser_screen_test.dart' show FakeRepositoryForPassage;

void main() {
  testWidgets('renders a local chapter without network access', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: [Locale('zh'), Locale('en')],
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3章'), findsOneWidget);
    expect(find.text('JHN 3'), findsNothing);
    expect(find.text('开始背诵'), findsOneWidget);
    expect(find.text('加入计划'), findsOneWidget);
    expect(find.textContaining('For God so loved the world'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-to-plan-button')));
    await tester.pumpAndSettle();
    expect(find.text('加入背诵计划'), findsOneWidget);
    expect(find.text('新建计划'), findsOneWidget);
    await tester.tap(find.text('新建计划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑背诵计划'), findsOneWidget);
    expect(find.text('约翰福音 3章'), findsWidgets);
  });
}
