# 背诵助手

一款面向 Android、iOS、Windows 和 macOS 的离线圣经背诵应用。经文浏览、计划、背诵检查、统计和艾宾浩斯复习均保存在本机；语音识别使用本地 sherpa-onnx 模型。

## 背诵计划

- 内置《圣经经典篇章》（20 段）与《每卷书钥节》（66 段）两个跨卷计划。
- 每个计划可以选择简体中文、繁體中文或 English 译本。
- 云端计划可从公开 HTTPS JSON 地址同步，也可从本机 `.json` 文件导入。
- 云端计划的经卷、章节和节数不可修改；译本、开始日期和结束日期可以在本机调整。
- 已经导入本机的计划不会因为发布方取消推送或删除记录而被自动删除。

默认公开清单：

`https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/cloud-plans.json`

JSON 协议示例和正式数据见 [assets/cloud_plans.json](assets/cloud_plans.json)。不同团队只要生成相同结构的 JSON，就能在 App 的“云端来源”中填写自己的地址。

## 飞书发布流程

飞书多维表格负责编辑和审核，静态 JSON 负责 App 匿名读取。这样无需购买服务器，也不依赖飞书网页结构或用户登录。

从两份 Markdown 重新生成飞书模板：

```powershell
dart run tool/cloud_plan/bin/generate_feishu_template.dart `
  --classic "D:\Personal\Downloads\圣经经典篇章.md" `
  --key-verses "D:\Personal\Downloads\每卷书钥节.md" `
  --output build\feishu_cloud_plan
```

生成 App/公共仓库使用的 JSON：

```powershell
dart run tool/cloud_plan/bin/generate_cloud_plan_json.dart `
  --classic "D:\Personal\Downloads\圣经经典篇章.md" `
  --key-verses "D:\Personal\Downloads\每卷书钥节.md" `
  --output assets\cloud_plans.json
```

## 本地开发

```powershell
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

离线语音模型不放进普通 Git 历史，因为 `encoder.onnx` 超过 GitHub 的 100 MB 单文件限制。请按 [assets/models/README.md](assets/models/README.md) 下载项目 Release 中的模型包。

更完整的 Android 打包说明见 [docs/RELEASE.md](docs/RELEASE.md)。
