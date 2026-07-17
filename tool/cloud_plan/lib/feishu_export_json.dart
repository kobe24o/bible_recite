import 'dart:convert';
import 'dart:io';

final class FeishuExportJsonRequest {
  const FeishuExportJsonRequest({
    required this.plansCsvPath,
    required this.passagesCsvPath,
    required this.outputPath,
  });

  final String plansCsvPath;
  final String passagesCsvPath;
  final String outputPath;
}

final class FeishuExportJsonSummary {
  const FeishuExportJsonSummary({
    required this.planCount,
    required this.passageCount,
  });

  final int planCount;
  final int passageCount;
}

final class FeishuExportJsonPublisher {
  const FeishuExportJsonPublisher();

  FeishuExportJsonSummary publish(FeishuExportJsonRequest request) {
    final planTable = _CsvTable.fromFile(File(request.plansCsvPath));
    planTable.requireHeaders(const ['计划 ID', '计划名称', '修订号', '默认译本', '协议版本']);
    if (!planTable.hasHeader('是否推送') && !planTable.hasHeader('推送状态')) {
      throw const FormatException('背诵计划 CSV 缺少“是否推送”字段');
    }

    final plans = <_Plan>[];
    final plansById = <String, _Plan>{};
    for (final row in planTable.rows) {
      final id = row.required('计划 ID');
      if (plansById.containsKey(id)) {
        throw FormatException('计划 ID 重复：$id');
      }
      final protocol = _positiveInteger(row.required('协议版本'), '协议版本', id);
      if (protocol != 1) {
        throw FormatException('计划 $id 使用了不支持的协议版本：$protocol');
      }
      final pushed = _pushValue(
        row.value('是否推送').isNotEmpty ? row.value('是否推送') : row.value('推送状态'),
        id,
      );
      final startDate = _date(row.value('默认开始日期'), '默认开始日期', id);
      final endDate = _date(row.value('默认结束日期'), '默认结束日期', id);
      if (startDate != null &&
          endDate != null &&
          endDate.compareTo(startDate) < 0) {
        throw FormatException('计划 $id 的默认结束日期早于默认开始日期');
      }
      final plan = _Plan(
        id: id,
        title: row.required('计划名称'),
        description: row.value('计划简介'),
        push: pushed,
        revision: _positiveInteger(row.required('修订号'), '修订号', id),
        defaultTranslationId: _translation(row.required('默认译本'), id),
        defaultStartDate: startDate,
        defaultEndDate: endDate,
        sourceName: row.value('来源名称'),
        tag: row.value('标签'),
      );
      plans.add(plan);
      plansById[id] = plan;
    }

    final passageTable = _CsvTable.fromFile(File(request.passagesCsvPath));
    passageTable.requireHeaders(const [
      '所属计划',
      '经文顺序',
      '起始章节',
      '起始节',
      '终止章节',
      '终止节',
      '范围校验',
    ]);
    for (final row in passageTable.rows) {
      final planId = _linkedPlanId(row);
      final plan = plansById[planId];
      if (plan == null) {
        throw FormatException('计划经文引用了背诵计划 CSV 中不存在的计划：$planId');
      }
      if (!plan.push) continue;
      final validation = _singleCellValue(row.required('范围校验'));
      if (validation != '通过') {
        throw FormatException(
          '计划 $planId 的第 ${row.value('经文顺序')} 条经文“范围校验”为“$validation”，必须为“通过”',
        );
      }

      final start = _chapterRef(
        displayValue: row.required('起始章节'),
        bookValue: row.value('起始经卷'),
        chapterValue: row.value('起始章号'),
        field: '起始章节',
        planId: planId,
      );
      final end = _chapterRef(
        displayValue: row.required('终止章节'),
        bookValue: row.value('终止经卷'),
        chapterValue: row.value('终止章号'),
        field: '终止章节',
        planId: planId,
      );
      final order = _positiveInteger(row.required('经文顺序'), '经文顺序', planId);
      final startVerse = _positiveInteger(row.required('起始节'), '起始节', planId);
      final endVerse = _positiveInteger(row.required('终止节'), '终止节', planId);
      if (start.bookId != end.bookId) {
        throw FormatException('计划 $planId 的第 $order 条经文不可在单条范围内跨卷');
      }
      if (start.chapter > end.chapter ||
          (start.chapter == end.chapter && startVerse > endVerse)) {
        throw FormatException('计划 $planId 的第 $order 条经文范围顺序错误');
      }
      if (plan.passages.any((item) => item.order == order)) {
        throw FormatException('计划 $planId 的经文顺序重复：$order');
      }
      plan.passages.add(
        _Passage(
          order: order,
          bookId: start.bookId,
          startChapter: start.chapter,
          startVerse: startVerse,
          endChapter: end.chapter,
          endVerse: endVerse,
        ),
      );
    }

    final publishedPlans = plans
        .where((plan) => plan.push)
        .toList(growable: false);
    for (final plan in publishedPlans) {
      if (plan.passages.isEmpty) {
        throw FormatException('已推送计划 ${plan.id} 没有经文');
      }
      plan.passages.sort((a, b) => a.order.compareTo(b.order));
    }
    final publishers = publishedPlans
        .map((plan) => plan.sourceName)
        .where((name) => name.isNotEmpty)
        .toSet();
    final manifest = <String, Object?>{
      'protocolVersion': 1,
      'publisher': publishers.length == 1 ? publishers.single : '',
      'plans': [for (final plan in publishedPlans) plan.toJson()],
    };
    final source = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
    _replaceSafely(File(request.outputPath), source);
    return FeishuExportJsonSummary(
      planCount: publishedPlans.length,
      passageCount: publishedPlans.fold(
        0,
        (sum, plan) => sum + plan.passages.length,
      ),
    );
  }
}

