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
  String get navStatistics => 'Statistics';

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
}
