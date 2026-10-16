import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_recite/src/features/plans/presentation/plans_screen.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
  testWidgets(
    'new passage defaults to first verse and final chapter final verse',
    (tester) async {
      final scripture = FakeRepositoryForPassage(
        chapterUnitsByReference: {
          'EXO:40': [
            for (var verse = 1; verse <= 5; verse++)
              VerseUnit(
                translationId: 'eng-web',
                start: (
                  canonId: CanonId.protestant66,
                  osisBookId: 'EXO',
                  chapter: 40,
                  verse: verse,
                ),
                end: (
                  canonId: CanonId.protestant66,
                  osisBookId: 'EXO',
                  chapter: 40,
                  verse: verse,
                ),
                text: 'verse',
                status: SourceTextStatus.present,
              ),
          ],
        },
        chapterUnits: [
          for (var verse = 1; verse <= 3; verse++)
            VerseUnit(
              translationId: 'eng-web',
              start: (
                canonId: CanonId.protestant66,
                osisBookId: 'JHN',
                chapter: 1,
                verse: verse,
              ),
              end: (
                canonId: CanonId.protestant66,
                osisBookId: 'JHN',
                chapter: 1,
                verse: verse,
              ),
              text: 'verse',
              status: SourceTextStatus.present,
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanPassagePickerDialog(
              books: [
                BibleBook(
                  osisId: 'JHN',
                  ordinal: 43,
                  name: 'John',
                  chapterCount: 21,
                ),
                BibleBook(
                  osisId: 'EXO',
                  ordinal: 44,
                  name: 'Exodus',
                  chapterCount: 40,
                ),
              ],
              scripture: scripture,
              translationId: 'eng-web',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .toList();
      expect(fields.map((field) => field.initialValue).toList(), [1, 1, 21, 3]);
      final bookFields = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      bookFields.last.onChanged!('EXO');
      await tester.pumpAndSettle();
      final updated = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .toList();
      expect(updated.map((field) => field.initialValue).toList(), [
        1,
        1,
        40,
        5,
      ]);
    },
  );
}
