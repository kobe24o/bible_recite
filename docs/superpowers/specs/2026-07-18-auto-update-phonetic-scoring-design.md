# 自动升级、最近背诵折叠与中文同音评分设计

## 目标

本次改动包含三个彼此独立、通过明确接口协作的功能：

1. “我的”页面默认只展示最近 10 条背诵记录，记录较多时允许展开和收起，并在页面底部增加“关于”入口。
2. Android 在“关于”页自动检查正式的 BibleRecite Release，支持 CDN 下载、断点续传、完整性校验和拉起系统安装；iOS、Windows、macOS 只展示版本与 Release 链接。
3. 中文背诵在用户点击“结束背诵”后进行无声调拼音对齐。同音字计为正确并显示目标经文中的正确汉字；读音不同的位置保留 ASR 转录文字，再据此计算准确率。

本次不增加账号、云同步、后台强制更新、静默安装或云端语音识别。除主动检查更新和下载 APK 外，背诵、评分、经文和统计继续完全离线。

## 已确认的产品规则

- Android 支持完整的应用内更新流程；其他平台不下载或安装应用包。
- 打开“关于”页时检查更新，不在应用启动时自动弹窗打扰用户。
- 只识别包含 `BibleRecite-<version>.apk` 的正式 Release；忽略 Draft、Pre-release、离线模型和云计划发布工具。
- Wi-Fi 下点击“立即更新”后直接下载；移动网络下先显示包大小并要求确认。
- R2 是主下载源，GitHub Release 是备用源，不使用不可控的第三方 GitHub 代理。
- R2 只保留最近 10 个 APK；GitHub Release 永久保留全部发布记录。
- `versionName` 增加属于新版本；`versionName` 相同且 `buildNumber` 增加也属于新版本。
- 中文同音判断忽略声调，只比较上下文确定后的无声调拼音音节。
- 实时阶段保留 ASR 原始文字；只有点击“结束背诵”后才进行同音修正和最终评分。
- 中文同音字与原字都计为正确；英文继续使用现有精确文本评分。

## 页面设计

### 最近背诵

- “最近背诵”默认查询并展示最新 10 条记录。
- 总记录数不超过 10 时不显示展开按钮。
- 超过 10 条时显示“展开全部（共 N 条）”。
- 展开后使用分页查询和惰性列表加载剩余记录，避免一次创建大量卡片。
- 展开状态只在当前页面实例内保存；重新进入“我的”时恢复为折叠状态。
- 展开后显示“收起”，收起时回到最新 10 条。
- 页面从当前 `SingleChildScrollView` 调整为可惰性构建的滚动结构，但不改变艾宾浩斯设置、汇总卡和成就卡的业务含义。
- 即使没有背诵记录，“关于”入口也必须显示。

### 关于页

“我的”页面底部增加“关于”卡片，点击进入独立路由 `/about`。页面包含：

- 应用图标与应用名称。
- 当前 `versionName` 和 `buildNumber`，格式为 `1.0.4（构建 7）`。
- 当前平台的更新能力说明。
- 进入页面后自动开始一次更新检查。
- 检查中、已是最新版、发现新版、检查失败四种明确状态。
- 发现新版时展示版本、build、发布日期、APK 大小和 Release 更新说明。
- Android 显示“立即更新”；其他平台显示“查看 Release”。
- 下载中显示百分比、已下载大小、总大小、当前速度和“取消”。
- 已下载且校验通过时显示“安装更新”。如果用户刚完成未知来源授权，则自动继续打开系统安装器。
- 用户取消系统安装后保留已校验 APK，允许再次点击安装而不重复下载。

## 更新模块边界

新增独立的 `features/update` 功能域：

```text
features/update/
├─ domain/
│  ├─ app_version.dart
│  ├─ update_manifest.dart
│  └─ update_status.dart
├─ application/
│  └─ update_controller.dart
├─ data/
│  ├─ update_feed_client.dart
│  ├─ resumable_downloader.dart
│  └─ update_verifier.dart
└─ presentation/
   └─ about_screen.dart
```

