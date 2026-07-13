import 'package:bible_recite/src/features/scripture/presentation/scripture_sources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows pinned offline source and license details', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScriptureSourcesScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('World English Bible'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('World English Bible'), findsOneWidget);
    expect(find.textContaining('Public Domain'), findsWidgets);
    expect(find.textContaining('Semantic SHA-256'), findsWidgets);
  });
}
