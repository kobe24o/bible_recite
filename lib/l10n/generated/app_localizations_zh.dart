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
  String get navStatistics => '我的';

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

  @override
  String get todayTitle => '今日任务';

  @override
  String get todayEmpty => '还没有今日背诵任务。可以先浏览圣经并选择要背诵的经文。';

  @override
  String get plansTitle => '背诵计划';

  @override
  String get plansEmpty => '还没有背诵计划。可以先浏览圣经，确定想要背诵的范围。';

  @override
  String get statisticsTitle => '我的';

  @override
  String get statisticsEmpty => '还没有背诵记录。完成背诵后，这里会显示学习进度。';

  @override
  String get browseBible => '浏览圣经';

  @override
  String get startRecitation => '开始背诵';

  @override
  String get addToPlan => '加入计划';

  @override
  String get verseMode => '逐节背诵';

  @override
  String get continuousMode => '连续背诵';

  @override
  String get chooseRecitationMode => '选择背诵模式';

  @override
  String get presetPlans => '预置计划';

  @override
  String get psalm23Plan => '诗篇 23篇';

  @override
  String get matthewSermonPlan => '马太福音 5–7章';

  @override
  String get johnOpeningPlan => '约翰福音 1–3章';

  @override
  String get philippiansPlan => '腓立比书全书';

  @override
  String daysCount(int days) {
    return '$days 天';
  }

  @override
  String get customPlan => '自定义计划';
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
  String get navStatistics => '我的';

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

  @override
  String get todayTitle => '今日任務';

  @override
  String get todayEmpty => '還沒有今日背誦任務。可以先瀏覽聖經並選擇要背誦的經文。';

  @override
  String get plansTitle => '背誦計劃';

  @override
  String get plansEmpty => '還沒有背誦計劃。可以先瀏覽聖經，確定想要背誦的範圍。';

  @override
  String get statisticsTitle => '我的';

  @override
  String get statisticsEmpty => '還沒有背誦記錄。完成背誦後，這裡會顯示學習進度。';

  @override
  String get browseBible => '瀏覽聖經';

  @override
  String get startRecitation => '開始背誦';

  @override
  String get addToPlan => '加入計劃';

  @override
  String get verseMode => '逐節背誦';

  @override
  String get continuousMode => '連續背誦';

  @override
  String get chooseRecitationMode => '選擇背誦模式';

  @override
  String get presetPlans => '預置計劃';

  @override
  String get psalm23Plan => '詩篇 23篇';

  @override
  String get matthewSermonPlan => '馬太福音 5–7章';

  @override
  String get johnOpeningPlan => '約翰福音 1–3章';

  @override
  String get philippiansPlan => '腓立比書全書';

  @override
  String daysCount(int days) {
    return '$days 天';
  }

  @override
  String get customPlan => '自訂計劃';
}