List<List<String>> parseRfc4180Csv(String source) {
  var input = source;
  if (input.startsWith('\uFEFF')) input = input.substring(1);
  final records = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var justClosedQuote = false;

  void finishField() {
    row.add(field.toString());
    field.clear();
    justClosedQuote = false;
  }

  void finishRow() {
    finishField();
    if (row.any((value) => value.isNotEmpty)) records.add(row);
    row = <String>[];
  }

  for (var index = 0; index < input.length; index++) {
    final character = input[index];
    if (inQuotes) {
      if (character == '"') {
        if (index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          inQuotes = false;
          justClosedQuote = true;
        }
      } else {
        field.write(character);
      }
      continue;
    }
    if (character == '"') {
      if (field.isNotEmpty || justClosedQuote) {
        throw const FormatException('CSV 引号格式错误');
      }
      inQuotes = true;
    } else if (character == ',') {
      finishField();
    } else if (character == '\r' || character == '\n') {
      if (character == '\r' &&
          index + 1 < input.length &&
          input[index + 1] == '\n') {
        index++;
      }
      finishRow();
    } else {
      if (justClosedQuote) throw const FormatException('CSV 引号后存在非法字符');
      field.write(character);
    }
  }
  if (inQuotes) throw const FormatException('CSV 存在未闭合的引号');
  if (field.isNotEmpty || row.isNotEmpty || justClosedQuote) finishRow();
  if (records.isEmpty) throw const FormatException('CSV 为空');
  return records;
}

final class _CsvTable {
  _CsvTable._(this.headers, this.rows);

  factory _CsvTable.fromFile(File file) {
    if (!file.existsSync()) {
      throw FormatException('找不到 CSV 文件：${file.path}');
    }
    final records = parseRfc4180Csv(file.readAsStringSync());
    final headers = records.first
        .map((value) => value.trim())
        .toList(growable: false);
    if (headers.toSet().length != headers.length) {
      throw FormatException('CSV 表头存在重复字段：${file.path}');
    }
    final rows = <_CsvRow>[];
    for (var index = 1; index < records.length; index++) {
      final values = records[index];
      if (values.length != headers.length) {
        throw FormatException(
          'CSV 第 ${index + 1} 行有 ${values.length} 列，表头有 ${headers.length} 列：${file.path}',
        );
      }
      rows.add(_CsvRow(Map.fromIterables(headers, values), index + 1));
    }
    return _CsvTable._(headers, rows);
  }

  final List<String> headers;
  final List<_CsvRow> rows;

  bool hasHeader(String name) => headers.contains(name);

  void requireHeaders(List<String> required) {
    final missing = required.where((name) => !headers.contains(name)).toList();
    if (missing.isNotEmpty) {
      throw FormatException('CSV 缺少字段：${missing.join('、')}');
    }
  }
}

final class _CsvRow {
  const _CsvRow(this.values, this.line);

  final Map<String, String> values;
  final int line;

  String value(String field) => (values[field] ?? '').trim();

  String required(String field) {
    final result = value(field);
    if (result.isEmpty) throw FormatException('CSV 第 $line 行的“$field”不能为空');
    return result;
  }
}

final class _Plan {
  _Plan({
    required this.id,
    required this.title,
    required this.description,
    required this.push,
    required this.revision,
    required this.defaultTranslationId,
    required this.defaultStartDate,
    required this.defaultEndDate,
    required this.sourceName,
    required this.tag,
  });

