# 飞书背诵计划发布器

这个工具把飞书多维表格中的计划转换为 App 可读取的 `cloud-plans.json`。它只读本地 CSV，不需要飞书开放平台应用、服务器或付费服务。

## 导出两份 CSV

每次发布都需要两份文件：

1. 在 `背诵计划` 表中导出 CSV。它提供计划名称、是否推送、修订号、默认译本、预置日期等元数据。
2. 打开 `计划经文` 表，切换到 **`发布编辑`** 视图，再导出当前视图 CSV。它提供经文顺序和起止范围。

第二份文件必须来自 `发布编辑` 视图，不是 `App公开发布` 视图。发布器会检查 `范围校验=通过`，并只输出 `是否推送=是` 的计划。

## 运行

下载对应平台的 `cloud-plan-publisher` 后，在终端运行：

```text
cloud-plan-publisher \
  --plans "背诵计划发布中心_背诵计划.csv" \
  --passages "背诵计划发布中心_计划经文_发布编辑.csv" \
  --output "cloud-plans.json"
```

Windows PowerShell 示例：

```powershell
.\cloud-plan-publisher-windows-x64.exe `
  --plans "$HOME\Downloads\背诵计划发布中心_背诵计划.csv" `
  --passages "$HOME\Downloads\背诵计划发布中心_计划经文_发布编辑.csv" `
  --output ".\cloud-plans.json"
```

已安装 Dart 的用户也可以直接从源码运行：

```powershell
dart run tool/cloud_plan/bin/publish_feishu_export.dart `
  --plans "背诵计划发布中心_背诵计划.csv" `
  --passages "背诵计划发布中心_计划经文_发布编辑.csv" `
  --output "cloud-plans.json"
```

命令成功后会显示计划数和经文数。校验失败会指出计划和字段，原有输出文件不会被替换。

## 发布到手机

把生成的 `cloud-plans.json` 覆盖到公开发布仓库，并提交、推送：

```powershell
git add cloud-plans.json
git commit -m "publish: update cloud plans"
git push
```

手机 App 下次同步公开 URL 时，会拉取其中 `push=true` 的计划。手机里已经导入的计划不会因云端取消推送或删除而自动消失。

修改计划名称、日期、译本或经文范围后，应增加该计划的 `修订号`；否则手机会把它视为同一版本。计划可以用多条经文跨越不同经卷，但单条起止范围必须在同一卷内。

## 跨平台构建

GitHub Actions 工作流 `.github/workflows/cloud-plan-publisher-release.yml` 可手动运行，生成 Windows、macOS、Linux 三个平台的下载包。推送形如 `cloud-plan-publisher-v1.0.0` 的标签时，还会自动创建 GitHub Release。
