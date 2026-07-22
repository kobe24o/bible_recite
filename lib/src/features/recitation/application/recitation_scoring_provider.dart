import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/bible_pronunciation_lexicon.dart';
import '../domain/mandarin_phonetic_comparator.dart';

/// Loads the bundled pronunciation lexicon once for completed Chinese scoring.
final mandarinPhoneticComparatorProvider =
    FutureProvider<MandarinPhoneticComparator>((ref) async {
      final lexicon = await BiblePronunciationLexicon.load(rootBundle);
      return MandarinPhoneticComparator(lexicon: lexicon);
    });
