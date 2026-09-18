import 'dart:convert';

import '../../scripture/domain/canonical_verse_limits.dart';

enum RestoreMode { merge, replace }

final class RestoreCounts {
  const RestoreCounts({this.imported = 0, this.skipped = 0, this.retained = 0});
  final int imported;
  final int skipped;
  final int retained;
}

final class RestoreReport {
  RestoreReport(Map<String, RestoreCounts> categories)
    : categories = Map.unmodifiable(categories);
  final Map<String, RestoreCounts> categories;
  int get imported => categories.values.fold(0, (n, c) => n + c.imported);
  int get skipped => categories.values.fold(0, (n, c) => n + c.skipped);
  int get retained => categories.values.fold(0, (n, c) => n + c.retained);
}

final class BackupDevotionNote {
  const BackupDevotionNote(this.date, this.content, this.updatedAt);
  final DateTime date;
  final String content;
  final DateTime updatedAt;
}

/// Version 1 is an explicit, portable record protocol, never a SQLite dump.
/// Only these settings are transferable; newly added credentials or caches
/// remain private by default until deliberately included here.
const backupSettingKeys = {
  'profile_name',
  'first_opened_at',
  'show_recitation_scripture',
  'ignore_final_nasal',
  'recent_scripture_searches',
  'daily_reminder_enabled',
  'daily_reminder_start',
  'daily_reminder_end',
  'daily_reminder_interval',
  'cloud_plan_source_url',
  'devotion_source_url',
  'quiz_model_url',
  'quiz_model_name',
  'quiz_model_answering_enabled',
  'max_day_streak',
  'max_verse_streak',
  'current_quiz_correct_streak',
  'max_quiz_correct_streak',
};

