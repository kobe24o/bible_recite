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
}
