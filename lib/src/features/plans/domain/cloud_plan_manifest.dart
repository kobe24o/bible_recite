import 'dart:convert';

final class CloudPlanManifest {
  const CloudPlanManifest({
    required this.protocolVersion,
    required this.publisher,
    required this.plans,
  });

  final int protocolVersion;
  final String publisher;
  final List<CloudPlanTemplate> plans;

  static CloudPlanManifest parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid cloud plan JSON: ${error.message}');
    }
    final root = _map(decoded, 'root');
    final protocol = _integer(root['protocolVersion'], 'protocolVersion');
    if (protocol != 1) {
      throw FormatException('Unsupported cloud plan protocol: $protocol');
    }
    final rawPlans = _list(root['plans'], 'plans');
    final plans = rawPlans
        .map((item) => CloudPlanTemplate._parse(_map(item, 'plan')))
        .toList(growable: false);
    final ids = plans.map((plan) => plan.id).toSet();
    if (ids.length != plans.length) {
      throw const FormatException('Plan IDs must be unique');
    }
    return CloudPlanManifest(
      protocolVersion: protocol,
      publisher: _optionalString(root['publisher']) ?? '',
      plans: List.unmodifiable(plans),
    );
  }
}

final class CloudPlanTemplate {
  const CloudPlanTemplate({
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
    required this.passages,
  });

  final String id;
  final String title;
  final String description;
  final bool push;
  final int revision;
  final String defaultTranslationId;
  final DateTime? defaultStartDate;
  final DateTime? defaultEndDate;
  final String sourceName;
  final String tag;
  final List<CloudPlanPassage> passages;

  factory CloudPlanTemplate._parse(Map<String, Object?> value) {
    final passages =
        _list(value['passages'], 'passages')
            .map((item) => CloudPlanPassage._parse(_map(item, 'passage')))
            .toList(growable: false)
          ..sort((a, b) => a.order.compareTo(b.order));
    if (passages.isEmpty) {
      throw const FormatException('A plan must contain at least one passage');
    }
    if (passages.map((passage) => passage.order).toSet().length !=
        passages.length) {
      throw const FormatException('Passage order values must be unique');
    }
    final revision = _integer(value['revision'], 'revision');
    if (revision < 1) throw const FormatException('Revision must be positive');
    return CloudPlanTemplate(
      id: _requiredString(value['id'], 'id'),
      title: _requiredString(value['title'], 'title'),
      description: _optionalString(value['description']) ?? '',
      push: value['push'] == true,
      revision: revision,
      defaultTranslationId: _requiredString(
        value['defaultTranslationId'],
        'defaultTranslationId',
      ),
      defaultStartDate: _date(value['defaultStartDate'], 'defaultStartDate'),
      defaultEndDate: _date(value['defaultEndDate'], 'defaultEndDate'),
      sourceName: _optionalString(value['sourceName']) ?? '',
      tag: _optionalString(value['tag']) ?? '',
      passages: List.unmodifiable(passages),
    );
  }
}

final class CloudPlanPassage {
  const CloudPlanPassage({
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

  factory CloudPlanPassage._parse(Map<String, Object?> value) {
    final order = _integer(value['order'], 'order');
    final bookId = _requiredString(value['bookId'], 'bookId');
    final startChapter = _integer(value['startChapter'], 'startChapter');
    final startVerse = _integer(value['startVerse'], 'startVerse');
    final endChapter = _integer(value['endChapter'], 'endChapter');
    final endVerse = _integer(value['endVerse'], 'endVerse');
    if (!RegExp(r'^[1-3]?[A-Z]{2,3}$').hasMatch(bookId) ||
        order < 1 ||
        startChapter < 1 ||
        startVerse < 1 ||
        endChapter < startChapter ||
        endVerse < 1 ||
        (startChapter == endChapter && endVerse < startVerse)) {
      throw const FormatException('Invalid passage range');
    }
    return CloudPlanPassage(
      order: order,
      bookId: bookId,
      startChapter: startChapter,
      startVerse: startVerse,
      endChapter: endChapter,
      endVerse: endVerse,
    );
  }
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String field) {
  if (value is! List<Object?>) throw FormatException('$field must be a list');
  return value;
}

int _integer(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

String _requiredString(Object? value, String field) {
  final result = _optionalString(value);
  if (result == null || result.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return result;
}

String? _optionalString(Object? value) => value is String ? value.trim() : null;

DateTime? _date(Object? value, String field) {
  if (value == null || value == '') return null;
  if (value is! String) throw FormatException('$field must be a date string');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$field is not a valid date');
  return DateTime(parsed.year, parsed.month, parsed.day);
}
