# Feishu Cloud Plan Publisher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reusable Feishu Base template with validated chapter dropdowns, the 20-range classic-passages plan, the 66-range key-verses plan, and one anonymous read-only publishing URL.

**Architecture:** Generate three deterministic CSV imports from the repository scripture packs and the two user-provided Markdown files. Import them into normalized `章节目录`, `背诵计划`, and `计划经文` tables, then expose a flattened `App公开发布` view filtered to valid pushed records.

**Tech Stack:** Dart 3.12, `sqlite3`, Flutter test, Feishu Base web UI, Chrome browser automation.

## Global Constraints

- Do not import CUV or ESV reference text from the Markdown files; only references and titles are used.
- `圣经经典篇章.md` must yield exactly 20 ordered ranges.
- `每卷书钥节.md` must yield exactly 66 ordered ranges, preserving multi-verse endings.
- A published passage row stays within one book; a plan spans books through multiple rows.
- Chapter choices come from a complete valid Protestant-66 chapter catalog.
- Start and end verses must be positive and no larger than the selected chapter's shared publish maximum.
- The public publishing surface is one HTTPS Feishu independent-view URL with anonymous read-only access.
- No Feishu credential, cookie, app secret, or access token is written to the repository.

---

## File Structure

- Create `tool/cloud_plan/lib/cloud_plan_models.dart`: immutable source-plan and passage-reference types.
- Create `tool/cloud_plan/lib/markdown_plan_parser.dart`: deterministic extraction of the two supplied Markdown formats.
- Create `tool/cloud_plan/lib/feishu_csv_generator.dart`: scripture-pack catalog reader, validator, and CSV writer.
- Create `tool/cloud_plan/bin/generate_feishu_template.dart`: command-line entry point.
- Create `tool/cloud_plan/test/markdown_plan_parser_test.dart`: fixture-backed 20/66 parsing tests.
- Create `tool/cloud_plan/test/feishu_csv_generator_test.dart`: chapter bounds and CSV contract tests.
- Create `tool/cloud_plan/test/fixtures/classic_headings.md`: compact representative headings, including full chapter and partial ranges.
- Create `tool/cloud_plan/test/fixtures/key_verses.md`: compact representative key-verse entries, including multi-verse ranges.
- Generate `build/feishu_cloud_plan/章节目录.csv`: all valid chapters and shared verse maxima.
- Generate `build/feishu_cloud_plan/背诵计划.csv`: two initial plan records.
- Generate `build/feishu_cloud_plan/计划经文.csv`: 86 ordered passage rows.

---

### Task 1: Parse the two source Markdown formats

**Files:**
- Create: `tool/cloud_plan/lib/cloud_plan_models.dart`
- Create: `tool/cloud_plan/lib/markdown_plan_parser.dart`
- Create: `tool/cloud_plan/test/markdown_plan_parser_test.dart`
- Create: `tool/cloud_plan/test/fixtures/classic_headings.md`
- Create: `tool/cloud_plan/test/fixtures/key_verses.md`

**Interfaces:**
- Produces: `CloudPassageRef`, `CloudPlanDefinition`, `MarkdownPlanParser.parseClassic(String)`, and `MarkdownPlanParser.parseKeyVerses(String)`.
- Consumes: UTF-8 Markdown text only; no scripture body text is retained.

- [ ] **Step 1: Write parser fixtures containing exact boundary cases**

```markdown
## 1. 两条道路的抉择：《诗篇》第 1 篇 (全篇)
## 2. 尊主颂：《路加福音》第 1 章 46-56 节
## 3. 无微不至的鉴察：《诗篇》第 139 篇 1-12 节
```

```markdown
### 1. 《创世记》 (Genesis)
创世记1:1  起初，神创造天地。
### 2. 《民数记》 (Numbers)
民数记14:22-23  示例正文不会被保留。
```

- [ ] **Step 2: Write failing parser tests**

```dart
test('classic parser keeps full chapters and partial verse ranges', () {
  final plans = const MarkdownPlanParser().parseClassic(fixture);
  expect(plans, hasLength(3));
  expect(plans[0].startVerse, isNull);
  expect(plans[1].bookId, 'LUK');
  expect(plans[1].startVerse, 46);
  expect(plans[1].endVerse, 56);
});

test('key verse parser preserves a multi-verse ending', () {
  final plans = const MarkdownPlanParser().parseKeyVerses(fixture);
  expect(plans, hasLength(2));
  expect(plans[1].bookId, 'NUM');
  expect(plans[1].startVerse, 22);
  expect(plans[1].endVerse, 23);
});
```

