import 'dart:io';

import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_bank_merge.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';

const _usage = '''
合并多个 BibleRecite 导出题库并按题目位置去重。

用法：
  dart run tool/merge_quiz_banks.dart -o merged-quiz-bank.json bank-a.json bank-b.json

规则：同一译本、卷、章、节、开始位置、结束位置视为同一题；
按输入顺序保留第一题。答题记录和 API Key 不会出现在输出文件中。
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  String? output;
  final inputs = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '-o' || argument == '--output') {
      if (++index >= arguments.length) _fail('缺少输出文件路径');
      output = arguments[index];
    } else if (argument.startsWith('-')) {
      _fail('未知选项：$argument');
    } else {
      inputs.add(argument);
    }
  }
  if (output == null || inputs.isEmpty) _fail('需要至少一个输入文件和 -o 输出文件');
  final banks = <List<QuizBankQuestion>>[];
  var total = 0;
  for (final path in inputs) {
    final file = File(path);
    if (!await file.exists()) _fail('找不到文件：$path');
    final text = await file.readAsString();
    if (text.length > 10 * 1024 * 1024) _fail('文件过大（超过 10 MB）：$path');
    try {
      final bank = QuizBankExchange.decode(text);
      banks.add(bank);
      total += bank.length;
      stdout.writeln('$path：读取 ${bank.length} 道');
    } on FormatException catch (error) {
      _fail('$path 不是有效题库：${error.message}');
    }
  }
  final merged = QuizBankMerge.merge(banks);
  await File(output).writeAsString(QuizBankExchange.encode(merged));
  stdout.writeln(
    '合并完成：输入 $total 道，保留 ${merged.length} 道，去重 ${total - merged.length} 道。',
  );
  stdout.writeln('输出：$output');
}

Never _fail(String message) {
  stderr.writeln('错误：$message');
  stderr.write(_usage);
  exitCode = 64;
  throw ArgumentError(message);
}
