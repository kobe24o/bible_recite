# macOS TestFlight 自动发布

GitHub Actions 的 **macOS TestFlight and App Store** 会在 master 的应用代码、版本或 macOS 配置更新时，构建签名安装包并上传 App Store Connect。每两个自然月第一天 02:37 UTC 自动续发，也可手动运行。

上传完成后等待 Apple 处理，加入外部 outer 测试组并提交 Beta App Review。外部测试者需等待 Apple 审核批准。

沿用 APPSTORE_ISSUER_ID、APPSTORE_API_KEY_ID、APPSTORE_API_PRIVATE_KEY 和 Supabase 配置；macOS 签名使用 MACOS_CERTIFICATE_PRIVATE_KEY，自动获取 Mac App Store 描述文件与安装器证书。私钥保存在 Actions secrets。

手动运行默认只发布 TestFlight；勾选 submit_review 才提交 macOS 正式 App Review，并设置通过后自动发布。正式审核与 Beta 审核分别进行。

scripts/submit-store-build.mjs 同时支持 IOS 和 MAC_OS，会检查构建所属平台、版本、处理状态和过期状态，避免误挂不同平台或版本。已在审核的商店版本不会重复提交。
