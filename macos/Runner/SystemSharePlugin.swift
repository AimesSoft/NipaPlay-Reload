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