final class UserDataBackup {
  UserDataBackup._(
    this.exportedAt,
    Map<String, List<Map<String, Object?>>> rows,
  ) : records = Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: List<Map<String, Object?>>.unmodifiable(
            entry.value.map((row) => Map<String, Object?>.unmodifiable(row)),
          ),
      });

  /// Large personal history, particularly devotional notes, must round-trip
  /// without treating a normal export as an unsafe import payload.
  static const maxBytes = 100 * 1024 * 1024;
  final DateTime exportedAt;
  final Map<String, List<Map<String, Object?>>> records;

  Map<String, String> get settings => Map.unmodifiable({
    for (final row in records['app_setting']!)
      row['setting_key'] as String: row['setting_value'] as String,
  });

  List<BackupDevotionNote> get devotionNotes => List.unmodifiable([
    for (final row in records['devotion_note']!)
      BackupDevotionNote(
        DateTime.parse(row['date'] as String),
        row['content'] as String,
        DateTime.parse(row['updated_at'] as String),
      ),
  ]);

  /// Adapts explicit local rows in dependency order. Row IDs are used only to
  /// find parents and never leave the device. Natural keys exclude mutable
  /// progress and note content, so re-importing a backup is idempotent.
  factory UserDataBackup.fromRecords(
    Map<String, List<Map<String, Object?>>> rows, {
    DateTime? exportedAt,
  }) {
    final portable = <String, List<Map<String, Object?>>>{};
    final keys = <String, Map<Object?, String>>{};
    for (final table in backupTables) {
      final localKeys = keys[table.name] = {};
      final occurrences = <String, int>{};
      portable[table.name] = [
        for (final row in rows[table.name] ?? <Map<String, Object?>>[])
          if (table.name != 'app_setting' ||
              backupSettingKeys.contains(row['setting_key']))
            _portableRow(table, row, keys, localKeys, occurrences),
      ];
    }
    return UserDataBackup.decode(
      jsonEncode({
        'format': 'bible-recite-user-backup',
        'version': 1,
        'exported_at': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'records': portable,
      }),
    );
  }

  static Map<String, Object?> _portableRow(
    BackupTable table,
    Map<String, Object?> row,
    Map<String, Map<Object?, String>> keys,
    Map<Object?, String> localKeys,
    Map<String, int> occurrences,
  ) {
    final result = <String, Object?>{
      for (final field in table.fields.keys) field: row[field],
    };
    for (final ref in table.references) {
      final id = row[ref.column];
      final key = id == null ? null : keys[ref.table]?[id];
      if (id != null && key == null) {
        throw FormatException('Missing ${ref.table} parent');
      }
      result[ref.field] = key;
    }
    result['key'] = _portableKey(table, result, occurrences);
    localKeys[row[table.primaryKey]] = result['key'] as String;
    return result;
  }

  static UserDataBackup decode(String source) {
    if (source.length > maxBytes || utf8.encode(source).length > maxBytes) {
      throw const FormatException('备份文件超过 100 MB');
    }
    final root = _map(jsonDecode(source));
    if (root['format'] != 'bible-recite-user-backup' || root['version'] != 1) {
      throw const FormatException('不支持的备份格式或版本');
    }
    final time = _timestamp(root['exported_at']);
    final data = _map(root['records']);
    if (data.length != backupTables.length ||
        data.keys.any(
          (key) => !backupTables.any((table) => table.name == key),
        )) {
      throw const FormatException('Unknown or missing backup categories');
    }
    final rows = <String, List<Map<String, Object?>>>{};
    final indexed = <String, Map<String, Map<String, Object?>>>{};
    for (final table in backupTables) {
      final raw = data[table.name];
      if (raw is! List) throw FormatException('Missing ${table.name} records');
      final index = indexed[table.name] = {};
      final occurrences = <String, int>{};
      rows[table.name] = [];
      for (final value in raw) {
        final row = Map<String, Object?>.from(_map(value));
        table.validate(row);
        for (final field in table.fields.entries) {
          if (field.value.replaceAll('?', '') == 'time' &&
              row[field.key] != null) {
            row[field.key] = _timestamp(row[field.key]).toIso8601String();
          }
        }
        final key = _portableKey(table, row, occurrences);
        if (row['key'] != key || index.containsKey(key)) {
          throw FormatException('Invalid or duplicate ${table.name} identity');
        }
        for (final ref in table.references) {
          final parent = row[ref.field];
          if (parent == null && ref.nullable) continue;
          if (parent is! String || indexed[ref.table]?[parent] == null) {
            throw FormatException('Dangling ${table.name}.${ref.field}');
          }
        }
        _validateRelationships(table.name, row, indexed);
        index[key] = row;
        rows[table.name]!.add(row);
      }
    }
    final settings = {
      for (final row in rows['app_setting']!)
        row['setting_key'] as String: row['setting_value'] as String,
    };
    final reminderStart = int.parse(settings['daily_reminder_start'] ?? '420');
    final reminderEnd = int.parse(settings['daily_reminder_end'] ?? '1439');
    if (reminderEnd < reminderStart) {
      throw const FormatException('Invalid reminder time range');
    }
    return UserDataBackup._(time, rows);
  }

  String encode() => jsonEncode({
    'format': 'bible-recite-user-backup',
    'version': 1,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'records': records,
  });
}

final class BackupReference {
  const BackupReference(
    this.column,
    this.field,
    this.table, {
    this.nullable = false,
  });
  final String column;
  final String field;
  final String table;
  final bool nullable;
}

/// All SQL identifiers originate here, never from the imported file. Field
/// codes: s=nonempty string, text=any string, i=nonnegative integer,
/// p=positive integer, b=0/1, ratio=0..1, day=calendar date, time=timestamp.
final class BackupTable {
  const BackupTable(
    this.name,
    this.fields,
    this.identity, {
    this.primaryKey = 'id',
    this.references = const [],
  });
  final String name;
  final Map<String, String> fields;
  final List<String> identity;
  final String primaryKey;
  final List<BackupReference> references;

