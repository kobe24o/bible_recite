import 'dart:io';

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/scripture/data/sqlite_scripture_repository.dart';
import 'package:bible_recite/src/features/scripture/domain/book_name_catalog.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/statistics/application/achievement_coverage.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _Names implements BookNameCatalog {
  @override
  String nameFor(String id, Locale locale) => id;
  @override
  String chapterLabel(String id, int chapter, Locale locale) => '$id $chapter';
}

void main() {
  test(
    'all recorded Exodus units unlock badge including merged 38:14-15',
    () async {
      final registry = await ScripturePackRegistry.fromDirectories({
        for (final id in ['cmn-cu89s', 'cmn-cu89t', 'eng-web'])
          id: Directory('assets/scripture/$id'),
      });
      final scripture = SqliteScriptureRepository(registry: registry);
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final units = <VerseUnit>[];
      for (var chapter = 1; chapter <= 40; chapter++) {
        units.addAll(await scripture.getChapter('cmn-cu89s', 'EXO', chapter));
      }
      expect(
        units
            .singleWhere((u) => u.start.chapter == 38 && u.start.verse == 14)
            .end
            .verse,
        15,
      );
      Future<void> save(Iterable<VerseUnit> values) async {
        await repository.saveRecitationResult(
          NewRecitationResult(
            translationId: 'cmn-cu89s',
            bookId: 'EXO',
            chapter: 1,
            startVerse: 1,
            endVerse: 22,
            mode: 'continuous',
            durationSeconds: 0,
            correctCount: 1,
            incorrectCount: 0,
            omittedCount: 0,
            reorderedCount: 0,
            accuracy: 1,
            completedAt: DateTime(2026, 10, 21),
            verseMetrics: [
              for (final unit in values)
                NewRecitationVerseMetric(
                  bookId: 'EXO',
                  chapter: unit.start.chapter,
                  verse: unit.start.verse,
                  accuracy: 1,
                  durationSeconds: 0,
                ),
            ],
          ),
        );
      }

      await save(units.take(units.length - 1));
      final incomplete = await syncScriptureCoverageAchievements(
        repository: repository,
        scripture: scripture,
        names: _Names(),
      );
      final locked = incomplete.progress.singleWhere(
        (p) => p.definition.id == 'book_complete_EXO',
      );
      expect(locked.awardCount, 0);
      expect(locked.percentage, 99);
      await save([units.last]);
      final complete = await syncScriptureCoverageAchievements(
        repository: repository,
        scripture: scripture,
        names: _Names(),
      );
      final badge = complete.progress.singleWhere(
        (p) => p.definition.id == 'book_complete_EXO',
      );
      expect(badge.awardCount, 1);
      expect(badge.percentage, 100);
      expect(badge.unlockedAt, isNotNull);
      final again = await syncScriptureCoverageAchievements(
        repository: repository,
        scripture: scripture,
        names: _Names(),
      );
      expect(
        again.unlocked.where((p) => p.definition.id == 'book_complete_EXO'),
        isEmpty,
      );
    },
  );
}
