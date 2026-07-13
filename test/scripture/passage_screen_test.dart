import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/presentation/passage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('For God so loved the world'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
  });
}
