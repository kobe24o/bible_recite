# TestFlight 自动续发

`.github/workflows/testflight-renewal.yml` 会在每两个自然月的第一天（02:17 UTC）构建并上传新的 iOS TestFlight 构建，也可以在 GitHub 的 **Actions → Renew TestFlight beta → Run workflow** 手动运行。每次上传使用 UTC 时间生成递增构建号，避免 TestFlight 90 天到期。

## 首次配置

在 App Store Connect 的 **用户和访问 → Integrations → App Store Connect API** 创建一个角色为 **App Manager** 的 API 密钥。私钥 `.p8` 只能下载一次，请保存在密码管理器或离线加密位置。

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 中设置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `APPSTORE_ISSUER_ID` | App Store Connect API 的 Issuer ID |
| Variable | `APPSTORE_API_KEY_ID` | 新 API 密钥的 Key ID |
| Secret | `APPSTORE_API_PRIVATE_KEY` | `.p8` 私钥的完整文本 |
| Secret | `APPSTORE_CERTIFICATES_FILE_BASE64` | Apple Distribution `.p12` 证书经 Base64 编码后的文本 |
| Secret | `APPSTORE_CERTIFICATES_PASSWORD` | 导出该 `.p12` 时设置的密码 |

证书和私钥不应提交到 Git。若没有 `.p12`，请在本机“钥匙串访问”中导出对应的 **Apple Distribution: Mingming Chen** 证书及私钥，再用：

```bash
base64 -i ios_distribution.p12 | pbcopy
```

将剪贴板内容保存为 `APPSTORE_CERTIFICATES_FILE_BASE64`。API 私钥直接以原文本保存，不进行 Base64 编码。

## 测试组

工作流会在 Apple 完成构建处理后自动将新构建加入外部 `outer` 测试组，并自动提交 Beta App Review。Apple 批准后，外部测试者即可获得该构建；Apple 的审核结果和处理时长无法自动化。

如需为已经上传的构建补交审核，可在 GitHub 的 **Actions → Submit existing TestFlight build → Run workflow** 输入构建号。该工作流不会重新打包或上传 IPA，只会确认构建已加入 `outer` 并向 Apple 提交 Beta App Review。

自动提交依赖已填写完整的 Test Information（包括 Beta 描述、反馈邮箱和联系信息）。如果 Apple 拒绝审核、要求补充资料，或同一版本已有构建处于审核中，工作流会失败并显示 Apple 的具体原因，不会继续伪造“已测试”状态。GitHub 对长期无活动的公开仓库可能会停用计划工作流，因此建议偶尔检查 Actions 页面，或在需要时手动运行一次。
