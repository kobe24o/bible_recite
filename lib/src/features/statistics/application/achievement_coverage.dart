import 'package:flutter/widgets.dart';

import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/data/sqlite_scripture_repository.dart';
import '../../scripture/domain/book_name_catalog.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../domain/achievement.dart';
import '../domain/achievement_engine.dart';

Future<ExternalAchievementSyncResult> syncScriptureCoverageAchievements({
  required SqlitePlanRepository repository,
  required ScriptureRepository scripture,
  required BookNameCatalog names,
}) async {
  final metrics = await repository.listRecitationVerseMetrics();
  if (metrics.isEmpty) {
    return const ExternalAchievementSyncResult(progress: [], unlocked: []);
  }

  final books = await scripture.listBooks('cmn-cu89s', CanonId.protestant66);
  final chapterTotals = scripture is SqliteScriptureRepository
      ? await scripture.getChapterVerseCounts('cmn-cu89s')
      : <String, int>{
          for (final book in books)
            for (var chapter = 1; chapter <= book.chapterCount; chapter++)
              '${book.osisId}:$chapter': (await scripture.getChapter(
                'cmn-cu89s',
                book.osisId,
                chapter,
              )).length,
        };
  final verseCounts = <String, int>{
    for (final item in metrics)
      if (item.translationId == 'cmn-cu89s')
        '${item.bookId}:${item.chapter}:${item.verse}': item.sessions,
  };
  final definitions = <AchievementDefinition>[];
  final satisfied = <String>{};
  final currentValues = <String, double>{};
  final oldVerseCounts = <int>[];
  final newVerseCounts = <int>[];

  for (final book in books) {
    final id = 'book_complete_${book.osisId}';
    final bookName = names.nameFor(book.osisId, const Locale('zh', 'CN'));
    definitions.add(
      AchievementDefinition(
        id: id,
        title: '$bookName勋章',
        description: '完成$bookName全部经文',
        metric: AchievementMetric.sessions,
        target: 1,
        repeatable: true,
      ),
    );
    final bookVerseCounts = <int>[];
    for (var chapter = 1; chapter <= book.chapterCount; chapter++) {
      final key = '${book.osisId}:$chapter';
      final total = chapterTotals[key] ?? 0;
      for (var verse = 1; verse <= total; verse++) {
        bookVerseCounts.add(verseCounts['$key:$verse'] ?? 0);
      }
    }
    final progress = calculateRepeatedAchievementProgress(bookVerseCounts);
    currentValues[id] = progress.progress;
    if (progress.awardCount > 0) satisfied.add(id);
    if (book.ordinal <= 39) {
      oldVerseCounts.addAll(bookVerseCounts);
    } else {
      newVerseCounts.addAll(bookVerseCounts);
    }
  }

  final scopeProgress = <String, RepeatedAchievementProgress>{
    'old_testament_complete': calculateRepeatedAchievementProgress(
      oldVerseCounts,
    ),
    'new_testament_complete': calculateRepeatedAchievementProgress(
      newVerseCounts,
    ),
    'bible_complete': calculateRepeatedAchievementProgress([
      ...oldVerseCounts,
      ...newVerseCounts,
    ]),
  };
  for (final entry in <({String id, String title, String description})>[
    (id: 'old_testament_complete', title: '旧约勋章', description: '完成旧约全部经文'),
    (id: 'new_testament_complete', title: '新约勋章', description: '完成新约全部经文'),
    (id: 'bible_complete', title: '圣经勋章', description: '完成整本圣经全部经文'),
  ]) {
    final definition = AchievementDefinition(
      id: entry.id,
      title: entry.title,
      description: entry.description,
      metric: AchievementMetric.sessions,
      target: 1,
      repeatable: true,
    );
    definitions.add(definition);
    final progress = scopeProgress[entry.id]!;
    currentValues[entry.id] = progress.progress;
    if (progress.awardCount > 0) satisfied.add(entry.id);
  }

  return repository.syncExternalAchievementsWithUnlocks(
    definitions,
    satisfied,
    currentValues,
  );
}