  String keyFor(Map<String, Object?> row) {
    if (name == 'ebbinghaus_settings') return 'settings';
    final columns =
        name == 'memorization_plan' &&
            row['source_url'] != null &&
            row['external_id'] != null
        ? ['source_url', 'external_id']
        : identity;
    return jsonEncode([
      for (final key in columns)
        fields[key]?.replaceAll('?', '') == 'time' && row[key] != null
            ? _timestamp(row[key]).toIso8601String()
            : row[key],
    ]);
  }

  void validate(Map<String, Object?> row) {
    final allowed = {'key', ...fields.keys, ...references.map((r) => r.field)};
    if (row.keys.any((key) => !allowed.contains(key)) ||
        !allowed.every(row.containsKey)) {
      throw FormatException('Unexpected or missing $name fields');
    }
    for (final field in fields.entries) {
      final value = row[field.key];
      if (field.value.endsWith('?') && value == null) continue;
      final type = field.value.replaceAll('?', '');
      if (type == 'day') {
        _day(value);
        continue;
      }
      if (type == 'time') {
        _timestamp(value);
        continue;
      }
      final valid = switch (type) {
        's' => value is String && value.isNotEmpty,
        'text' => value is String,
        'i' => value is int && value >= 0,
        'p' => value is int && value > 0,
        'b' => value is int && (value == 0 || value == 1),
        'ratio' => value is num && value.isFinite && value >= 0 && value <= 1,
        _ => false,
      };
      if (!valid) throw FormatException('Invalid $name.${field.key}');
    }
    if (row.containsKey('book_id')) _validatePassage(row);
    void choice(String field, List<String> options) {
      if (!options.contains(row[field])) {
        throw FormatException('Invalid $name.$field');
      }
    }

    switch (name) {
      case 'memorization_plan':
        choice('source_kind', ['local', 'preset', 'cloud']);
        choice('status', ['active', 'paused']);
        if ((row['days'] as int) > 365 ||
            _day(row['end_date']).difference(_day(row['start_date'])).inDays +
                    1 !=
                row['days']) {
          throw const FormatException('Invalid plan schedule');
        }
      case 'plan_schedule_span':
        if ((row['days'] as int) <= 365) {
          throw const FormatException('Invalid extended schedule');
        }
      case 'quiz_question':
        choice('source', ['local', 'cloud', 'model']);
        if ((row['end_offset'] as int) <= (row['start_offset'] as int) ||
            (row['answered'] == 1 &&
                (row['is_correct'] == null || row['answered_at'] == null)) ||
            (row['answered'] == 0 &&
                (row['is_correct'] != null || row['answered_at'] != null))) {
          throw const FormatException('Invalid question state');
        }
      case 'ebbinghaus_settings':
        if ((row['pass_threshold'] as num) < 0.5) {
          throw const FormatException('Invalid pass threshold');
        }
      case 'ebbinghaus_cycle':
        choice('status', ['active', 'completed', 'restarted', 'paused']);
      case 'ebbinghaus_review':
        choice('status', ['pending', 'completed', 'failed', 'cancelled']);
      case 'app_setting':
        if (!backupSettingKeys.contains(row['setting_key'])) {
          throw const FormatException('Nonportable setting');
        }
        if (row['setting_key'] == 'first_opened_at') {
          _timestamp(row['setting_value']);
        }
        _validateSetting(
          row['setting_key'] as String,
          row['setting_value'] as String,
        );
    }
    if (row['started_at'] != null &&
        row['completed_at'] != null &&
        _timestamp(
          row['completed_at'],
        ).isBefore(_timestamp(row['started_at']))) {
      throw const FormatException('Completion precedes start');
    }
  }
}

