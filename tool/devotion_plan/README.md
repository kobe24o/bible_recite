# 2026 年度灵修发布器

将经批准的中文全年日程转换为版本化发布清单：

```sh
dart run tool/devotion_plan/bin/publish_2026_devotion.dart --input tool/devotion_plan/data/2026-devotion-source.txt --output devotion-plans.json --revision 1
```

发布器拒绝缺失、重复或无效日期，以及未知书卷和超出真实章节/节数的范围。输出按日期排序，并通过同目录临时文件原子替换。
