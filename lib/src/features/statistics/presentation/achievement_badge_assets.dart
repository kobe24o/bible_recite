/// Resolves a stable bundled artwork for every achievement id, including
/// dynamically created book, 30-day, streak, and preset-plan achievements.
String achievementBadgeAssetPath(String achievementId) {
  if (achievementId.startsWith('book_complete_')) {
    final bookId = achievementId.substring('book_complete_'.length);
    final slug = _bookSlugs[bookId] ?? bookId.toLowerCase();
    return 'assets/achievements/generated/book_$slug.png';
  }
  if (achievementId.startsWith('preset_plan_')) {
    return 'assets/achievements/generated/preset_plan.png';
  }
  if (_isThirtyMultiple(achievementId, 'days_')) {
    return 'assets/achievements/generated/recitation_days_30n_template.png';
  }
  if (_isThirtyMultiple(achievementId, 'streak_')) {
    return 'assets/achievements/generated/streak_30n_template.png';
  }
  return 'assets/achievements/generated/$achievementId.png';
}

const _bookSlugs = <String, String>{
  'GEN': 'genesis',
  'EXO': 'exodus',
  'LEV': 'leviticus',
  'NUM': 'numbers',
  'DEU': 'deuteronomy',
  'JOS': 'joshua',
  'JDG': 'judges',
  'RUT': 'ruth',
  '1SA': '1_samuel',
  '2SA': '2_samuel',
  '1KI': '1_kings',
  '2KI': '2_kings',
  '1CH': '1_chronicles',
  '2CH': '2_chronicles',
  'EZR': 'ezra',
  'NEH': 'nehemiah',
  'EST': 'esther',
  'JOB': 'job',
  'PSA': 'psalms',
  'PRO': 'proverbs',
  'ECC': 'ecclesiastes',
  'SNG': 'song_of_songs',
  'ISA': 'isaiah',
  'JER': 'jeremiah',
  'LAM': 'lamentations',
  'EZK': 'ezekiel',
  'DAN': 'daniel',
  'HOS': 'hosea',
  'JOL': 'joel',
  'AMO': 'amos',
  'OBA': 'obadiah',
  'JON': 'jonah',
  'MIC': 'micah',
  'NAM': 'nahum',
  'HAB': 'habakkuk',
  'ZEP': 'zephaniah',
  'HAG': 'haggai',
  'ZEC': 'zechariah',
  'MAL': 'malachi',
  'MAT': 'matthew',
  'MRK': 'mark',
  'LUK': 'luke',
  'JHN': 'john',
  'ACT': 'acts',
  'ROM': 'romans',
  '1CO': '1_corinthians',
  '2CO': '2_corinthians',
  'GAL': 'galatians',
  'EPH': 'ephesians',
  'PHP': 'philippians',
  'COL': 'colossians',
  '1TH': '1_thessalonians',
  '2TH': '2_thessalonians',
  '1TI': '1_timothy',
  '2TI': '2_timothy',
  'TIT': 'titus',
  'PHM': 'philemon',
  'HEB': 'hebrews',
  'JAS': 'james',
  '1PE': '1_peter',
  '2PE': '2_peter',
  '1JN': '1_john',
  '2JN': '2_john',
  '3JN': '3_john',
  'JUD': 'jude',
  'REV': 'revelation',
};

bool _isThirtyMultiple(String id, String prefix) {
  if (!id.startsWith(prefix)) return false;
  final value = int.tryParse(id.substring(prefix.length));
  return value != null && value >= 30 && value % 30 == 0;
}
