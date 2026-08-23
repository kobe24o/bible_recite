# 自定义背诵条目与子块 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以条目聚合多段经文，并支持可选拆分策略和子块移动。

**Architecture:** 保留 `plan_task` 排期语义，新增 SQLite 子表 `plan_task_block`，由仓储装配 blocks；领域拆分器生成条目组，页面与背诵链只消费条目。

**Tech Stack:** Flutter/Dart、sqlite3、flutter_test。

**Spec:** `docs/superpowers/specs/2026-08-23-plan-entry-blocks-design.md`

## Global Constraints

- 精确范围必须保存为起止章节，未选空隙不得纳入背诵或测验。
- 仅本地、未完成、未锁定条目可调整。
- 多条新条目一天一条；每 N 节绝不跨章。

### Task 1: 子块模型、策略与迁移

- [x] 新增条目子块模型与按卷、章、节、每 N 节分组测试。
- [x] 新增 `plan_task_block` 表并将旧任务迁移为单子块。

### Task 2: 创建、移动、展示和背诵

- [x] 默认多选创建一条含精确子块的背诵条目。
- [x] 在计划编辑器提供五种拆分策略。
- [x] 支持把子块移入其他条目、清除空源条目并压缩日期。
- [x] Today/详情聚合显示，背诵链仅执行当前条目的 blocks。

### Task 3: 验证

- [x] 运行领域、仓储、编辑器、Today、详情与背诵链回归测试。
- [ ] 运行静态分析、差异检查并提交隔离分支。