- [ ] **Step 3: Run the focused tests and verify the missing implementation failure**

Run: `dart test tool/cloud_plan/test/markdown_plan_parser_test.dart -r expanded`

Expected: FAIL because `MarkdownPlanParser` and its models do not exist.

- [ ] **Step 4: Implement immutable reference models and strict Chinese-book mapping**

```dart
final class CloudPassageRef {
  const CloudPassageRef({
    required this.order,
    required this.bookId,
    required this.startChapter,
    required this.endChapter,
    this.startVerse,
    this.endVerse,
  });

  final int order;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final int? startVerse;
  final int? endVerse;
}

final class CloudPlanDefinition {
  const CloudPlanDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.passages,
  });

  final String id;
  final String title;
  final String description;
  final List<CloudPassageRef> passages;
}
```

The parser must recognize all 66 Chinese book names and throw `FormatException` for an unknown book, malformed range, duplicate order, or non-contiguous order. Full-chapter headings return null verse bounds so Task 2 can replace them with `1..sharedMaximum` from the chapter catalog.

- [ ] **Step 5: Run parser tests**

Run: `dart test tool/cloud_plan/test/markdown_plan_parser_test.dart -r expanded`

Expected: PASS, including the `NUM 14:22-23` assertion.

- [ ] **Step 6: Commit the parser**

```powershell
git add tool/cloud_plan/lib/cloud_plan_models.dart tool/cloud_plan/lib/markdown_plan_parser.dart tool/cloud_plan/test
git commit -m "feat: parse cloud memorization plan sources"
```

---

### Task 2: Generate the chapter catalog and validate all 86 references

**Files:**
- Create: `tool/cloud_plan/lib/feishu_csv_generator.dart`
- Create: `tool/cloud_plan/bin/generate_feishu_template.dart`
- Create: `tool/cloud_plan/test/feishu_csv_generator_test.dart`

**Interfaces:**
- Consumes: `CloudPlanDefinition` from Task 1 and the three SQLite packs under `assets/scripture/`.
- Produces: `FeishuTemplateGenerator.generate(TemplateGenerationRequest) -> TemplateGenerationSummary` and three UTF-8 BOM CSV files.

- [ ] **Step 1: Write failing catalog and validation tests**

```dart
test('catalog uses the minimum supported maximum verse', () {
  final entry = ChapterCatalogEntry(
    bookId: 'PSA',
    chapter: 1,
    simplifiedMaxVerse: 6,
    traditionalMaxVerse: 6,
    englishMaxVerse: 6,
  );
  expect(entry.publishMaxVerse, 6);
});

test('validator rejects a verse beyond the selected chapter', () {
  expect(
    () => validatePassage(
      const CloudPassageRef(
        order: 1,
        bookId: 'PSA',
        startChapter: 1,
        endChapter: 1,
        startVerse: 1,
        endVerse: 7,
      ),
      catalog,
    ),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run the generator tests and verify failure**

Run: `dart test tool/cloud_plan/test/feishu_csv_generator_test.dart -r expanded`

Expected: FAIL because the generator types do not exist.

- [ ] **Step 3: Implement chapter maximum queries**

For each pack, query every chapter with:

```sql
SELECT b.osis_id,
       b.ordinal,
       b.chapter_count,
       u.chapter,
       MAX(u.end_verse) AS max_verse