职责约束：

- `AppVersion` 负责解析和比较语义版本及 build，不依赖页面。
- `UpdateFeedClient` 只负责按顺序获取更新清单并验证清单签名。
- `ResumableDownloader` 只负责 URL 回退、Range/ETag 续传、进度和取消。
- `UpdateVerifier` 负责文件大小、SHA-256 和清单字段一致性；Android 包名、版本和证书检查委托给原生层。
- `UpdateController` 组织状态机，不直接包含 HTTP、文件或 Android Intent 细节。
- `AboutScreen` 只渲染状态并发出检查、下载、取消和安装意图。

这些接口允许测试使用内存清单、临时文件、假下载器和假安装器，不依赖真实 GitHub、R2 或系统安装界面。

## 版本规则

更新比较使用有序二元组 `(versionName, buildNumber)`：

1. 先按语义版本规则比较 `versionName`。
2. 远端 `versionName` 更高时属于新版本。
3. `versionName` 相同时，远端 `buildNumber` 更高才属于新版本。
4. 远端 `versionName` 更低时，即使 build 更高也拒绝为更新，防止发布配置错误造成回滚。
5. 相同版本和 build 不重复提示。

GitHub Actions 为每个新提交分配单调递增的有效 build：

- `versionName` 取自 `pubspec.yaml`。
- 首次发布时有效 build 至少等于 `pubspec.yaml` 的 build。
- 后续新提交使用 `max(pubspec build, GitHub run number, 已发布 build + 1)`。
- 更新清单记录 `sourceCommit`。同一 Git commit 的工作流重跑复用已分配 build，不制造重复更新。
- 工作流拒绝发布低于当前清单 `versionName` 的版本。
- 云端构建显式将有效 build 传给 Android 和 iOS 构建命令，并在 APK 元数据检查中验证。
- 本地正式打包脚本先读取更新清单，选择不低于当前发布 build 的有效 build；离线时必须由调用者显式指定高于已发布版本的 build，不能悄悄生成可能无法覆盖安装的正式包。

## 更新清单

发布系统生成协议版本为 1 的签名更新信封。信封是一个 JSON 对象，包含 Base64 编码的原始 payload 和 Ed25519 签名：

```json
{
  "protocol": 1,
  "payload": "<base64-json-bytes>",
  "signature": "<base64-ed25519-signature>"
}
```

payload 至少包含：

- `versionName`
- `buildNumber`
- `sourceCommit`
- `publishedAt`
- `releaseNotes`
- `releasePageUrl`
- `android.packageName`，固定为 `app.biblerecite`
- `android.fileName`
- `android.size`
- `android.sha256`
- `android.signingCertificateSha256`
- `android.urls`，R2 在前，GitHub Release 在后

使用单文件签名信封可避免 `latest.json` 与单独签名文件在 CDN 更新时短暂不一致。App 内只嵌入 Ed25519 公钥，发布私钥只保存在 GitHub Actions Secret 中。App 必须先对 payload 原始字节验签，再解析其中 JSON；验签失败的清单不得用于展示或下载。

更新清单发布到两个读取位置：

1. R2 自定义域名下的 `updates/latest.json`，作为主源并设置短缓存时间。
2. GitHub 的独立 `update-feed` 分支，通过 jsDelivr 多节点和 GitHub Raw 作为清单备用源。

版本化清单和 APK 使用不可变长缓存；`latest.json` 使用短缓存和缓存刷新。更新清单分支由 GitHub Actions 的 `GITHUB_TOKEN` 写入，不触发移动端构建工作流。

## Cloudflare R2 发布

GitHub Actions 使用 R2 的 S3 兼容接口。写入凭据只存在于仓库 Secrets：

- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_PUBLIC_BASE_URL`
- `UPDATE_MANIFEST_PRIVATE_KEY`

App 和仓库源代码中不得出现任何 R2 写入凭据或清单私钥。

发布顺序固定为：

1. 测试、静态分析、双平台构建。
2. 校验 Android 包名、有效 build 和固定 APK 证书。
3. 创建 GitHub Release 并上传 APK、IPA 与校验文件。
4. 上传版本化 APK 到 R2。
5. 生成并签署版本化更新信封。
6. 写入 GitHub `update-feed` 分支的版本化清单和 `latest.json`。
7. 最后替换 R2 的 `updates/latest.json`。
8. 在最新指针成功后清理 R2 中第 11 个及更早的 APK；清理失败记录为警告，不撤销已经可用的新版本。

在步骤 7 之前失败时，旧 `latest.json` 保持不变，用户不会看到未完整上传的新版本。GitHub Release 已成功但 R2 同步失败时，发布任务整体标记失败以便处理，但已发布的旧更新源仍可用。

## Android 下载与安装

### 下载

- 文件保存在应用专属缓存/支持目录，不申请共享存储权限。
- 临时文件使用 `.part` 后缀，并保存 URL、ETag、期望大小和已下载字节数。
- 恢复下载时发送 `Range` 和 `If-Range`；服务器不接受范围请求或 ETag 改变时从零开始。
- R2 出现 DNS、连接、超时、HTTP 或内容范围错误时自动切换 GitHub Release。
- 切换来源前必须确认两个来源对应同一清单中的同一文件、大小和 SHA-256。
- Wi-Fi 和移动网络判断只用于交互确认，不能把“连接到 Wi-Fi”误当成“互联网一定可用”。
- 用户取消后保留可续传的 `.part` 文件；清单版本改变时删除旧 partial。

### 安装前验证

下载完成后必须依次通过：

1. 实际文件大小与清单一致。
2. APK SHA-256 与清单一致。
3. APK 包名等于 `app.biblerecite`。
4. APK 的 `versionName` 和 `versionCode` 等于清单。
5. APK 签名证书 SHA-256 等于永久发布证书：
   `4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7`。
6. APK 版本严格高于当前已安装版本。

任一检查失败都删除最终 APK 和相关 partial，记录不含敏感信息的原因，并禁止打开安装器。

### 原生安装边界

Flutter 通过受限平台接口调用 Android 原生实现，原生层负责：

- 使用 PackageManager 读取未安装 APK 的包名、版本和签名。
- 检查 `canRequestPackageInstalls`。
- 在缺少权限时打开当前应用的“安装未知应用”设置页。
- 使用 `FileProvider` 生成 `content://` URI 并授予临时读取权限。
- 使用系统 Intent 打开 APK 安装确认页。

Manifest 只增加完成此流程必需的 `REQUEST_INSTALL_PACKAGES`、FileProvider 和查询声明。App 不请求 `INSTALL_PACKAGES`，不尝试静默安装。用户拒绝授权或取消安装属于正常状态，不显示为应用崩溃。

## 中文无声调评分

### 比较器边界

保留 `RecitationAlignment` 作为页面和统计层使用的结果模型，在其内部或相邻领域层增加策略：

```text
features/recitation/domain/
├─ recitation_alignment.dart
├─ exact_text_comparator.dart
├─ mandarin_phonetic_comparator.dart
└─ bible_pronunciation_lexicon.dart
```

- 简体和繁体中文译本使用 `MandarinPhoneticComparator`。
- 英文和其他非中文内容使用 `ExactTextComparator`，行为与现有实现一致。
- 经文仓库、计划和艾宾浩斯只接收最终结果，不依赖拼音库。
- 拼音转换完全离线，使用支持词组多音字和自定义词典的本地实现。

### 对齐算法

结束背诵后执行以下流程：

1. 保存本次 ASR 原始转录字符串供当前页面使用。
2. 目标经文和转录分别去除不参与评分的空白与标点，同时保留映射到原字符串的位置。
3. 按完整短语上下文生成无声调拼音音节；不能转换的字符保留为精确比较单元。
4. 使用支持相邻转置的动态规划对齐目标单元和转录单元。
5. 相同汉字是最高优先级零代价匹配；汉字不同但上下文拼音相同是次优先级零错误匹配。
6. 当多个路径错误数相同时，按“精确匹配更多、同音匹配更多、编辑操作更少”的顺序选择，避免重复音节导致不稳定结果。
7. 继续区分替换、删除、插入和相邻转置。
8. 将结果投影回带标点的目标经文布局。

