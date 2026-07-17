import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../lib/feishu_export_json.dart';

void main(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _usage(stdout);
    return;
  }
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final key = arguments[index];
    if (!key.startsWith('--') || index + 1 >= arguments.length) {
      stderr.writeln('参数格式错误：$key');
      _usage(stderr);
      exitCode = 64;
      return;
    }
    values[key] = arguments[++index];
  }
  final plans = values['--plans'];
  final passages = values['--passages'];
  final output = values['--output'];
  if (plans == null || passages == null || output == null) {
    stderr.writeln('必须同时提供 --plans、--passages 和 --output。');
    _usage(stderr);
    exitCode = 64;
    return;
  }
  try {
    final summary = const FeishuExportJsonPublisher().publish(
      FeishuExportJsonRequest(
        plansCsvPath: plans,
        passagesCsvPath: passages,
        outputPath: output,
      ),
    );
    stdout.writeln(
      '发布完成：${summary.planCount} 个计划，${summary.passageCount} 条经文 → $output',
    );
  } on FormatException catch (error) {
    stderr.writeln('发布失败：${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('文件操作失败：${error.message}');
    exitCode = 74;
  }
}

void _usage(IOSink sink) {
  sink.writeln(
    '用法：cloud-plan-publisher --plans <背诵计划.csv> '
    '--passages <计划经文_发布编辑.csv> --output <cloud-plans.json>',
  );
}
