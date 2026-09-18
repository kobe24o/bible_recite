import 'dart:convert';

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

  static const maxBytes = 20 * 1024 * 1024;
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
      throw const FormatException('备份文件超过 20 MB');
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
  final limits = _verseLimits[row['book_id']];
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

// Maximum verse numbers for the 1,189 chapters across the bundled cmn-cu89s,
// cmn-cu89t and eng-web verse_unit tables. Keeps validation independent of
// downloaded scripture packs while respecting their versification differences.
final _verseLimits = <String, List<int>>{
  for (final entry in _chapterVerseNumbers.entries)
    entry.key: entry.value.split(',').map(int.parse).toList(growable: false),
};

const _chapterVerseNumbers = {
  '1CH':
      '54,55,24,43,26,81,40,40,44,14,47,40,14,17,29,43,27,17,19,8,30,19,32,31,31,32,34,21,30',
  '1CO': '31,16,23,21,13,20,40,13,27,33,34,31,13,40,58,24',
  '1JN': '10,29,24,21,21',
  '1KI': '53,46,28,34,18,38,51,66,28,29,43,33,34,31,34,34,24,46,21,43,29,53',
  '1PE': '25,25,22,19,14',
  '1SA':
      '28,36,21,22,12,21,17,22,27,27,15,25,23,52,35,23,58,30,24,42,15,23,29,22,44,25,12,25,11,31,13',
  '1TH': '10,20,13,18,28',
  '1TI': '20,15,16,16,25,21',
  '2CH':
      '17,18,17,22,14,42,22,18,31,19,23,16,22,15,19,14,19,34,11,37,20,12,21,27,28,23,9,27,36,27,21,33,25,33,27,23',
  '2CO': '24,17,18,18,21,18,16,24,15,18,33,21,14',
  '2JN': '13',
  '2KI':
      '18,25,27,44,27,33,20,29,37,36,21,21,25,29,38,20,41,37,37,21,26,20,37,20,30',
  '2PE': '21,22,18',
  '2SA':
      '27,32,39,12,25,23,29,18,13,19,27,31,39,33,37,23,29,33,43,26,22,51,39,25',
  '2TH': '12,17,18',
  '2TI': '18,26,17,22',
  '3JN': '15',
  'ACT':
      '26,47,26,37,42,15,60,40,43,48,30,25,52,28,41,40,34,28,41,38,40,30,35,27,27,32,44,31',
  'AMO': '15,16,15,13,27,14,17,14,15',
  'COL': '29,23,25,18',
  'DAN': '21,49,30,37,31,28,28,27,27,21,45,13',
  'DEU':
      '46,37,29,49,33,25,26,20,29,22,32,32,18,29,23,22,20,22,21,20,23,30,25,22,19,19,26,68,29,20,30,52,29,12',
  'ECC': '18,26,22,16,20,12,29,17,18,20,10,14',
  'EPH': '23,22,21,32,33,24',
  'EST': '22,23,15,17,14,14,10,17,32,3',
  'EXO':
      '22,25,22,31,23,30,25,32,35,29,10,51,22,31,27,36,16,27,25,26,36,31,33,18,40,37,21,43,46,38,18,35,23,35,35,38,29,31,43,38',
  'EZK':
      '28,10,27,17,17,14,27,18,11,22,25,28,23,23,8,63,24,32,14,49,32,31,49,27,17,21,36,26,21,26,18,32,33,31,15,38,28,23,29,49,26,20,27,31,25,24,23,35',
  'EZR': '11,70,13,24,17,22,28,36,15,44',
  'GAL': '24,21,29,31,26,18',
  'GEN':
      '31,25,24,26,32,22,24,22,29,32,32,20,18,24,21,16,27,33,38,18,34,24,20,67,34,35,46,22,35,43,55,32,20,31,29,43,36,30,23,23,57,38,34,34,28,34,31,22,33,26',
  'HAB': '17,20,19',
  'HAG': '15,23',
  'HEB': '14,18,19,16,14,20,28,13,28,39,40,29,25',
  'HOS': '11,23,5,19,15,11,16,14,17,15,12,14,16,9',
  'ISA':
      '31,22,26,6,30,13,25,22,21,34,16,6,22,32,9,14,14,7,25,6,17,25,18,23,12,21,13,29,24,33,9,20,24,17,10,22,38,22,8,31,29,25,28,28,25,13,15,22,26,11,23,15,12,17,13,12,21,14,21,22,11,12,19,12,25,24',
  'JAS': '27,26,18,17,20',
  'JDG': '36,23,31,24,31,40,25,35,57,18,40,15,25,20,20,31,13,31,30,48,25',
  'JER':
      '19,37,25,31,31,30,34,22,26,25,23,17,27,22,21,21,27,23,15,18,14,30,40,10,38,24,22,17,32,24,40,44,26,22,19,32,21,28,18,16,18,22,13,30,5,28,7,47,39,46,64,34',
  'JHN': '51,25,36,54,47,71,53,59,41,42,57,50,38,31,27,33,26,40,42,31,25',
  'JOB':
      '22,13,26,21,27,30,21,22,35,22,20,25,28,22,35,22,16,21,29,29,34,30,17,25,6,14,23,28,25,31,40,22,33,37,16,33,24,41,30,24,34,17',
  'JOL': '20,32,21',
  'JON': '17,10,10,11',
  'JOS':
      '18,24,17,24,15,27,26,35,27,43,23,24,33,15,63,10,18,28,51,9,45,34,16,33',
  'JUD': '25',
  'LAM': '22,22,66,22,22',
  'LEV':
      '17,16,17,35,19,30,38,36,24,20,47,8,59,57,33,34,16,30,37,27,24,33,44,23,55,46,34',
  'LUK':
      '80,52,38,44,39,49,50,56,62,42,54,59,35,35,32,31,37,43,48,47,38,71,56,53',
  'MAL': '14,17,18,6',
  'MAT':
      '25,23,17,25,48,34,29,34,38,42,30,50,58,36,39,28,27,35,30,34,46,46,39,51,46,75,66,20',
  'MIC': '16,13,12,13,15,16,20',
  'MRK': '45,28,35,41,43,56,37,38,50,52,33,44,37,72,47,20',
  'NAM': '15,13,19',
  'NEH': '11,20,32,23,19,19,73,18,38,39,36,47,31',
  'NUM':
      '54,34,51,49,31,27,89,26,23,36,35,16,33,45,41,50,13,32,22,29,35,41,30,25,18,65,23,31,40,16,54,42,56,29,34,13',
  'OBA': '21',
  'PHM': '25',
  'PHP': '30,30,21,23',
  'PRO':
      '33,22,35,27,23,35,27,36,18,32,31,28,25,35,33,33,28,24,29,30,31,29,35,34,28,28,27,28,27,33,31',
  'PSA':
      '6,12,8,8,12,10,17,9,20,18,7,8,6,7,5,11,15,50,14,9,13,31,6,10,22,12,14,9,11,12,24,11,22,22,28,12,40,22,13,17,13,11,5,26,17,11,9,14,20,23,19,9,6,7,23,13,11,11,17,12,8,12,11,10,13,20,7,35,36,5,24,20,28,23,10,12,20,72,13,19,16,8,18,12,13,17,7,18,52,17,16,15,5,23,11,13,12,9,9,5,8,28,22,35,45,48,43,13,31,7,10,10,9,8,18,19,2,29,176,7,8,9,4,8,5,6,5,6,8,8,3,18,3,3,21,26,9,8,24,13,10,7,12,15,21,10,20,14,9,6',
  'REV': '20,29,22,11,14,17,17,13,21,11,19,18,18,20,8,21,18,24,21,15,27,21',
  'ROM': '32,29,31,25,21,23,25,39,33,21,36,21,14,26,33,27',
  'RUT': '22,23,18,22',
  'SNG': '17,17,11,16,16,13,13,14',
  'TIT': '16,15,15',
  'ZEC': '21,13,10,14,11,15,14,23,17,12,17,14,9,21',
  'ZEP': '18,15,20',
};
