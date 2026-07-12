import 'package:bible_recite/src/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the shell with English navigation labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const BibleReciteApp(locale: Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Bible'), findsOneWidget);
    expect(find.text('Plans'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
  });
}