// Dependency order is also the import order and reversed deletion order.
const backupTables = <BackupTable>[
  BackupTable(
    'memorization_plan',
    {
      'title': 's',
      'translation_id': 's',
      'book_id': 's',
      'start_chapter': 'p',
      'end_chapter': 'p',
      'days': 'p',
      'start_date': 'day',
      'end_date': 'day',
      'source_kind': 's',
      'source_url': 's?',
      'external_id': 's?',
      'revision': 'i',
      'content_locked': 'b',
      'ebbinghaus_enabled': 'b',
      'status': 's',
      'created_at': 'time',
    },
    ['created_at', 'translation_id', 'book_id'],
  ),
  BackupTable(
    'plan_schedule_span',
    {'days': 'p', 'end_date': 'day'},
    ['plan_ref'],
    primaryKey: 'plan_id',
    references: [BackupReference('plan_id', 'plan_ref', 'memorization_plan')],
  ),
  BackupTable(
    'plan_task',
    {
      'day_index': 'i',
      'due_date': 'day',
      'book_id': 's',
      'start_chapter': 'p',
      'start_verse': 'p',
      'end_chapter': 'p',
      'end_verse': 'p',
      'completed': 'b',
    },
    [
      'plan_ref',
      'day_index',
      'book_id',
      'start_chapter',
      'start_verse',
      'end_chapter',
      'end_verse',
    ],
    references: [BackupReference('plan_id', 'plan_ref', 'memorization_plan')],
  ),
  BackupTable(
    'plan_task_block',
    {
      'sort_order': 'i',
      'book_id': 's',
      'start_chapter': 'p',
      'start_verse': 'p',
      'end_chapter': 'p',
      'end_verse': 'p',
    },
    ['task_ref', 'sort_order'],
    references: [BackupReference('plan_task_id', 'task_ref', 'plan_task')],
  ),
  BackupTable(
    'recitation_result',
    {
      'translation_id': 's',
      'book_id': 's',
      'chapter': 'p',
      'start_verse': 'p',
      'end_verse': 'p',
      'chapter_verse_count': 'i',
      'mode': 's',
      'duration_seconds': 'i',
      'character_count': 'i',
      'correct_count': 'i',
      'phonetic_correct_count': 'i',
      'incorrect_count': 'i',
      'omitted_count': 'i',
      'reordered_count': 'i',
      'accuracy': 'ratio',
      'started_at': 'time?',
      'completed_at': 'time',
    },
    [
      'translation_id',
      'book_id',
      'chapter',
      'start_verse',
      'end_verse',
      'mode',
      'started_at',
      'completed_at',
    ],
    references: [
      BackupReference(
        'plan_id',
        'plan_ref',
        'memorization_plan',
        nullable: true,
      ),
    ],
  ),
  BackupTable(
    'recitation_verse_metric',
    {
      'translation_id': 's',
      'book_id': 's',
      'chapter': 'p',
      'verse': 'p',
      'accuracy': 'ratio',
      'duration_seconds': 'i',
      'character_count': 'i',
      'started_at': 'time?',
      'completed_at': 'time',
    },
    ['result_ref', 'book_id', 'chapter', 'verse'],
    references: [
      BackupReference(
        'recitation_result_id',
        'result_ref',
        'recitation_result',
      ),
      BackupReference(
        'plan_id',
        'plan_ref',
        'memorization_plan',
        nullable: true,
      ),
    ],
  ),
  BackupTable(
    'quiz_question',
    {
      'translation_id': 's',
      'book_id': 's',
      'chapter': 'p',
      'verse': 'p',
      'start_offset': 'i',
      'end_offset': 'p',
      'word': 's',
      'part_of_speech': 'text',
      'meaning': 'text',
      'reference': 'text',
      'source': 's',
      'quality_version': 'p',
      'answered': 'b',
      'is_correct': 'b?',
      'answered_at': 'time?',
      'created_at': 'time',
    },
    [
      'translation_id',
      'book_id',
      'chapter',
      'verse',
      'start_offset',
      'end_offset',
    ],
  ),
  BackupTable(
    'quiz_result',
    {
      'translation_id': 's',
      'book_id': 's',
      'chapter': 'p',
      'verse': 'p',
      'correct': 'b',
      'answered_at': 'time',
    },
    ['translation_id', 'book_id', 'chapter', 'verse', 'answered_at', 'correct'],
    references: [
      BackupReference(
        'question_id',
        'question_ref',
        'quiz_question',
        nullable: true,
      ),
    ],
  ),
  BackupTable(
    'achievement_unlock',
    {
      'achievement_id': 's',
      'unlocked_at': 'time',
      'source': 'text',
      'award_count': 'p',
    },
    ['achievement_id'],
    primaryKey: 'achievement_id',
  ),
  BackupTable('ebbinghaus_settings', {
    'enabled': 'b',
    'pass_threshold': 'ratio',
    'enabled_at': 'time?',
    'updated_at': 'time',
  }, []),
  BackupTable(
    'ebbinghaus_cycle',
    {
      'translation_id': 's',
      'book_id': 's',
      'chapter': 'p',
      'start_chapter': 'p',
      'start_verse': 'p',
      'end_chapter': 'p',
      'end_verse': 'p',
      'base_date': 'day',
      'status': 's',
      'created_at': 'time',
    },
    ['source_result_ref'],
    references: [
      BackupReference(
        'source_result_id',
        'source_result_ref',
        'recitation_result',
      ),
      BackupReference(
        'source_plan_id',
        'source_plan_ref',
        'memorization_plan',
        nullable: true,
      ),
    ],
  ),
  BackupTable(
    'ebbinghaus_review',
    {
      'interval_days': 'p',
      'due_date': 'day',
      'status': 's',
      'created_at': 'time',
    },
    ['cycle_ref', 'interval_days'],
    references: [
      BackupReference('cycle_id', 'cycle_ref', 'ebbinghaus_cycle'),
      BackupReference(
        'result_id',
        'result_ref',
        'recitation_result',
        nullable: true,
      ),
    ],
  ),
  BackupTable(
    'devotion_note',
    {'date': 'day', 'content': 'text', 'updated_at': 'time'},
    ['date'],
    primaryKey: 'date',
  ),
  BackupTable(
    'app_setting',
    {'setting_key': 's', 'setting_value': 'text'},
    ['setting_key'],
    primaryKey: 'setting_key',
  ),
];

