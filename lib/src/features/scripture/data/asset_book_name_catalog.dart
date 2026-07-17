import 'package:flutter/widgets.dart';

import '../domain/book_name_catalog.dart';

final class AssetBookNameCatalog implements BookNameCatalog {
  const AssetBookNameCatalog.protestant66();

  @override
  String nameFor(String osisId, Locale locale) {
    final names = _names[osisId];
    if (names == null) return osisId;
    return names[_languageKey(locale)] ?? names['en'] ?? osisId;
  }

  @override
  String chapterLabel(String osisId, int chapter, Locale locale) {
    final book = nameFor(osisId, locale);
    return locale.languageCode == 'zh' ? '$book $chapter章' : '$book $chapter';
  }

  static String _languageKey(Locale locale) {
    if (locale.languageCode != 'zh') return locale.languageCode;
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    return script == 'hant' ||
            country == 'TW' ||
            country == 'HK' ||
            country == 'MO'
        ? 'zh-Hant'
        : 'zh-Hans';
  }
}

const _names = <String, Map<String, String>>{
  'GEN': {'zh-Hans': '创世记', 'zh-Hant': '創世記', 'en': 'Genesis'},
  'EXO': {'zh-Hans': '出埃及记', 'zh-Hant': '出埃及記', 'en': 'Exodus'},
  'LEV': {'zh-Hans': '利未记', 'zh-Hant': '利未記', 'en': 'Leviticus'},
  'NUM': {'zh-Hans': '民数记', 'zh-Hant': '民數記', 'en': 'Numbers'},
  'DEU': {'zh-Hans': '申命记', 'zh-Hant': '申命記', 'en': 'Deuteronomy'},
  'JOS': {'zh-Hans': '约书亚记', 'zh-Hant': '約書亞記', 'en': 'Joshua'},
  'JDG': {'zh-Hans': '士师记', 'zh-Hant': '士師記', 'en': 'Judges'},
  'RUT': {'zh-Hans': '路得记', 'zh-Hant': '路得記', 'en': 'Ruth'},
  '1SA': {'zh-Hans': '撒母耳记上', 'zh-Hant': '撒母耳記上', 'en': '1 Samuel'},
  '2SA': {'zh-Hans': '撒母耳记下', 'zh-Hant': '撒母耳記下', 'en': '2 Samuel'},
  '1KI': {'zh-Hans': '列王纪上', 'zh-Hant': '列王紀上', 'en': '1 Kings'},
  '2KI': {'zh-Hans': '列王纪下', 'zh-Hant': '列王紀下', 'en': '2 Kings'},
  '1CH': {'zh-Hans': '历代志上', 'zh-Hant': '歷代志上', 'en': '1 Chronicles'},
  '2CH': {'zh-Hans': '历代志下', 'zh-Hant': '歷代志下', 'en': '2 Chronicles'},
  'EZR': {'zh-Hans': '以斯拉记', 'zh-Hant': '以斯拉記', 'en': 'Ezra'},
  'NEH': {'zh-Hans': '尼希米记', 'zh-Hant': '尼希米記', 'en': 'Nehemiah'},
  'EST': {'zh-Hans': '以斯帖记', 'zh-Hant': '以斯帖記', 'en': 'Esther'},
  'JOB': {'zh-Hans': '约伯记', 'zh-Hant': '約伯記', 'en': 'Job'},
  'PSA': {'zh-Hans': '诗篇', 'zh-Hant': '詩篇', 'en': 'Psalms'},
  'PRO': {'zh-Hans': '箴言', 'zh-Hant': '箴言', 'en': 'Proverbs'},
  'ECC': {'zh-Hans': '传道书', 'zh-Hant': '傳道書', 'en': 'Ecclesiastes'},
  'SNG': {'zh-Hans': '雅歌', 'zh-Hant': '雅歌', 'en': 'Song of Songs'},
  'ISA': {'zh-Hans': '以赛亚书', 'zh-Hant': '以賽亞書', 'en': 'Isaiah'},
  'JER': {'zh-Hans': '耶利米书', 'zh-Hant': '耶利米書', 'en': 'Jeremiah'},
  'LAM': {'zh-Hans': '耶利米哀歌', 'zh-Hant': '耶利米哀歌', 'en': 'Lamentations'},
  'EZK': {'zh-Hans': '以西结书', 'zh-Hant': '以西結書', 'en': 'Ezekiel'},
  'DAN': {'zh-Hans': '但以理书', 'zh-Hant': '但以理書', 'en': 'Daniel'},
  'HOS': {'zh-Hans': '何西阿书', 'zh-Hant': '何西阿書', 'en': 'Hosea'},
  'JOL': {'zh-Hans': '约珥书', 'zh-Hant': '約珥書', 'en': 'Joel'},
  'AMO': {'zh-Hans': '阿摩司书', 'zh-Hant': '阿摩司書', 'en': 'Amos'},
  'OBA': {'zh-Hans': '俄巴底亚书', 'zh-Hant': '俄巴底亞書', 'en': 'Obadiah'},
  'JON': {'zh-Hans': '约拿书', 'zh-Hant': '約拿書', 'en': 'Jonah'},
  'MIC': {'zh-Hans': '弥迦书', 'zh-Hant': '彌迦書', 'en': 'Micah'},
  'NAM': {'zh-Hans': '那鸿书', 'zh-Hant': '那鴻書', 'en': 'Nahum'},
  'HAB': {'zh-Hans': '哈巴谷书', 'zh-Hant': '哈巴谷書', 'en': 'Habakkuk'},
  'ZEP': {'zh-Hans': '西番雅书', 'zh-Hant': '西番雅書', 'en': 'Zephaniah'},
  'HAG': {'zh-Hans': '哈该书', 'zh-Hant': '哈該書', 'en': 'Haggai'},
  'ZEC': {'zh-Hans': '撒迦利亚书', 'zh-Hant': '撒迦利亞書', 'en': 'Zechariah'},
  'MAL': {'zh-Hans': '玛拉基书', 'zh-Hant': '瑪拉基書', 'en': 'Malachi'},
  'MAT': {'zh-Hans': '马太福音', 'zh-Hant': '馬太福音', 'en': 'Matthew'},
  'MRK': {'zh-Hans': '马可福音', 'zh-Hant': '馬可福音', 'en': 'Mark'},
  'LUK': {'zh-Hans': '路加福音', 'zh-Hant': '路加福音', 'en': 'Luke'},
  'JHN': {'zh-Hans': '约翰福音', 'zh-Hant': '約翰福音', 'en': 'John'},
  'ACT': {'zh-Hans': '使徒行传', 'zh-Hant': '使徒行傳', 'en': 'Acts'},
  'ROM': {'zh-Hans': '罗马书', 'zh-Hant': '羅馬書', 'en': 'Romans'},
  '1CO': {'zh-Hans': '哥林多前书', 'zh-Hant': '哥林多前書', 'en': '1 Corinthians'},
  '2CO': {'zh-Hans': '哥林多后书', 'zh-Hant': '哥林多後書', 'en': '2 Corinthians'},
  'GAL': {'zh-Hans': '加拉太书', 'zh-Hant': '加拉太書', 'en': 'Galatians'},
  'EPH': {'zh-Hans': '以弗所书', 'zh-Hant': '以弗所書', 'en': 'Ephesians'},
  'PHP': {'zh-Hans': '腓立比书', 'zh-Hant': '腓立比書', 'en': 'Philippians'},
  'COL': {'zh-Hans': '歌罗西书', 'zh-Hant': '歌羅西書', 'en': 'Colossians'},
  '1TH': {'zh-Hans': '帖撒罗尼迦前书', 'zh-Hant': '帖撒羅尼迦前書', 'en': '1 Thessalonians'},
  '2TH': {'zh-Hans': '帖撒罗尼迦后书', 'zh-Hant': '帖撒羅尼迦後書', 'en': '2 Thessalonians'},
  '1TI': {'zh-Hans': '提摩太前书', 'zh-Hant': '提摩太前書', 'en': '1 Timothy'},
  '2TI': {'zh-Hans': '提摩太后书', 'zh-Hant': '提摩太後書', 'en': '2 Timothy'},
  'TIT': {'zh-Hans': '提多书', 'zh-Hant': '提多書', 'en': 'Titus'},
  'PHM': {'zh-Hans': '腓利门书', 'zh-Hant': '腓利門書', 'en': 'Philemon'},
  'HEB': {'zh-Hans': '希伯来书', 'zh-Hant': '希伯來書', 'en': 'Hebrews'},
  'JAS': {'zh-Hans': '雅各书', 'zh-Hant': '雅各書', 'en': 'James'},
  '1PE': {'zh-Hans': '彼得前书', 'zh-Hant': '彼得前書', 'en': '1 Peter'},
  '2PE': {'zh-Hans': '彼得后书', 'zh-Hant': '彼得後書', 'en': '2 Peter'},
  '1JN': {'zh-Hans': '约翰一书', 'zh-Hant': '約翰一書', 'en': '1 John'},
  '2JN': {'zh-Hans': '约翰二书', 'zh-Hant': '約翰二書', 'en': '2 John'},
  '3JN': {'zh-Hans': '约翰三书', 'zh-Hant': '約翰三書', 'en': '3 John'},
  'JUD': {'zh-Hans': '犹大书', 'zh-Hant': '猶大書', 'en': 'Jude'},
  'REV': {'zh-Hans': '启示录', 'zh-Hant': '啟示錄', 'en': 'Revelation'},
};
