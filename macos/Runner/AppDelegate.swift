import Cocoa
import Darwin
import FlutterMacOS
import UniformTypeIdentifiers

@main
@objcMembers
class AppDelegate: FlutterAppDelegate {
  // Keep IBOutlet connected from MainMenu.xib to avoid runtime crash,
  // but no longer used — Flutter's PlatformMenuBar handles the menu bar.
  @IBOutlet weak var playerMenu: NSMenu?

  private var didConfigureBundledMoltenVK = false

  @objc override func applicationWillFinishLaunching(_ notification: Notification) {
    configureBundledMoltenVKIfAvailable()
  }
  
  @objc override func applicationDidFinishLaunching(_ notification: Notification) {
    configureBundledMoltenVKIfAvailable()
    print("[AppDelegate] 应用启动")
  }

  private func configureBundledMoltenVKIfAvailable() {
    guard !didConfigureBundledMoltenVK else {
      return
    }
    didConfigureBundledMoltenVK = true

    let environment = ProcessInfo.processInfo.environment
    if environment["VK_ICD_FILENAMES"] != nil || environment["VK_DRIVER_FILES"] != nil {
      print("[AppDelegate] Vulkan ICD 已由环境变量配置，跳过 bundled MoltenVK")
      return
    }

    guard let frameworksPath = Bundle.main.privateFrameworksPath else {
      return
    }

    let fileManager = FileManager.default
    let moltenVKFrameworkURL = URL(fileURLWithPath: frameworksPath)
      .appendingPathComponent("MoltenVK.framework", isDirectory: true)
    let libraryCandidates = [
      moltenVKFrameworkURL.appendingPathComponent("MoltenVK"),
      moltenVKFrameworkURL.appendingPathComponent("Versions/A/MoltenVK"),
    ]

    guard let moltenVKLibraryURL = libraryCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
      return
    }

    do {
      let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? fileManager.temporaryDirectory
      let icdDirectoryURL = baseURL
        .appendingPathComponent("vulkan", isDirectory: true)
        .appendingPathComponent("icd.d", isDirectory: true)
      try fileManager.createDirectory(at: icdDirectoryURL, withIntermediateDirectories: true)

      let icdURL = icdDirectoryURL.appendingPathComponent("MoltenVK_icd.json")
      let icd: [String: Any] = [
        "file_format_version": "1.0.0",
        "ICD": [
          "library_path": moltenVKLibraryURL.path,
          "api_version": "1.3.0",
          "is_portability_driver": true,
        ],
      ]
      let data = try JSONSerialization.data(withJSONObject: icd, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: icdURL, options: [.atomic])

      setenv("VK_ICD_FILENAMES", icdURL.path, 0)
      setenv("VK_DRIVER_FILES", icdURL.path, 0)
      print("[AppDelegate] 已配置 bundled MoltenVK ICD: \(icdURL.path)")
    } catch {
      print("[AppDelegate] 配置 bundled MoltenVK ICD 失败: \(error)")
    }
  }
  
  // MARK: - Window lifecycle

  @objc override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 需要支持"关闭窗口后仍驻留菜单栏(托盘)"的行为，因此不能在最后一个窗口关闭时退出进程。
    return false
  }

  @objc override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  // MARK: - File handling (drag-drop to Dock icon)

  @objc override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    print("[AppDelegate] 收到文件拖拽: \(filename)")
    handleOpenFile(filename)
    return true
  }
  
  @objc override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    print("[AppDelegate] 收到多个文件拖拽: \(filenames)")
    for filename in filenames {
      if isSupportedVideoFile(filename) {
        handleOpenFile(filename)
        break
      }
    }
  }
  
  private func handleOpenFile(_ filename: String) {
    print("[AppDelegate] 处理文件: \(filename)")
    
    guard isSupportedVideoFile(filename) else {
      print("[AppDelegate] 不支持的文件格式: \(filename)")
      showSimpleAlert(message: "不支持的文件格式")
      return
    }
    
    if !isFlutterReady() {
      print("[AppDelegate] Flutter未准备好，保存文件路径")
      pendingFilePath = filename
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if let savedPath = self.pendingFilePath {
          self.sendFileToFlutter(savedPath)
          self.pendingFilePath = nil
        }
      }
    } else {
      sendFileToFlutter(filename)
    }
  }
  
  private func isSupportedVideoFile(_ filename: String) -> Bool {
    let supportedExtensions = ["mp4", "mkv", "avi", "mov", "webm", "wmv", "m4v", "3gp", "flv", "ts", "m2ts"]
    let fileExtension = (filename as NSString).pathExtension.lowercased()
    return supportedExtensions.contains(fileExtension)
  }
  
  private func isFlutterReady() -> Bool {
    guard let _ = self.mainFlutterWindow?.nipaplayFlutterViewController else {
      return false
    }
    return true
  }
  
  private func sendFileToFlutter(_ filename: String) {
    print("[AppDelegate] 发送文件到Flutter: \(filename)")
    
    guard let controller = self.mainFlutterWindow?.nipaplayFlutterViewController else {
      print("[AppDelegate] 错误: 无法获取Flutter控制器")
      return
    }
    
    let channel = FlutterMethodChannel(name: "drag_drop_channel", binaryMessenger: controller.engine.binaryMessenger)
    
    channel.invokeMethod("onFilesDropped", arguments: ["files": [filename]]) { result in
      if let error = result as? FlutterError {
        print("[AppDelegate] 发送文件到Flutter失败: \(error.message ?? "未知错误")")
      } else {
        print("[AppDelegate] 文件已发送到Flutter")
      }
    }
  }
  
  private var pendingFilePath: String?

  // MARK: - Helpers

  private func showSimpleAlert(message: String) {
    DispatchQueue.main.async {
      if let window = NSApp.mainWindow {
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: window, completionHandler: nil)
      }
    }
  }
}
