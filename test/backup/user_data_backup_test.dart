import 'dart:convert';

import 'package:bible_recite/src/features/backup/domain/user_data_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'round trips every generated category with portable parent references',
    () {
      final backup = UserDataBackup.decode(
        UserDataBackup.fromRecords(backupRecords()).encode(),
      );
      expect(backup.devotionNotes.single.content, '今天的领受');
      expect(backup.settings, {'profile_name': '路得'});
      expect(
        backup.records['recitation_verse_metric']!.single['result_ref'],
        backup.records['recitation_result']!.single['key'],
      );
      expect(
        backup.records['quiz_result']!.single['question_ref'],
        backup.records['quiz_question']!.single['key'],
      );
      expect(
        backup.records['ebbinghaus_review']!.single['cycle_ref'],
        backup.records['ebbinghaus_cycle']!.single['key'],
      );
      expect(backup.records['plan_schedule_span']!.single['days'], 400);
      expect(backup.encode(), isNot(contains('secret-value')));
      expect(backup.encode(), isNot(contains('cached-value')));
      expect(backup.encode(), isNot(contains('plan_id')));
      expect(
        backup.records.values.every(
          (rows) => rows.every((row) => !row.containsKey('id')),
        ),
        isTrue,
      );
    },
  );

  test('identities are independent of local SQLite row IDs', () {
    final records = backupRecords();
    final first = UserDataBackup.fromRecords(records);
    records['memorization_plan']!.single['id'] = 999;
    for (final table in [
      'plan_task',
      'plan_schedule_span',
      'recitation_result',
      'recitation_verse_metric',
    ]) {
      records[table]!.single['plan_id'] = 999;
    }
    records['ebbinghaus_cycle']!.single['source_plan_id'] = 999;
    expect(UserDataBackup.fromRecords(records).records, first.records);
  });

  test('rejects unsupported format and version', () {
    for (final change in [
      {'format': 'other'},
      {'version': 2},
    ]) {
      expect(
        () => UserDataBackup.decode(jsonEncode({...validJson(), ...change})),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed objects and missing categories', () {
    expect(() => UserDataBackup.decode('[]'), throwsFormatException);
    final json = validJson()..remove('records');
    expect(
      () => UserDataBackup.decode(jsonEncode(json)),
      throwsFormatException,
    );
    final missing = validJson();
    (missing['records'] as Map).remove('plan_task');
    expect(
      () => UserDataBackup.decode(jsonEncode(missing)),
      throwsFormatException,
    );
  });

  test('rejects duplicate natural keys even if a supplied key is changed', () {
    final json = validJson();
    final rows = (json['records'] as Map)['quiz_question'] as List;
    rows.add({...rows.single as Map, 'key': 'forged'});
    expect(
      () => UserDataBackup.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test(
    'nullable quiz history still validates references and scripture scope',
    () {
      for (final reference in ['missing', 42]) {
        final json = validJson();
        final row =
            ((json['records'] as Map)['quiz_result'] as List).single as Map;
        row['question_ref'] = reference;
        expect(
          () => UserDataBackup.decode(jsonEncode(json)),
          throwsFormatException,
        );
      }
      final mismatched = backupRecords();
      mismatched['quiz_result']!.single['verse'] = 17;
      expect(
        () => UserDataBackup.fromRecords(mismatched),
        throwsFormatException,
      );

      final detached = backupRecords();
      detached['quiz_result']!.single['question_id'] = null;
      detached['quiz_question'] = [];
      final backup = UserDataBackup.fromRecords(detached);
      expect(backup.records['quiz_result']!.single['question_ref'], isNull);
      detached['quiz_result']!.single['verse'] = 37;
      expect(() => UserDataBackup.fromRecords(detached), throwsFormatException);
    },
  );

  test('rejects duplicate portable quiz event keys', () {
    final json = validJson();
    final rows = (json['records'] as Map)['quiz_result'] as List;
    rows.add({...rows.single as Map});
    expect(
      () => UserDataBackup.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test(
    'rejects dangling parents and relationships with inconsistent scope',
    () {
      for (final changes in [
        {'result_ref': 'missing'},
        {'verse': 99},
        {'book_id': 'GEN'},
      ]) {
        final json = validJson();
        final row =
            ((json['records'] as Map)['recitation_verse_metric'] as List).single
                as Map;
        row.addAll(changes);
        expect(
          () => UserDataBackup.decode(jsonEncode(json)),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects invalid dates, ranges, flags and numerical values', () {
    for (final entry in <(String, String, Object)>[
      ('devotion_note', 'date', '2026-02-30'),
      ('devotion_note', 'updated_at', '2026-02-30T00:00:00Z'),
      ('memorization_plan', 'days', 0),
      ('memorization_plan', 'start_date', '2026-13-01'),
      ('plan_task', 'start_verse', 0),
      ('plan_task_block', 'end_verse', 0),
      ('plan_task_block', 'book_id', 'BOGUS'),
      ('plan_task_block', 'end_chapter', 200),
      ('recitation_result', 'accuracy', 1.1),
      ('recitation_result', 'duration_seconds', -1),
      ('quiz_question', 'answered', 2),
      ('ebbinghaus_review', 'interval_days', -1),
      ('ebbinghaus_settings', 'pass_threshold', 0.1),
    ]) {
      final json = validJson();
      final row = ((json['records'] as Map)[entry.$1] as List).single as Map;
      row[entry.$2] = entry.$3;
      expect(
        () => UserDataBackup.decode(jsonEncode(json)),
        throwsFormatException,
        reason: '${entry.$1}.${entry.$2}',
      );
    }
  });

  test('rejects secret and cache settings in imported files', () {
    final json = validJson();
    ((json['records'] as Map)['app_setting'] as List).add({
      'key': 'quiz_model_api_key',
      'setting_key': 'quiz_model_api_key',
      'setting_value': 'secret',
    });
    expect(
      () => UserDataBackup.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('rejects invalid reminder and preference values before restore', () {
    for (final entry in <(String, String)>[
      ('daily_reminder_start', '-1'),
      ('daily_reminder_end', '1440'),
      ('daily_reminder_interval', '0'),
      ('daily_reminder_enabled', 'yes'),
      ('show_recitation_scripture', '1'),
      ('current_quiz_correct_streak', '-2'),
      ('recent_scripture_searches', '{"query":"创世记"}'),
    ]) {
      expect(
        () => UserDataBackup.fromRecords({
          'app_setting': [
            {'setting_key': entry.$1, 'setting_value': entry.$2},
          ],
        }),
        throwsFormatException,
        reason: entry.$1,
      );
    }
    expect(
      () => UserDataBackup.fromRecords({
        'app_setting': [
          {'setting_key': 'daily_reminder_start', 'setting_value': '1000'},
          {'setting_key': 'daily_reminder_end', 'setting_value': '900'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('rejects a review result from a different scripture passage', () {
    final rows = backupRecords();
    rows['recitation_result']!.add({
      ...rows['recitation_result']!.single,
      'id': 99,
      'book_id': 'GEN',
      'plan_id': null,
    });
    rows['ebbinghaus_review']!.single.addAll({
      'result_id': 99,
      'status': 'completed',
    });
    expect(() => UserDataBackup.fromRecords(rows), throwsFormatException);
  });

  test('limits UTF-8 input to 20 MB', () {
    expect(
      () => UserDataBackup.decode(' ' * (20 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(
      () => UserDataBackup.decode('中' * (7 * 1024 * 1024)),
      throwsFormatException,
    );
  });

  test(
    'validates actual chapter verse limits and strict flags before creating a backup',
    () {
      for (final entry in <(String, String, Object)>[
        ('plan_task_block', 'end_verse', 37), // John 3 has 36 verses.
        ('quiz_question', 'answered', 1.0),
        ('memorization_plan', 'days', 364), // Stored range spans 365 days.
      ]) {
        final rows = backupRecords();
        rows[entry.$1]!.single[entry.$2] = entry.$3;
        expect(
          () => UserDataBackup.fromRecords(rows),
          throwsFormatException,
          reason: '${entry.$1}.${entry.$2}',
        );
      }
    },
  );

  test(
    'rejects unknown categories instead of ignoring potentially lost data',
    () {
      final json = validJson();
      (json['records'] as Map)['future_data'] = [];
      expect(
        () => UserDataBackup.decode(jsonEncode(json)),
        throwsFormatException,
      );
    },
  );

  test(
    'normalizes timestamps to UTC including legacy values without offsets',
    () {
      final rows = backupRecords();
      rows['devotion_note']!.single['updated_at'] = '2026-01-01T09:00:00+08:00';
      expect(
        UserDataBackup.fromRecords(
          rows,
        ).records['devotion_note']!.single['updated_at'],
        '2026-01-01T01:00:00.000Z',
      );
      rows['devotion_note']!.single['updated_at'] = '2026-01-01T01:00:00';
      expect(
        UserDataBackup.fromRecords(
          rows,
        ).records['devotion_note']!.single['updated_at'],
        '2026-01-01T01:00:00.000Z',
      );
    },
  );
}

Map<String, Object?> validJson() =>
    jsonDecode(UserDataBackup.fromRecords(backupRecords()).encode())
        as Map<String, Object?>;

// Literal database rows cover the complete current user-data schema.
Map<String, List<Map<String, Object?>>> backupRecords() => {
  'memorization_plan': [
    {
      'id': 12,
      'title': '恩典之路',
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'start_chapter': 3,
      'end_chapter': 3,
      'days': 365,
      'start_date': '2026-01-01',
      'end_date': '2026-12-31',
      'source_kind': 'local',
      'source_url': null,
      'external_id': null,
      'revision': 0,
      'content_locked': 0,
      'ebbinghaus_enabled': 1,
      'status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
    },
  ],
  'plan_schedule_span': [
    {'plan_id': 12, 'days': 400, 'end_date': '2027-02-04'},
  ],
  'plan_task': [
    {
      'id': 25,
      'plan_id': 12,
      'day_index': 0,
      'due_date': '2026-01-01',
      'book_id': 'JHN',
      'start_chapter': 3,
      'start_verse': 16,
      'end_chapter': 3,
      'end_verse': 17,
      'completed': 1,
    },
  ],
  'plan_task_block': [
    {
      'id': 33,
      'plan_task_id': 25,
      'sort_order': 0,
      'book_id': 'JHN',
      'start_chapter': 3,
      'start_verse': 16,
      'end_chapter': 3,
      'end_verse': 17,
    },
  ],
  'recitation_result': [
    {
      'id': 45,
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'chapter': 3,
      'start_verse': 16,
      'end_verse': 17,
      'chapter_verse_count': 36,
      'mode': 'continuous',
      'duration_seconds': 60,
      'character_count': 21,
      'correct_count': 20,
      'phonetic_correct_count': 0,
      'incorrect_count': 1,
      'omitted_count': 0,
      'reordered_count': 0,
      'accuracy': 0.95,
      'plan_id': 12,
      'started_at': '2026-01-01T00:00:00.000Z',
      'completed_at': '2026-01-01T00:01:00.000Z',
    },
  ],
  'recitation_verse_metric': [
    {
      'id': 46,
      'recitation_result_id': 45,
      'plan_id': 12,
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'chapter': 3,
      'verse': 16,
      'accuracy': 0.9,
      'duration_seconds': 30,
      'character_count': 10,
      'started_at': '2026-01-01T00:00:00.000Z',
      'completed_at': '2026-01-01T00:01:00.000Z',
    },
  ],
  'quiz_question': [
    {
      'id': 52,
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'chapter': 3,
      'verse': 16,
      'start_offset': 2,
      'end_offset': 4,
      'word': '世人',
      'part_of_speech': '名词',
      'meaning': '人类',
      'reference': '约翰福音 3:16',
      'source': 'model',
      'quality_version': 3,
      'answered': 1,
      'is_correct': 1,
      'answered_at': '2026-01-01T00:02:00.000Z',
      'created_at': '2026-01-01T00:00:00.000Z',
    },
  ],
  'quiz_result': [
    {
      'id': 53,
      'question_id': 52,
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'chapter': 3,
      'verse': 16,
      'correct': 1,
      'answered_at': '2026-01-01T00:02:00.000Z',
    },
  ],
  'achievement_unlock': [
    {
      'achievement_id': 'first_recitation',
      'unlocked_at': '2026-01-01T00:01:00.000Z',
      'source': 'recitation',
      'award_count': 1,
    },
  ],
  'ebbinghaus_settings': [
    {
      'id': 1,
      'enabled': 1,
      'pass_threshold': 0.8,
      'enabled_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
  ],
  'ebbinghaus_cycle': [
    {
      'id': 64,
      'source_result_id': 45,
      'source_plan_id': 12,
      'translation_id': 'cmn-cu89s',
      'book_id': 'JHN',
      'chapter': 3,
      'start_chapter': 3,
      'start_verse': 16,
      'end_chapter': 3,
      'end_verse': 17,
      'base_date': '2026-01-01',
      'status': 'active',
      'created_at': '2026-01-01T00:01:00.000Z',
    },
  ],
  'ebbinghaus_review': [
    {
      'id': 65,
      'cycle_id': 64,
      'interval_days': 1,
      'due_date': '2026-01-02',
      'status': 'pending',
      'result_id': null,
      'created_at': '2026-01-01T00:01:00.000Z',
    },
  ],
  'devotion_note': [
    {
      'date': '2026-01-01',
      'content': '今天的领受',
      'updated_at': '2026-01-01T01:00:00.000Z',
    },
  ],
  'app_setting': [
    {'setting_key': 'profile_name', 'setting_value': '路得'},
    {'setting_key': 'quiz_model_api_key', 'setting_value': 'secret-value'},
    {
      'setting_key': 'devotion_cached_manifest',
      'setting_value': 'cached-value',
    },
    {'setting_key': 'quiz_bank_revision', 'setting_value': 'cached-value'},
  ],
};
