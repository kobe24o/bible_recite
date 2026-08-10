import 'dart:convert';

import 'quiz_models.dart';

/// Portable question-only format. It intentionally excludes answer history,
/// statistics and model credentials so a bank can be shared safely.
final class QuizBankExchange {
  static const format = 'bible-recite-quiz-bank';
  static const version = 1;

  static String encode(List<ValidatedQuizQuestion> questions) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'questions': [
          for (final question in questions)
            {
              'translationId': question.translationId,
              'bookId': question.bookId,
              'chapter': question.chapter,
              'verse': question.verse,
              'start': question.start,
              'end': question.end,
              'word': question.word,
              'partOfSpeech': question.partOfSpeech,
              'meaning': question.meaning,
              'reference': question.reference,
              'verseText': question.verseText,
            },
        ],
      });

  static List<ValidatedQuizQuestion> decode(String source) {
    final root = _map(jsonDecode(source), 'root');
    if (root['format'] != format || root['version'] != version) {
      throw const FormatException('不是可导入的答题题库文件');
    }
    return _list(root['questions'], 'questions')
        .map((value) {
          final data = _map(value, 'question');
          final text = _text(data['verseText'], 'verseText');
          final start = _nonNegative(data['start'], 'start');
          final end = _positive(data['end'], 'end');
          final word = _text(data['word'], 'word');
          if (end <= start ||
              end > text.length ||
              text.substring(start, end) != word) {
            throw const FormatException('题目位置或词语无效');
          }
          return ValidatedQuizQuestion(
            reference: _text(data['reference'], 'reference'),
            translationId: _text(data['translationId'], 'translationId'),
            bookId: _text(data['bookId'], 'bookId'),
            chapter: _positive(data['chapter'], 'chapter'),
            verse: _positive(data['verse'], 'verse'),
            start: start,
            end: end,
            word: word,
            partOfSpeech: _text(data['partOfSpeech'], 'partOfSpeech'),
            meaning: _text(data['meaning'], 'meaning'),
            verseText: text,
          );
        })
        .toList(growable: false);
  }
}

Map<String, Object?> _map(Object? value, String name) =>
    value is Map<String, Object?> ? value : throw FormatException('$name 无效');
List<Object?> _list(Object? value, String name) =>
    value is List<Object?> ? value : throw FormatException('$name 无效');
String _text(Object? value, String name) =>
    value is String && value.trim().isNotEmpty
    ? value.trim()
    : throw FormatException('$name 无效');
int _positive(Object? value, String name) =>
    value is int && value > 0 ? value : throw FormatException('$name 无效');
int _nonNegative(Object? value, String name) =>
    value is int && value >= 0 ? value : throw FormatException('$name 无效');