  final String id;
  final String title;
  final String description;
  final bool push;
  final int revision;
  final String defaultTranslationId;
  final String? defaultStartDate;
  final String? defaultEndDate;
  final String sourceName;
  final String tag;
  final passages = <_Passage>[];

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'push': push,
    'revision': revision,
    'defaultTranslationId': defaultTranslationId,
    'defaultStartDate': defaultStartDate,
    'defaultEndDate': defaultEndDate,
    'sourceName': sourceName,
    'tag': tag,
    'passages': [for (final passage in passages) passage.toJson()],
  };
}

final class _Passage {
  const _Passage({
    required this.order,
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final int order;
  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;

  Map<String, Object?> toJson() => <String, Object?>{
    'order': order,
    'bookId': bookId,
    'startChapter': startChapter,
    'startVerse': startVerse,
    'endChapter': endChapter,
    'endVerse': endVerse,
  };
}

final class _ChapterRef {
  const _ChapterRef(this.bookId, this.chapter);

  final String bookId;
  final int chapter;
}

String _linkedPlanId(_CsvRow row) {
  final formulaId = row.value('计划 ID');
  return _singleCellValue(
    formulaId.isNotEmpty ? formulaId : row.required('所属计划'),
  );
}

String _singleCellValue(String input) {
  final value = input.trim();
  if (value.startsWith('[')) {
    final decoded = jsonDecode(value);
    if (decoded is! List || decoded.length != 1 || decoded.single is! String) {
      throw FormatException('关联字段必须只包含一个值：$value');
    }
    return (decoded.single as String).trim();
  }
  return value;
}

_ChapterRef _chapterRef({
  required String displayValue,
  required String bookValue,
  required String chapterValue,
  required String field,
  required String planId,
}) {
  final match = RegExp(
    r'^([1-3]?[A-Z]{2,3})\.(\d{3})(?:\b|｜)',
  ).firstMatch(_singleCellValue(displayValue));
  if (match == null) {
    throw FormatException('计划 $planId 的$field格式无效：$displayValue');
  }
  final displayBook = match.group(1)!;
  final displayChapter = int.parse(match.group(2)!);
  final book = bookValue.isEmpty ? displayBook : _singleCellValue(bookValue);
  final chapter = chapterValue.isEmpty
      ? displayChapter
      : _positiveInteger(_singleCellValue(chapterValue), field, planId);
  if (book != displayBook || chapter != displayChapter) {
    throw FormatException('计划 $planId 的$field与经卷/章号公式字段不一致');
  }
  if (!RegExp(r'^[1-3]?[A-Z]{2,3}$').hasMatch(book)) {
    throw FormatException('计划 $planId 的$field经卷 OSIS 无效：$book');
  }
  return _ChapterRef(book, chapter);
}

bool _pushValue(String input, String planId) {
  switch (_singleCellValue(input).toLowerCase()) {
    case '是':
    case 'true':
    case 'yes':
    case '1':
      return true;
    case '':
    case '否':
    case 'false':
    case 'no':
    case '0':
      return false;
    default:
      throw FormatException('计划 $planId 的“是否推送”值无效：$input');
  }
}

String _translation(String input, String planId) {
  switch (_singleCellValue(input).toLowerCase()) {
    case '简体':
    case '简体中文':
    case 'cmn-cu89s':
      return 'cmn-cu89s';
    case '繁体':
    case '繁體':
    case '繁体中文':
    case '繁體中文':
    case 'cmn-cu89t':
      return 'cmn-cu89t';
    case '英文':
    case 'english':
    case 'eng-web':
      return 'eng-web';
    default:
      throw FormatException('计划 $planId 的“默认译本”值无效：$input');
  }
}

int _positiveInteger(String input, String field, String context) {
  final number = num.tryParse(_singleCellValue(input));
  if (number == null || number != number.roundToDouble() || number < 1) {
    throw FormatException('$context 的$field必须是正整数：$input');
  }
  return number.toInt();
}

String? _date(String input, String field, String planId) {
  if (input.isEmpty) return null;
  final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(input);
  if (match == null) throw FormatException('计划 $planId 的$field格式无效：$input');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw FormatException('计划 $planId 的$field无效：$input');
  }
  return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

void _replaceSafely(File target, String source) {
  target.parent.createSync(recursive: true);
  final temporary = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  final backup = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.bak',
  );
  temporary.writeAsStringSync(source, flush: true);
  var movedOriginal = false;
  try {
    if (target.existsSync()) {
      target.renameSync(backup.path);
      movedOriginal = true;
    }
    temporary.renameSync(target.path);
    if (backup.existsSync()) backup.deleteSync();
  } catch (_) {
    if (!target.existsSync() && movedOriginal && backup.existsSync()) {
      backup.renameSync(target.path);
    }
    rethrow;
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
