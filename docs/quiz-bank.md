# 共享答题题库

答题题库只包含题干所需的经文、位置、词语、词性与提示解释；不包含 API Key、语音内容、答题结果、正确率或其他个人信息。

## 使用方式

在“我的 → 共享答题题库”中：

- **导出**：生成 `BibleRecite-quiz-bank.json`，可分享给其他用户。
- **导入**：校验题目位置后按“译本、卷、章、节、开始、结束”去重。新题目始终标记为未作答；已存在题目及其本机答题历史不变。
- **同步题库**：先获取很小的 `quiz-bank.index.json`。索引 ETag 未变化时不会下载题库；有变化时仅下载 SHA-256 不同的分片并校验后导入。地址顺序为 gcore.jsdelivr、fastly.jsdelivr、cdn.jsdelivr，最后回退 `raw.githubusercontent.com`。

题库同步只有下载行为。想贡献题目时，请先导出并提交到题库仓库，不会自动上传个人数据。

## 合并多个导出文件

在项目根目录执行：

```powershell
.\.toolchains\flutter\bin\dart.bat run tool\merge_quiz_banks.dart -o merged-quiz-bank.json bank-a.json bank-b.json
```

脚本会校验每个 JSON，按题目唯一位置去重，并输出合并数量。合并产物可直接导入 App，也可用于维护云端题库分片。更新云端分片时必须同步更新 `quiz-bank.index.json` 中的文件字节数、SHA-256 和 revision。
