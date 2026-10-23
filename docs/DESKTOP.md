# Windows / macOS 桌面版

## 安装和数据

- Windows：Windows 10 2004 (19041)+ 或 Windows 11，x64。下载 Release 的 `BibleRecite-Windows-…-x64-setup.exe` 并安装到当前用户目录，不需要管理员权限。安装程序包含 Flutter、语音模型、原生库及 Visual C++ 运行库，支持卸载。关闭程序后升级安装即可。
- macOS：macOS 15.5+，支持 Apple Silicon 与 Intel。打开 `BibleRecite-macOS-…-universal.dmg`，将“背诵助手”拖到 Applications。当前 sherpa_onnx 1.13.4 内的 ONNX Runtime 原生库最低系统版本为 15.5，所以应用使用相同最低版本。
- 桌面安装包尚未使用正式发布证书签名/Apple 公证；Windows SmartScreen 或 macOS Gatekeeper 可能提示未知发布者。macOS 若系统阻止打开，可在“系统设置 → 隐私与安全性”检查该程序的允许打开选项。不要关闭整个系统的安全保护。
- 首次语音背诵需允许麦克风权限。桌面录音使用系统默认输入设备，可在系统声音设置中切换内置、USB 或蓝牙麦克风。
- 桌面支持系统学习提醒；拒绝权限时可到系统通知设置开启。Windows 未使用 MSIX 包身份，已显示的通知不能通过插件清除，但未来待触发提醒仍可重新排期/取消。
- 通过应用“我的 → 数据备份与恢复”导出 JSON，再在另一台设备导入。平台适配不提供设备之间自动同步。卸载不会主动删除用户数据。
- 桌面升级从 GitHub Releases 下载新安装包；Android APK 的签名更新源不用于桌面自动安装。

## GitHub 构建和发布

`.github/workflows/android-apk.yml`（App releases）在 `master` 推送和手动触发时运行。

Windows 和 macOS 作业各执行：

1. 获取 `offline-models-v1/sherpa-models.zip` 并校验四个模型文件存在。
2. 使用 Flutter 3.47.3 安装锁定依赖、静态分析、运行 `TZ=UTC flutter test`。现有非错误级别的 analyzer 提示会显示但不阻断发布。
3. 运行 `flutter test integration_test/desktop_smoke_test.dart -d windows` / `-d macos`，在原生应用中验证持久化 SQLite、应用信息、录音插件、ONNX 模型加载、通知插件和桌面导航。不会请求录音或通知权限，也不会改写已有用户数据库。
4. 构建 Release 包。Windows 用 Inno Setup 创建安装程序，并进行静默安装、启动、卸载验证；macOS 验证双架构、代码签名完整性、模型资源和 DMG 完整性。
5. 上传安装包和 SHA-256 校验文件，供发布作业附加到同一个 GitHub Release。任何平台失败都不会发布正式 Release。

手动触发时选中 `desktop_only`，会跳过 Android/iOS 构建，只把通过验证的桌面包发布为 **Pre-release**；不会更改 latest 正式版或 Android 更新源。CLI 示例：

```bash
gh workflow run android-apk.yml --ref codex/desktop-support -f desktop_only=true
```

正式签名尚需单独配置 Windows 代码签名证书、Apple Developer ID 与公证凭证。当前流程只生成可测试的安装包，不代表商店签名发布。

## 本机构建

先安装 Flutter 3.47.3，并按 `assets/models/README.md` 放置语音模型，然后执行 `flutter pub get`。

Windows 需要 Visual Studio 的 Desktop development with C++ 工作负载、Windows SDK 与 Inno Setup 6：

```powershell
flutter test
flutter test integration_test/desktop_smoke_test.dart -d windows
flutter build windows --release
# 安装程序参数和调用示例见 GitHub workflow 的 Package and verify Windows installer 步骤。
```

macOS 需要 Xcode 和 CocoaPods（语音库仍依赖 CocoaPods）：

```bash
TZ=UTC flutter test
flutter test integration_test/desktop_smoke_test.dart -d macos
flutter build macos --release
bash tool/desktop/package-macos.sh
```

GitHub 的原生测试不录制真人语音。发布前仍应在实机检查录音授权、外接麦克风、识别准确率、真实通知到达，以及系统文件选择器的导入/导出。
