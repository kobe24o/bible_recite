// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '圣经背诵';

  @override
  String get navToday => '今日';

  @override
  String get navBible => '圣经';

  @override
  String get navPlans => '计划';

  @override
  String get navStatistics => '统计';

  @override
  String get bibleTitle => '圣经';

  @override
  String get translationLabel => '译本';

  @override
  String get oldTestament => '旧约';

  @override
  String get newTestament => '新约';

  @override
  String chapterLabel(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String get unableLoadBible => '无法载入圣经';

  @override
  String get unableLoadPassage => '无法载入经文';

  @override
  String get omittedVerse => '本译本省略此节。';

  @override
  String get scriptureSources => '经文来源';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => '聖經背誦';

  @override
  String get navToday => '今日';

  @override
  String get navBible => '聖經';

  @override
  String get navPlans => '計劃';

  @override
  String get navStatistics => '統計';

  @override
  String get bibleTitle => '聖經';

  @override
  String get translationLabel => '譯本';

  @override
  String get oldTestament => '舊約';

  @override
  String get newTestament => '新約';

  @override
  String chapterLabel(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String get unableLoadBible => '無法載入聖經';

  @override
  String get unableLoadPassage => '無法載入經文';

  @override
  String get omittedVerse => '本譯本省略此節。';

  @override
  String get scriptureSources => '經文來源';
}
