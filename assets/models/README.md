# 离线语音模型

此目录在本地构建时应包含：

- `sherpa/encoder.onnx`
- `sherpa/decoder.onnx`
- `sherpa/joiner.onnx`
- `sherpa/tokens.txt`

ONNX 文件没有进入普通 Git 历史，其中 `encoder.onnx` 约 181 MB，超过 GitHub 的 100 MB 单文件限制。模型包发布在代码仓库的 GitHub Release `offline-models-v1` 中。

已安装 GitHub CLI 并登录后，可在仓库根目录执行：

```powershell
gh release download offline-models-v1 --pattern "sherpa-models.zip" --dir .model-download
Expand-Archive .model-download\sherpa-models.zip -DestinationPath assets\models -Force
```

模型文件只用于本地离线识别，不会上传用户录音或背诵内容。
