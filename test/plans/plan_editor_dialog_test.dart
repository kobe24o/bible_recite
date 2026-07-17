import 'package:bible_recite/src/features/plans/presentation/plan_editor_dialog.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits title chapters and inclusive plan dates', (tester) async {
    PlanEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<PlanEditorResult>(
                  context: context,
                  builder: (_) => PlanEditorDialog(
                    books: [
                      BibleBook(
                        osisId: 'JHN',
                        ordinal: 43,
                        name: '约翰福音',
                        chapterCount: 21,
                      ),
                    ],
                    initial: PlanEditorDraft(
                      title: '旧计划',
                      translationId: 'cmn-cu89s',
                      bookId: 'JHN',
                      startChapter: 1,
                      endChapter: 3,
                      startDate: DateTime(2026, 7, 15),
                      endDate: DateTime(2026, 7, 31),
                    ),
                    allowDelete: true,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('编辑背诵计划'), findsOneWidget);
    expect(find.byKey(const Key('plan-start-date')), findsOneWidget);
    expect(find.byKey(const Key('plan-end-date')), findsOneWidget);
    expect(find.byKey(const Key('plan-translation')), findsOneWidget);
    expect(find.byKey(const Key('delete-plan-button')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('plan-title')), '新计划');
    await tester.enterText(find.byKey(const Key('start-chapter')), '2');
    await tester.enterText(find.byKey(const Key('end-chapter')), '4');
    await tester.tap(find.byKey(const Key('save-plan-button')));
    await tester.pumpAndSettle();

    expect(result?.delete, isFalse);
    expect(result?.draft?.title, '新计划');
    expect(result?.draft?.startChapter, 2);
    expect(result?.draft?.endChapter, 4);
    expect(result?.draft?.days, 17);
  });
}
