import 'dart:io';

import 'package:test/test.dart';

import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';

// ignore: avoid_relative_lib_imports
import '../lib/feishu_export_json.dart';

void main() {
  group('FeishuExportJsonPublisher', () {
    test('publishes only pushed plans from the publisher edit view', () {
      final directory = Directory.systemTemp.createTempSync('feishu-publish-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final output = File('${directory.path}/cloud-plans.json');

      final summary = const FeishuExportJsonPublisher().publish(
        FeishuExportJsonRequest(
          plansCsvPath: 'tool/cloud_plan/test/fixtures/feishu_plans.csv',
          passagesCsvPath:
              'tool/cloud_plan/test/fixtures/feishu_publisher_edit.csv',
          outputPath: output.path,
        ),
      );

      expect(summary.planCount, 1);
      expect(summary.passageCount, 2);
      final source = output.readAsStringSync();
      final manifest = CloudPlanManifest.parse(source);
      expect(manifest.publisher, '测试团队');
      expect(manifest.plans, hasLength(1));
      final plan = manifest.plans.single;
      expect(plan.id, 'plan-cloud');
      expect(plan.title, '跨卷计划，示例');
      expect(plan.description, '第一行\n第二行');
      expect(plan.revision, 2);
      expect(plan.defaultTranslationId, 'cmn-cu89s');
      expect(plan.defaultStartDate, DateTime(2026, 7, 20));
      expect(plan.defaultEndDate, DateTime(2026, 8, 5));
      expect(plan.passages.map((item) => item.order), [1, 2]);
      expect(plan.passages.first.bookId, 'GEN');
      expect(plan.passages.last.bookId, 'JHN');
      expect(plan.passages.last.startVerse, 16);
      expect(plan.passages.last.endVerse, 18);
    });

    test('rejects a failed range check without replacing existing JSON', () {
      final directory = Directory.systemTemp.createTempSync('feishu-invalid-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final plans = File('${directory.path}/plans.csv')
        ..writeAsStringSync(
          '''计划 ID,计划名称,是否推送,修订号,默认译本,协议版本\nplan-a,计划 A,是,1,繁体,1\n''',
        );
      final passages = File('${directory.path}/passages.csv')
        ..writeAsStringSync(
          '''所属计划,经文顺序,起始章节,起始节,终止章节,终止节,范围校验,起始经卷,起始章号,终止经卷,终止章号\nplan-a,1,GEN.001｜创世记 1,1,EXO.001｜出埃及记 1,2,单条范围不可跨卷,GEN,1,EXO,1\n''',
        );
      final output = File('${directory.path}/cloud-plans.json')
        ..writeAsStringSync('{"keep":true}\n');

      expect(
        () => const FeishuExportJsonPublisher().publish(
          FeishuExportJsonRequest(
            plansCsvPath: plans.path,
            passagesCsvPath: passages.path,
            outputPath: output.path,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('范围校验'),
          ),
        ),
      );
      expect(output.readAsStringSync(), '{"keep":true}\n');
    });

    test(
      'parses BOM, quoted commas, embedded newlines, and escaped quotes',
      () {
        final records = parseRfc4180Csv(
          '\uFEFF名称,说明\r\n"甲,乙","第一行\r\n第二行，含""引号"""\r\n',
        );

        expect(records, [
          ['名称', '说明'],
          ['甲,乙', '第一行\r\n第二行，含"引号"'],
        ]);
      },
    );

    test('requires unique passage order values for each published plan', () {
      final directory = Directory.systemTemp.createTempSync('feishu-order-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final plans = File('${directory.path}/plans.csv')
        ..writeAsStringSync(
          '''计划 ID,计划名称,是否推送,修订号,默认译本,协议版本\nplan-a,计划 A,是,1,英文,1\n''',
        );
      final passages = File('${directory.path}/passages.csv')
        ..writeAsStringSync(
          '''所属计划,经文顺序,起始章节,起始节,终止章节,终止节,范围校验\nplan-a,1,GEN.001｜创世记 1,1,GEN.001｜创世记 1,1,通过\nplan-a,1,JHN.001｜约翰福音 1,1,JHN.001｜约翰福音 1,2,通过\n''',
        );

      expect(
        () => const FeishuExportJsonPublisher().publish(
          FeishuExportJsonRequest(
            plansCsvPath: plans.path,
            passagesCsvPath: passages.path,
            outputPath: '${directory.path}/output.json',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