String _portableKey(
  BackupTable table,
  Map<String, Object?> row,
  Map<String, int> occurrences,
) {
  final identity = table.keyFor(row);
  if (table.name != 'quiz_result') return identity;
  // Snapshot activation removes question IDs, but each history row retains
  // its own verse scope and answer event. Keep that identity stable before
  // and after detachment, and retain multiple indistinguishable attempts.
  // Occurrence order is stable in exports (local row order); re-importing
  // either snapshot preserves the maximum observed multiplicity.
  final occurrence = occurrences.update(
    identity,
    (n) => n + 1,
    ifAbsent: () => 0,
  );
  return jsonEncode([identity, occurrence]);
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object');
  }
  return value;
}

DateTime _day(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid calendar date');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      parsed.year < 1 ||
      parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid calendar date');
  }
  return parsed;
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)?$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid timestamp');
  }
  _day(value.substring(0, 10));
  // Old database rows may have no offset; interpret these consistently on all
  // devices instead of letting the importing machine change their identity.
  final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)
      ? value
      : '${value}Z';
  return DateTime.parse(zoned).toUtc();
}

void _validateSetting(String key, String value) {
  const flags = {
    'show_recitation_scripture',
    'ignore_final_nasal',
    'daily_reminder_enabled',
    'quiz_model_answering_enabled',
  };
  const counters = {
    'max_day_streak',
    'max_verse_streak',
    'current_quiz_correct_streak',
    'max_quiz_correct_streak',
  };
  if (flags.contains(key) && value != 'true' && value != 'false') {
    throw FormatException('Invalid $key');
  }
  if (counters.contains(key) ||
      key == 'daily_reminder_start' ||
      key == 'daily_reminder_end' ||
      key == 'daily_reminder_interval') {
    final number = int.tryParse(value);
    if (number == null ||
        number < 0 ||
        ((key == 'daily_reminder_start' || key == 'daily_reminder_end') &&
            number > 1439) ||
        (key == 'daily_reminder_interval' && (number < 1 || number > 779))) {
      throw FormatException('Invalid $key');
    }
  }
  if (key == 'recent_scripture_searches') {
    final searches = jsonDecode(value);
    if (searches is! List || searches.any((search) => search is! String)) {
      throw const FormatException('Invalid recent searches');
    }
  }
}

