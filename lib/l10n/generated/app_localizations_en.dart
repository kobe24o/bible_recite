// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Scripture Recite';

  @override
  String get navToday => 'Today';

  @override
  String get navBible => 'Bible';

  @override
  String get navPlans => 'Plans';

  @override
  String get navStatistics => 'My';

  @override
  String get bibleTitle => 'Bible';

  @override
  String get translationLabel => 'Translation';

  @override
  String get oldTestament => 'Old Testament';

  @override
  String get newTestament => 'New Testament';

  @override
  String chapterLabel(int chapter) {
    return 'Chapter $chapter';
  }

  @override
  String get unableLoadBible => 'Unable to load the Bible';

  @override
  String get unableLoadPassage => 'Unable to load the passage';

  @override
  String get omittedVerse => 'This verse is omitted in this translation.';

  @override
  String get scriptureSources => 'Scripture sources';

  @override
  String get todayTitle => 'Today\'s tasks';

  @override
  String get todayEmpty =>
      'There are no recitation tasks today. Browse the Bible to choose a passage to memorize.';

  @override
  String get plansTitle => 'Recitation plans';

  @override
  String get plansEmpty =>
      'There are no recitation plans yet. Browse the Bible to choose what you want to memorize.';

  @override
  String get statisticsTitle => 'My';

  @override
  String get statisticsEmpty =>
      'There are no recitation records yet. Your progress will appear here after you practice.';

  @override
  String get browseBible => 'Browse the Bible';

  @override
  String get startRecitation => 'Start recitation';

  @override
  String get addToPlan => 'Add to plan';

  @override
  String get verseMode => 'Verse by verse';

  @override
  String get continuousMode => 'Continuous';

  @override
  String get chooseRecitationMode => 'Choose recitation mode';

  @override
  String get presetPlans => 'Preset plans';

  @override
  String get psalm23Plan => 'Psalm 23';

  @override
  String get matthewSermonPlan => 'Matthew 5–7';

  @override
  String get johnOpeningPlan => 'John 1–3';

  @override
  String get philippiansPlan => 'Philippians';

  @override
  String daysCount(int days) {
    return '$days days';
  }

  @override
  String get customPlan => 'Custom plan';
}