FROM books b
JOIN verse_unit u ON u.osis_book_id = b.osis_id
WHERE u.status = 'present'
GROUP BY b.osis_id, b.ordinal, b.chapter_count, u.chapter
ORDER BY b.ordinal, u.chapter
```

Merge entries by `(osis_id, chapter)`. Require all three packs to expose the same 66 books and chapter keys. Set `publishMaxVerse` to the minimum of the three pack maxima.

- [ ] **Step 4: Implement strict passage validation and full-chapter expansion**

```dart
CloudPassageRef expandAndValidate(
  CloudPassageRef input,
  Map<(String, int), ChapterCatalogEntry> catalog,
) {
  final start = catalog[(input.bookId, input.startChapter)];
  final end = catalog[(input.bookId, input.endChapter)];
  if (start == null || end == null) throw const FormatException('Unknown chapter');
  final startVerse = input.startVerse ?? 1;
  final endVerse = input.endVerse ?? end.publishMaxVerse;
  if (startVerse < 1 || startVerse > start.publishMaxVerse) {
    throw const FormatException('Start verse is outside the selected chapter');
  }
  if (endVerse < 1 || endVerse > end.publishMaxVerse) {
    throw const FormatException('End verse is outside the selected chapter');
  }
  if (input.startChapter > input.endChapter ||
      (input.startChapter == input.endChapter && startVerse > endVerse)) {
    throw const FormatException('Passage range is reversed');
  }
  return CloudPassageRef(
    order: input.order,
    bookId: input.bookId,
    startChapter: input.startChapter,
    endChapter: input.endChapter,
    startVerse: startVerse,
    endVerse: endVerse,
  );
}
```

- [ ] **Step 5: Implement deterministic CSV output**

Use UTF-8 BOM and RFC 4180 quoting. Emit these exact column orders:

```text
章节目录.csv: 章节键,经卷 OSIS,简体卷名,繁体卷名,英文卷名,章号,简体最大节数,繁体最大节数,英文最大节数,发布最大节数,正典顺序
背诵计划.csv: 计划 ID,计划名称,计划简介,是否推送,修订号,默认译本,默认开始日期,默认结束日期,来源名称,协议版本,标签
计划经文.csv: 条目 ID,所属计划,经文顺序,起始章节,起始节,终止章节,终止节
```

The two initial plan rows use IDs `classic-passages` and `key-verses-66`, `是否推送=是`, `修订号=1`, `默认译本=简体`, `来源名称=背诵助手官方`, and `协议版本=1`. Leave default dates empty so the user can choose them when creating a plan.

- [ ] **Step 6: Run generator tests**

Run: `dart test tool/cloud_plan/test/feishu_csv_generator_test.dart -r expanded`

Expected: PASS, including UTF-8 headers, catalog coverage, full-chapter expansion, and invalid-range rejection.

- [ ] **Step 7: Generate the actual import files**

Run:

```powershell
dart run tool/cloud_plan/bin/generate_feishu_template.dart --classic "D:\Personal\Downloads\圣经经典篇章.md" --key-verses "D:\Personal\Downloads\每卷书钥节.md" --output build\feishu_cloud_plan
```

Expected summary:

```text
chapters: 1189
plans: 2
passages: 86
classic-passages: 20
key-verses-66: 66
```

- [ ] **Step 8: Commit generator code, not generated build output**

```powershell
git add tool/cloud_plan
git commit -m "feat: generate Feishu cloud plan template data"
```

---

### Task 3: Create and populate the Feishu Base

**Files:**
- Read: `build/feishu_cloud_plan/章节目录.csv`
- Read: `build/feishu_cloud_plan/背诵计划.csv`
- Read: `build/feishu_cloud_plan/计划经文.csv`

**Interfaces:**
- Consumes: three validated CSV files from Task 2.
- Produces: a Feishu Base owned by the user's signed-in account with three populated tables.

- [ ] **Step 1: Open Feishu in the existing signed-in Chrome session and create a Base named `背诵计划发布中心`**

Create an empty Base, then import each CSV into a separate table with exact names `章节目录`, `背诵计划`, and `计划经文`. This is an external creation action already authorized by the user; do not alter either source Markdown file.

- [ ] **Step 2: Verify imported row counts before adding relations**

Expected counts:

```text
章节目录: 1189
背诵计划: 2
计划经文: 86
```

Stop if any count differs. Do not compensate by manually adding or deleting rows.

- [ ] **Step 3: Convert plan metadata fields to constrained types**

Configure `是否推送` as single select with only `是` and `否`; `默认译本` as single select with only `简体`, `繁体`, `英文`; `协议版本` as single select with only `1`; `修订号` as integer; and both default dates as date fields.

- [ ] **Step 4: Convert chapter catalog fields to constrained types**

Configure `经卷 OSIS` as single select with the 66 imported OSIS values. Configure chapter, maximum-verse, and canon-order fields as integers. Keep `章节键` as the primary display field so relations are searchable by `PSA.023｜诗篇 23`.

- [ ] **Step 5: Convert passage references to relations**

Convert `所属计划` to a single-record relation to `背诵计划.计划 ID`; convert `起始章节` and `终止章节` to single-record relations to `章节目录.章节键`; keep order and verse fields as integers.

- [ ] **Step 6: Verify relation conversion did not orphan records**

Every `计划经文` row must show exactly one linked plan, one linked start chapter, and one linked end chapter. The two plan groups must contain 20 and 66 linked passage rows.

---

### Task 4: Add lookups, range validation, and the public publishing view

**Files:**
- Modify externally: Feishu Base `背诵计划发布中心`

**Interfaces:**
- Consumes: normalized related records from Task 3.
- Produces: one flattened, filtered, anonymous read-only view URL.

- [ ] **Step 1: Add plan lookup fields to `计划经文`**

Add lookup fields for `计划 ID`, `计划名称`, `修订号`, `默认译本`, `默认开始日期`, `默认结束日期`, `来源名称`, `协议版本`, and `推送状态` from `所属计划`.

- [ ] **Step 2: Add chapter lookup fields to `计划经文`**

From `起始章节`, add `起始经卷`, `起始章号`, and `起始最大节数`. From `终止章节`, add `终止经卷`, `终止章号`, and `终止最大节数`.

- [ ] **Step 3: Add the range-validation formula**

Configure `范围校验` to return one of these exact values: `通过`, `缺少章节`, `起始节无效`, `终止节无效`, `单条范围不可跨卷`, or `范围顺序错误`. The conditions are evaluated in that order and enforce positive verses, chapter maxima, same-book passage rows, and canonical forward order.

- [ ] **Step 4: Create the `App公开发布` table view**

Filter to `推送状态=是` and `范围校验=通过`. Sort ascending by `计划 ID`, then `经文顺序`. Show only these columns in this exact order:

```text
协议版本,来源名称,计划 ID,计划名称,修订号,默认译本,默认开始日期,默认结束日期,经文顺序,起始经卷,起始章号,起始节,终止经卷,终止章号,终止节
```

- [ ] **Step 5: Enable independent sharing as anonymous read-only**

Create an independent share link for `App公开发布` and select `互联网上获得链接的人可阅读`. Do not grant edit, comment, form-submit, or copy-management permissions.

- [ ] **Step 6: Verify the public view in a signed-out context**

Open the link without relying on the Feishu account session. Confirm the view exposes exactly 86 rows, two plan IDs, and no internal relations, formulas, personal data, source scripture text, or credentials.

- [ ] **Step 7: Record the handoff values without committing credentials**

Report the Base title, public view URL, plan IDs, counts, and sharing mode to the user. The public URL may later become the App default source; do not commit it until the App sync implementation plan is executed and its parser test fixture is captured.

---

### Task 5: Final verification

**Files:**
- Test: `tool/cloud_plan/test/markdown_plan_parser_test.dart`
- Test: `tool/cloud_plan/test/feishu_csv_generator_test.dart`

**Interfaces:**
- Consumes: generator code and completed Feishu view.
- Produces: verified publisher template ready for team duplication.

- [ ] **Step 1: Run all cloud-plan generator tests**

Run: `dart test tool/cloud_plan/test -r expanded`

Expected: all tests PASS.

- [ ] **Step 2: Re-run generation and compare hashes**

Run the Task 2 generation command twice and compare SHA-256 hashes of all three CSV files. Expected: hashes are unchanged between runs.

- [ ] **Step 3: Validate representative multi-verse rows in Feishu**

Confirm the public view contains exact endings for `NUM 14:22-23`, `DEU 6:4-5`, `LAM 3:22-23`, `EPH 2:8-9`, and `1TH 5:16-18`.

- [ ] **Step 4: Validate removal semantics without destroying data**

Temporarily use a duplicate test plan row, switch `是否推送` from `是` to `否`, and confirm it disappears from `App公开发布` while remaining in `背诵计划`. Delete only this explicitly created test row after confirmation; do not alter the two production plans.

- [ ] **Step 5: Commit any verification-only test corrections**

```powershell
git add tool/cloud_plan
git commit -m "test: verify Feishu plan publisher data"
```

Only create this commit if verification required a real test correction; otherwise leave the repository unchanged.