void _validatePassage(Map<String, Object?> row) {
  final limits = canonicalProtestant66VerseLimits[row['book_id']];
  final start = (row['start_chapter'] ?? row['chapter']) as int;
  final end = (row['end_chapter'] ?? start) as int;
  final startVerse = (row['start_verse'] ?? row['verse'] ?? 1) as int;
  final endVerse = (row['end_verse'] ?? row['verse'] ?? startVerse) as int;
  if (limits == null ||
      start > limits.length ||
      end > limits.length ||
      end < start ||
      startVerse > limits[start - 1] ||
      endVerse > limits[end - 1] ||
      (start == end && endVerse < startVerse)) {
    throw const FormatException('Invalid scripture range');
  }
}

void _validateRelationships(
  String table,
  Map<String, Object?> row,
  Map<String, Map<String, Map<String, Object?>>> index,
) {
  Map<String, Object?> parent(String name, String ref) =>
      index[name]![row[ref]]!;
  void same(Map<String, Object?> other, Iterable<String> fields) {
    if (fields.any((field) => row[field] != other[field])) {
      throw const FormatException('Inconsistent parent scope');
    }
  }

  switch (table) {
    case 'plan_schedule_span':
      final plan = parent('memorization_plan', 'plan_ref');
      if (_day(row['end_date']).difference(_day(plan['start_date'])).inDays +
              1 !=
          row['days']) {
        throw const FormatException('Inconsistent schedule span');
      }
    case 'plan_task':
      final plan = parent('memorization_plan', 'plan_ref');
      final span = index['plan_schedule_span']![jsonEncode([row['plan_ref']])];
      final days = (span?['days'] ?? plan['days']) as int;
      // Completion records its actual date, and resume rebases unfinished
      // tasks without changing the plan's original start date.
      if ((row['day_index'] as int) >= days) {
        throw const FormatException('Task is outside its schedule');
      }
    case 'recitation_verse_metric':
      final result = parent('recitation_result', 'result_ref');
      same(result, ['translation_id', 'book_id', 'chapter', 'plan_ref']);
      if ((row['verse'] as int) < (result['start_verse'] as int) ||
          (row['verse'] as int) > (result['end_verse'] as int)) {
        throw const FormatException('Metric outside result range');
      }
    case 'quiz_result':
      if (row['question_ref'] != null) {
        same(parent('quiz_question', 'question_ref'), [
          'translation_id',
          'book_id',
          'chapter',
          'verse',
        ]);
      }
    case 'ebbinghaus_cycle':
      final result = parent('recitation_result', 'source_result_ref');
      same(result, [
        'translation_id',
        'book_id',
        'chapter',
        'start_verse',
        'end_verse',
      ]);
      // A failed standalone review restarts under the original cycle's plan.
      // That plan need not be attached to the new source recitation result.
      if ((result['plan_ref'] != null &&
              row['source_plan_ref'] != result['plan_ref']) ||
          row['start_chapter'] != result['chapter'] ||
          row['end_chapter'] != result['chapter']) {
        throw const FormatException('Cycle outside source range');
      }
    case 'ebbinghaus_review':
      if (row['result_ref'] != null) {
        final cycle = parent('ebbinghaus_cycle', 'cycle_ref');
        final result = parent('recitation_result', 'result_ref');
        if ([
          'translation_id',
          'book_id',
          'chapter',
          'start_verse',
          'end_verse',
        ].any((field) => cycle[field] != result[field])) {
          throw const FormatException('Review result outside cycle range');
        }
      }
  }
}