不得使用“多音字任意候选拼音与对方相交就算正确”的规则。多音字必须先由词组上下文和圣经专用词典确定读音；转换失败时回退为精确汉字比较，不能过度放宽。

### 展示与准确率

新增 `phoneticCorrect` token 类型：

- `correct`：ASR 汉字与目标汉字相同，显示目标汉字，绿色。
- `phoneticCorrect`：汉字不同但无声调拼音相同，显示目标汉字，绿色。
- `incorrect`：读音不同，显示 ASR 汉字，红色。
- `omitted`：漏读，沿用漏字显示。
- `reordered`：错序，沿用橙色显示。
- `pending`：实时阶段尚未读到的位置。
- `formatting`：标点和格式字符。

实时识别期间不做拼音修正，错误位置继续显示 ASR 原字。用户点击“结束背诵”后才切换为最终拼音对齐结果。

最终准确率为：

```text
(exactCorrectCount + phoneticCorrectCount) / targetComparableLength
```

结束页同时显示总准确率、原字正确数和同音修正数。漏读、错读、错序和多读的统计语义保持不变。

### 圣经读音词典

新增独立资产 `assets/pronunciation/bible_pinyin_overrides.json`，内容只描述短语到无声调音节的映射。初始词典覆盖测试和现有经文中发现的常见多音词、人名及地名。该词典：

- 不与 `ScriptureRepository` 或译本文本硬编码耦合。
- 可独立增加条目而不改变评分算法。
- 同时适用于简体和繁体键，或在加载时建立等价键。
- 对非法音节、字符数不匹配和重复冲突执行启动时校验。

## 统计数据兼容

SQLite 增加 `phonetic_correct_count INTEGER NOT NULL DEFAULT 0`。

- 现有 `correct_count` 继续表示计入准确率的总正确数，即精确正确加同音正确。
- 精确正确数可由 `correct_count - phonetic_correct_count` 得到。
- 旧记录迁移后 `phonetic_correct_count = 0`，原有准确率和成就不变化。
- 新记录的 `accuracy` 使用总正确数计算，因此艾宾浩斯阈值、平均准确率和准确率成就自然采用已确认的新评分规则。
- 本次不持久化完整录音或转录文本，保持数据库小且不扩大隐私数据范围。

数据库升级必须在事务内完成并提升明确的 `user_version`。升级失败不得删除或重建用户数据库。

## 错误处理

### 更新

- 无网络或所有清单源失败：显示“暂时无法检查更新”，不影响其他页面。
- 清单协议不支持、Base64 非法、Ed25519 验签失败或字段非法：显示安全校验失败，不回退到未签名数据。
- 已是最新版：清理不再对应当前清单的旧 APK/partial，并显示最新版状态。
- 移动网络：用户拒绝后保持发现新版状态，可稍后重试。
- 存储空间不足：下载前尽量预检，写入失败时显示所需空间并保留可安全续传的数据。
- 下载取消：保持可续传状态。
- 文件或 APK 验证失败：删除损坏文件，禁止安装并提供重新下载。
- 未授权未知来源安装：引导到系统设置，返回后重新检查权限。
- 用户取消安装：保留已验证文件并提供再次安装。
- 安装成功后：新版本首次启动时删除旧 APK、partial 和过期下载元数据。

### 评分

- 拼音库对某字符或词组转换失败：该单元回退精确比较。
- 专用词典加载失败：记录本地错误并使用基础词典，不能阻止背诵。
- 对齐异常：回退现有精确比较并允许结果保存，不能丢失已完成的背诵。
- 中文以外译本不得因拼音依赖或词典状态改变结果。

## 测试

### 更新领域与数据测试

