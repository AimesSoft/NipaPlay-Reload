import Cocoa
import FlutterMacOS

final class SystemSharePlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nipaplay/system_share",
      binaryMessenger: registrar.messenger
    )
    let instance = SystemSharePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "share" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Arguments are required",
          details: nil
        )
      )
      return
    }

    let text = args["text"] as? String
    let urlString = args["url"] as? String
    let filePath = args["filePath"] as? String

    var items: [Any] = []
    if let filePath = filePath, !filePath.isEmpty {
      items.append(URL(fileURLWithPath: filePath))
    }
    if let urlString = urlString, let url = URL(string: urlString) {
      items.append(url)
    }
    if let text = text, !text.isEmpty {
      items.append(text)
    }

    if items.isEmpty {
      result(
        FlutterError(
          code: "NO_ITEMS",
          message: "Nothing to share",
          details: nil
        )
      )
      return
    }

    DispatchQueue.main.async {
      guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
            let contentView = window.contentView
      else {
        result(
          FlutterError(
            code: "NO_WINDOW",
            message: "No active window to present share sheet",
            details: nil
          )
        )
        return
      }

      let picker = NSSharingServicePicker(items: items)
      let rect = NSRect(
        x: contentView.bounds.midX,
        y: contentView.bounds.midY,
        width: 1,
        height: 1
      )
      picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
      result(true)
    }
  }
}

/// 把本地图片文件本体写入系统剪贴板。
///
/// 同时声明文件 URL、原始 GIF 数据与位图数据三种类型，使聊天软件输入框
/// 既能按“文件”粘贴（保留动图），也能按“图片”粘贴（首帧静态图）。
final class ClipboardImagePlugin: NSObject, FlutterPlugin {
  /// 保留动图的 GIF 粘贴板类型（与系统其它应用互通）。
  private static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nipaplay/clipboard_image",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(ClipboardImagePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "readImageFiles" {
      readImageFiles(call, result: result)
      return
    }
    guard call.method == "copyImageFile" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A non-empty file path is required",
          details: nil
        )
      )
      return
    }

    guard FileManager.default.fileExists(atPath: path) else {
      result(
        FlutterError(
          code: "FILE_NOT_FOUND",
          message: "The file to copy does not exist",
          details: path
        )
      )
      return
    }

    let fileURL = URL(fileURLWithPath: path)
    let item = NSPasteboardItem()
    // 文件本体：保留“复制文件”语义，聊天软件可直接粘贴为文件。
    item.setString(fileURL.absoluteString, forType: .fileURL)
    if let data = try? Data(contentsOf: fileURL) {
      item.setData(data, forType: Self.gifPasteboardType)
      // 静态位图回退：只接受图片数据的输入框也能粘贴（GIF 取首帧）。
      if let image = NSImage(data: data),
         let tiff = image.tiffRepresentation {
        item.setData(tiff, forType: .tiff)
        if let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
          item.setData(png, forType: .png)
        }
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      result(
        FlutterError(
          code: "CLIPBOARD_WRITE_FAILED",
          message: "Failed to write the file to the pasteboard",
          details: nil
        )
      )
      return
    }
    result(true)
  }

  private func readImageFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let directory = args["directory"] as? String, !directory.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "An attachment directory is required", details: nil))
      return
    }
    let board = NSPasteboard.general
    let destination = URL(fileURLWithPath: directory, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]
      let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
      var paths: [String] = []
      for url in urls where extensions.contains(url.pathExtension.lowercased()) {
        let target = destination.appendingPathComponent("clipboard-\(UUID().uuidString).\(url.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: url, to: target)
        paths.append(target.path)
      }
      if !paths.isEmpty { result(paths); return }
      // Screenshots and copied browser images usually carry PNG or TIFF data.
      let data: Data?
      if let png = board.data(forType: .png) {
        data = png
      } else if let image = NSImage(pasteboard: board),
                let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff) {
        data = bitmap.representation(using: .png, properties: [:])
      } else {
        data = nil
      }
      if let data = data {
        let target = destination.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        try data.write(to: target, options: .atomic)
        paths.append(target.path)
      }
      result(paths)
    } catch {
      result(FlutterError(code: "CLIPBOARD_READ_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}

