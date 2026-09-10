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

当前 `inner` 与 `outer` 测试组已经自动获得构建 98。首次手动运行该工作流后，请在 App Store Connect 确认新构建仍已分配到这两个群组；如果 Apple 未自动分配，在 TestFlight 的构建页面将其添加到对应群组一次即可。

外部测试的新构建仍可能需要 Apple 的 Beta App Review；自动化不会绕过此审核。GitHub 对长期无活动的公开仓库可能会停用计划工作流，因此建议偶尔检查 Actions 页面，或在需要时手动运行一次。
