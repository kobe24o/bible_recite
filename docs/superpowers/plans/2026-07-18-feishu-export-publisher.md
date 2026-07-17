# Feishu Export Publisher Implementation Plan

**Goal:** Convert two Feishu Base CSV exports into the versioned `cloud-plans.json` feed on Windows, macOS, and Linux.

**Architecture:** Read plan metadata from the `背诵计划` table export and passage ranges from the `计划经文 → 发布编辑` view export. Validate all published rows before atomically replacing the JSON output. Package the pure-Dart CLI for three desktop platforms in GitHub Actions.

## Contract

- The passage CSV must be exported from `计划经文 → 发布编辑`, not `App公开发布`.
- Only plans whose `是否推送` value is `是` are emitted.
- A plan may span books through multiple passage rows; one passage row must stay in one book.
- `范围校验`, when exported, must equal `通过`.
- Published plans require unique positive revisions, IDs, and passage orders.
- Failed validation leaves an existing output file unchanged.

## Tasks

- [ ] Add failing fixture-backed tests for filtering, link parsing, range preservation, validation, and atomic output.
- [ ] Implement an RFC 4180 CSV reader and strict Feishu export converter.
- [ ] Add a `publish_feishu_export.dart` command-line entry point.
- [ ] Document the exact two-view export and GitHub publishing workflow.
- [ ] Add Windows, macOS, and Linux executable builds in GitHub Actions.
- [ ] Run focused tests, all cloud-plan tests, analyzer, and a compiled executable smoke test.
- [ ] Commit, merge, and push the completed publisher.
