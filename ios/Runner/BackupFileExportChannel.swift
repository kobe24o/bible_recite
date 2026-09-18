import Flutter
import UIKit

/// Presents the iOS Files export picker for user backups. `file_selector`'s
/// desktop save-location API is not available on iOS, so mobile backup export
/// is handled natively on both platforms.
final class BackupFileExportChannel: NSObject, UIDocumentPickerDelegate {
  private static let name = "app.biblerecite/backup_file"
  private var pendingResult: FlutterResult?
  private var pendingFile: URL?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterError(code: "backup_export_error", message: "Backup exporter is unavailable", details: nil)) }
      guard call.method == "exportJson" else { return result(FlutterMethodNotImplemented) }
      self.export(call, result: result)
    }
  }

  private func export(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      return result(FlutterError(code: "backup_export_in_progress", message: "Another backup export is already in progress", details: nil))
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let typedData = arguments["bytes"] as? FlutterStandardTypedData
    else {
      return result(FlutterError(code: "backup_export_invalid_data", message: "Backup data is required", details: nil))
    }

    let requestedName = (arguments["displayName"] as? String) ?? "BibleRecite-backup.json"
    let fileName = requestedName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
      try typedData.data.write(to: file, options: .atomic)
      guard let presenter = topViewController() else {
        throw NSError(domain: "BibleRecite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to present the Files save dialog"])
      }
      pendingResult = result
      pendingFile = file
      let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      picker.delegate = self
      presenter.present(picker, animated: true)
    } catch {
      try? FileManager.default.removeItem(at: file)
      result(FlutterError(code: "backup_export_error", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(with: urls.first?.path)
  }

  private func finish(with path: String?) {
    let result = pendingResult
    let file = pendingFile
    pendingResult = nil
    pendingFile = nil
    if let file { try? FileManager.default.removeItem(at: file) }
    result?(path)
  }

  private func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    guard let root = windows.first(where: { $0.isKeyWindow })?.rootViewController ?? windows.first?.rootViewController else {
      return nil
    }
    return visibleViewController(from: root)
  }

  private func visibleViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController {
      return visibleViewController(from: presented)
    }
    if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
      return visibleViewController(from: visible)
    }
    if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
      return visibleViewController(from: selected)
    }
    return controller
  }
}
