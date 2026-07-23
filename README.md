# 背诵助手

一款面向 Android、iOS、Windows 和 macOS 的离线圣经背诵应用。经文浏览、计划、背诵检查、统计和艾宾浩斯复习均保存在本机；语音识别使用本地 sherpa-onnx 模型。

## 更新日志

### 2026-07-23 · 1.0.10+11

- 修复单个 CDN 缓存旧更新清单时导致“检查不到更新”的问题：App 会验证所有可访问来源并采用其中版本最高的签名清单，GitHub Raw 为首选来源，CDN 仅作回退。

### 2026-07-23 · 1.0.9+10

- 背诵页会清楚显示当前正在背诵的经卷、章节和节号；一次包含多节时，每节经文独立分框，左侧标明所属经文位置。
- Android 更新包下载优先使用加速源，并保留 GitHub Release 直连回退。无论来源如何，App 都会先校验 APK 的 SHA-256、版本与签名证书后才允许安装。

### 2026-07-23 · 1.0.7+8

- App 启动后及每 30 分钟检查一次更新：Wi-Fi 环境会自动下载并校验新版本，不会自动弹出安装；下载完成后由用户在“关于”页自行点击安装。
- 下载过程中如果检测到更高版本，会取消旧下载并切换为最新版本。移动网络只提示可用版本，用户点击后才开始下载。
- 计划日程和首页今日任务均可直接进入背诵；计划背诵结束后可继续下一项计划。新增“忽略后鼻音”开关，默认开启。

### 2026-07-23 · 1.0.8+9

- 背诵页显示当前经卷与章节。离线语音模型在首次进入背诵时准备一次，并在 App 运行期间复用，后续背诵无需重复准备。

## 自动更新说明

“我的 → 关于”会显示版本、简短更新说明、下载进度和安装入口。更新包优先从加速源下载，失败后回退到 GitHub Release；无论来源如何，都会在本机校验完整性、版本和签名。Wi-Fi 自动下载不会触发系统安装器，避免打断使用。移动网络始终由用户确认下载。

### 2026-07-23

- 中文背诵在结束后启用离线拼音同音纠正：简体和繁体经文使用无声调拼音并优先采用内置圣经多音字词典；实时识别仍保持原字对齐。结果页和最近背诵都会显示同音修正数量，统计会持久化保存。
- 调整已有计划期限时，已完成任务保持在原日期，未完成经文按剩余可用天数和字符量重新均分；“最近背诵”默认折叠为五条。
- 修复 Android 自动更新：发布后自动生成并签名更新清单，写入公开回退源；检查更新不再依赖不存在的分支。

### 2026-07-22

- 阅读页支持长按复选经文；选中内容可新建背诵计划或追加到已有本地计划，计划可跨章、跨卷，并可按天查看安排。
- 新增“关于”页面和安全 Android 更新流程：仅接受签名更新清单，完成 APK 校验、版本与证书检查后才交由系统安装器确认；更新在 Wi-Fi 下直接下载，蜂窝网络需用户确认。
- 中文背诵评分加入离线拼音对齐基础：简体和繁体经文使用无声调拼音，并优先采用内置圣经多音字词典。

## 背诵计划

- 内置《圣经经典篇章》（20 段）与《每卷书钥节》（66 段）两个跨卷计划。
- 每个计划可以选择简体中文、繁體中文或 English 译本。
- 云端计划可从公开 HTTPS JSON 地址同步，也可从本机 `.json` 文件导入。
- 云端计划的经卷、章节和节数不可修改；译本、开始日期和结束日期可以在本机调整。
- 已经导入本机的计划不会因为发布方取消推送或删除记录而被自动删除。

默认公开清单：

`https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/cloud-plans.json`

App 会在该 CDN 不可用时依次回退到 Fastly、jsDelivr CDN 和同一仓库的
GitHub Raw 地址；旧版本中已保存的官方地址也会自动使用相同的回退顺序。

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

以后直接从飞书发布时，需要导出 `背诵计划` 表和 `计划经文 → 发布编辑` 视图两份 CSV：

```powershell
dart run tool/cloud_plan/bin/publish_feishu_export.dart `
  --plans "背诵计划发布中心_背诵计划.csv" `
  --passages "背诵计划发布中心_计划经文_发布编辑.csv" `
  --output "cloud-plans.json"
```

发布器只输出 `是否推送=是` 且 `范围校验=通过` 的记录，并在任何校验失败时保留原输出文件。完整导出步骤和三平台下载包构建方式见 [tool/cloud_plan/README.md](tool/cloud_plan/README.md)。

## 本地开发

```powershell
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

离线语音模型不放进普通 Git 历史，因为 `encoder.onnx` 超过 GitHub 的 100 MB 单文件限制。请按 [assets/models/README.md](assets/models/README.md) 下载项目 Release 中的模型包。

更完整的 Android 打包说明见 [docs/RELEASE.md](docs/RELEASE.md)。