- 语义版本高于、低于、相等以及 build 高于、低于、相等。
- 预发布或非法版本字符串拒绝。
- 正确签名清单、篡改 payload、错误公钥、非法 Base64、未知协议。
- 只接受正式 BibleRecite APK，忽略其他 Release 资产。
- R2 成功、R2 失败回退 GitHub、所有来源失败。
- Range 续传、ETag 改变重下、服务器忽略 Range、取消后恢复。
- 大小、SHA-256、包名、版本、build 和证书各自不匹配时阻止安装。
- 同一 commit 重跑复用 build，新 commit build 单调递增，版本回退时工作流失败。

### 页面测试

- 0、10、11 和大量最近背诵记录时的折叠、展开、分页和收起。
- 无统计数据时仍显示“关于”。
- 关于页显示真实版本和 build，并在进入时检查。
- 检查中、最新版、新版、失败、移动网络确认、下载、取消、校验、授权和安装状态。
- 非 Android 平台只显示 Release 链接。

### 拼音评分测试

- 汉字完全相同。
- 同音同调和同音不同调均正确。
- 声母或韵母不同仍错误。
- 简体目标、繁体目标及相互转录。
- 词组上下文多音字和圣经专用词典。
- 不允许任意多音候选造成误判。
- 中间漏字、多字、连续错字、重复音节和相邻错序。
- 同音位置显示目标字，错音位置显示 ASR 字。
- 实时阶段不修正，结束后才修正。
- 英文所有现有对齐测试结果不变。
- 旧数据库迁移后统计与成就不变，新记录保存同音正确数。
- 长章节对齐在目标移动设备上没有明显界面卡顿；必要时结束评分移出 UI 同步路径。

### 最终验收门槛

- 全量 `flutter test` 通过。
- `flutter analyze` 无问题。
- Android 与 iOS Release 构建通过。
- 云端 APK 的版本、build、包名和证书检查通过。
- GitHub Release、R2 APK、签名更新清单和备用清单均可读取。
- 从已安装旧版在真实 Android 手机上完成：检查新版、R2 下载、SHA/证书验证、未知来源授权、覆盖安装、SQLite 数据保留。
- 模拟 R2 失败后在真实手机上完成 GitHub Release 回退下载。
- 真机完成至少一条包含同音字、错音字和漏读的中文背诵，页面校正和保存统计符合本设计。

## 实施范围与前置配置

实施分为两个可独立交付的工作包：

1. 最近背诵折叠、关于页、版本规则、R2 发布和 Android 更新。
2. 中文无声调拼音对齐、专用词典、统计迁移和结果展示。

工作包 1 上线前需要用户提供或授权创建 Cloudflare R2 存储桶、自定义公开域名及最小权限的 S3 API Token。Codex 只把凭据写入 GitHub Actions Secrets，不写入仓库、日志或 App。清单 Ed25519 私钥由发布环境生成并存为 Secret，公钥提交到 App。

两个工作包都完成并通过各自测试后再合并为一个新应用版本。最终发布沿用永久 APK 私钥，确保现有用户无需卸载即可覆盖安装。

## 参考依据

- Android `PackageManager.canRequestPackageInstalls`：应用必须声明请求安装包权限，且 Android 8.0 及以上由用户单独授权当前来源。
  <https://developer.android.com/reference/kotlin/android/content/pm/PackageManager.html>
- Android `FileProvider`：安装文件通过临时授权的 `content://` URI 提供给系统安装器，不能暴露 `file://` 路径。
  <https://developer.android.com/reference/androidx/core/content/FileProvider>
- GitHub Release REST API：正式 Release 资源包含下载 URL、文件大小和 SHA-256 摘要。
  <https://docs.github.com/en/rest/releases/releases>
- Cloudflare R2 定价与公开存储桶：Standard 免费层包含 10GB-month 存储和免费公网出口；生产下载使用自定义域名而不是开发用 `r2.dev`。
  <https://developers.cloudflare.com/r2/pricing/>
  <https://developers.cloudflare.com/r2/buckets/public-buckets/>
- `lpinyin` 离线拼音能力：支持无声调输出、常见多音词和自定义词典。
  <https://pub.dev/documentation/lpinyin/latest/>
