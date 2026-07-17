import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Scripture Recite'**
  String get appTitle;

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navBible.
  ///
  /// In en, this message translates to:
  /// **'Bible'**
  String get navBible;

  /// No description provided for @navPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get navPlans;

  /// No description provided for @navStatistics.
  ///
  /// In en, this message translates to:
  /// **'My'**
  String get navStatistics;

  /// No description provided for @bibleTitle.
  ///
  /// In en, this message translates to:
  /// **'Bible'**
  String get bibleTitle;

  /// No description provided for @translationLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translationLabel;

  /// No description provided for @oldTestament.
  ///
  /// In en, this message translates to:
  /// **'Old Testament'**
  String get oldTestament;

  /// No description provided for @newTestament.
  ///
  /// In en, this message translates to:
  /// **'New Testament'**
  String get newTestament;

  /// No description provided for @chapterLabel.
  ///
  /// In en, this message translates to:
  /// **'Chapter {chapter}'**
  String chapterLabel(int chapter);

  /// No description provided for @unableLoadBible.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the Bible'**
  String get unableLoadBible;

  /// No description provided for @unableLoadPassage.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the passage'**
  String get unableLoadPassage;

  /// No description provided for @omittedVerse.
  ///
  /// In en, this message translates to:
  /// **'This verse is omitted in this translation.'**
  String get omittedVerse;

  /// No description provided for @scriptureSources.
  ///
  /// In en, this message translates to:
  /// **'Scripture sources'**
  String get scriptureSources;

  /// No description provided for @todayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s tasks'**
  String get todayTitle;

  /// No description provided for @todayEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no recitation tasks today. Browse the Bible to choose a passage to memorize.'**
  String get todayEmpty;

  /// No description provided for @plansTitle.
  ///
  /// In en, this message translates to:
  /// **'Recitation plans'**
  String get plansTitle;

  /// No description provided for @plansEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no recitation plans yet. Browse the Bible to choose what you want to memorize.'**
  String get plansEmpty;

  /// No description provided for @statisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'My'**
  String get statisticsTitle;

  /// No description provided for @statisticsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no recitation records yet. Your progress will appear here after you practice.'**
  String get statisticsEmpty;

  /// No description provided for @browseBible.
  ///
  /// In en, this message translates to:
  /// **'Browse the Bible'**
  String get browseBible;

  /// No description provided for @startRecitation.
  ///
  /// In en, this message translates to:
  /// **'Start recitation'**
  String get startRecitation;

  /// No description provided for @addToPlan.
  ///
  /// In en, this message translates to:
  /// **'Add to plan'**
  String get addToPlan;

  /// No description provided for @verseMode.
  ///
  /// In en, this message translates to:
  /// **'Verse by verse'**
  String get verseMode;

  /// No description provided for @continuousMode.
  ///
  /// In en, this message translates to:
  /// **'Continuous'**
  String get continuousMode;

  /// No description provided for @chooseRecitationMode.
  ///
  /// In en, this message translates to:
  /// **'Choose recitation mode'**
  String get chooseRecitationMode;

  /// No description provided for @presetPlans.
  ///
  /// In en, this message translates to:
  /// **'Preset plans'**
  String get presetPlans;

  /// No description provided for @psalm23Plan.
  ///
  /// In en, this message translates to:
  /// **'Psalm 23'**
  String get psalm23Plan;

  /// No description provided for @matthewSermonPlan.
  ///
  /// In en, this message translates to:
  /// **'Matthew 5–7'**
  String get matthewSermonPlan;

  /// No description provided for @johnOpeningPlan.
  ///
  /// In en, this message translates to:
  /// **'John 1–3'**
  String get johnOpeningPlan;

  /// No description provided for @philippiansPlan.
  ///
  /// In en, this message translates to:
  /// **'Philippians'**
  String get philippiansPlan;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String daysCount(int days);

  /// No description provided for @customPlan.
  ///
  /// In en, this message translates to:
  /// **'Custom plan'**
  String get customPlan;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
