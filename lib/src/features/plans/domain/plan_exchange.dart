import 'dart:convert';

import 'plan_models.dart';

final class PlanExchange {
  static const format = 'bible-recite-plan';
  static const version = 1;

  static String encode(MemorizationPlan plan, List<PlanTask> tasks) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'plan': {
          'title': plan.title,
          'translationId': plan.translationId,
          'bookId': plan.bookId,
          'startChapter': plan.startChapter,
          'endChapter': plan.endChapter,
          'startDate': _date(plan.startDate),
          'endDate': _date(plan.endDate),
          'tasks': [
            for (final task in tasks)
              {
                'dayIndex': task.dayIndex,
                'bookId': task.bookId,
                'startChapter': task.startChapter,
                'startVerse': task.startVerse,
                'endChapter': task.endChapter,
                'endVerse': task.endVerse,
              },
          ],
        },
      });

  static NewMemorizationPlan decode(String source) {
    final root = _map(jsonDecode(source), 'root');
    if (root['format'] != format || root['version'] != version) {
      throw const FormatException('不是可导入的背诵计划文件');
    }
    final plan = _map(root['plan'], 'plan');
    final start = _dateValue(plan['startDate'], 'startDate');
    final end = _dateValue(plan['endDate'], 'endDate');
    final tasks = _list(plan['tasks'], 'tasks')
        .map((value) {
          final task = _map(value, 'task');
          final startChapter = _positive(task['startChapter'], 'startChapter');
          final startVerse = _positive(task['startVerse'], 'startVerse');
          final endChapter = _positive(task['endChapter'], 'endChapter');
          final endVerse = _positive(task['endVerse'], 'endVerse');
          if (endChapter < startChapter ||
              (endChapter == startChapter && endVerse < startVerse)) {
            throw const FormatException('经文范围无效');
          }
          return NewPlanTask(
            dayIndex: _nonNegative(task['dayIndex'], 'dayIndex'),
            bookId: _text(task['bookId'], 'bookId'),
            startChapter: startChapter,
            startVerse: startVerse,
            endChapter: endChapter,
            endVerse: endVerse,
          );
        })
        .toList(growable: false);
    if (tasks.isEmpty || end.isBefore(start)) {
      throw const FormatException('计划内容或日期无效');
    }
    final days = end.difference(start).inDays + 1;
    if (days > 365 || tasks.any((task) => task.dayIndex >= days)) {
      throw const FormatException('计划天数无效');
    }
    return NewMemorizationPlan(
      title: _text(plan['title'], 'title'),
      translationId: _text(plan['translationId'], 'translationId'),
      bookId: _text(plan['bookId'], 'bookId'),
      startChapter: _positive(plan['startChapter'], 'startChapter'),
      endChapter: _positive(plan['endChapter'], 'endChapter'),
      startDate: start,
      endDate: end,
      tasks: tasks,
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
Map<String, Object?> _map(Object? value, String name) =>
    value is Map<String, Object?> ? value : throw FormatException('$name 无效');
List<Object?> _list(Object? value, String name) =>
    value is List<Object?> ? value : throw FormatException('$name 无效');
String _text(Object? value, String name) =>
    value is String && value.trim().isNotEmpty
    ? value.trim()
    : throw FormatException('$name 无效');
int _nonNegative(Object? value, String name) =>
    value is int && value >= 0 ? value : throw FormatException('$name 无效');
int _positive(Object? value, String name) =>
    value is int && value > 0 ? value : throw FormatException('$name 无效');
DateTime _dateValue(Object? value, String name) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw FormatException('$name 无效');
  return DateTime(parsed.year, parsed.month, parsed.day);
}
