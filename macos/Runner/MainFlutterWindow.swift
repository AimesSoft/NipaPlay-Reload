import Cocoa
import FlutterMacOS
import desktop_multi_window

class SecurityBookmarkPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "security_bookmark", binaryMessenger: registrar.messenger)
        let instance = SecurityBookmarkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createBookmark":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Path is required", details: nil))
                return
            }
            createBookmark(path: path, result: result)
            
        case "resolveBookmark":
            guard let args = call.arguments as? [String: Any],
                  let bookmarkData = args["bookmarkData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Bookmark data is required", details: nil))
                return
            }
            resolveBookmark(bookmarkData: bookmarkData.data, result: result)
            
        case "stopAccessingSecurityScopedResource":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Path is required", details: nil))
                return
            }
            stopAccessingSecurityScopedResource(path: path, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func createBookmark(path: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: path)
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            result(FlutterStandardTypedData(bytes: bookmarkData))
        } catch {
            result(FlutterError(
                code: "BOOKMARK_CREATION_FAILED",
                message: "Failed to create security bookmark: \(error.localizedDescription)",
                details: error.localizedDescription
            ))
        }
    }
    
    private func resolveBookmark(bookmarkData: Data, result: @escaping FlutterResult) {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // 开始访问安全作用域资源
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            
            if didStartAccessing {
                result([
                    "path": url.path,
                    "isStale": isStale,
                    "didStartAccessing": true
                ])
            } else {
                result(FlutterError(
                    code: "ACCESS_DENIED",
                    message: "Failed to start accessing security scoped resource",
                    details: nil
                ))
            }
        } catch {
            result(FlutterError(
                code: "BOOKMARK_RESOLUTION_FAILED",
                message: "Failed to resolve security bookmark: \(error.localizedDescription)",
                details: error.localizedDescription
            ))
        }
    }
    
    private func stopAccessingSecurityScopedResource(path: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: path)
        url.stopAccessingSecurityScopedResource()
        result(true)
    }
}

private final class WeakMacOSNativeVideoPlatformViewBox {
    weak var view: MacOSNativeVideoPlatformView?

    init(view: MacOSNativeVideoPlatformView) {
        self.view = view
    }
}

final class MacOSNativeVideoPlugin: NSObject, FlutterPlugin {
    private static let channelName = "nipaplay/macos_native_video"
    private static let viewType = "nipaplay/macos_native_video_view"

    private var views: [Int64: WeakMacOSNativeVideoPlatformViewBox] = [:]

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = MacOSNativeVideoPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            MacOSNativeVideoViewFactory(plugin: instance),
            withId: viewType
        )
    }

    fileprivate func registerView(_ view: MacOSNativeVideoPlatformView, viewId: Int64) {
        views[viewId] = WeakMacOSNativeVideoPlatformViewBox(view: view)
    }

    fileprivate func unregisterView(viewId: Int64) {
        views.removeValue(forKey: viewId)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getViewHandles":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments are required", details: nil))
                return
            }
            let viewId: Int64?
            if let value = args["viewId"] as? Int64 {
                viewId = value
            } else if let value = args["viewId"] as? NSNumber {
                viewId = value.int64Value
            } else {
                viewId = nil
            }

            guard let resolvedViewId = viewId else {
                result(FlutterError(code: "INVALID_VIEW_ID", message: "viewId is required", details: nil))
                return
            }
            guard let view = views[resolvedViewId]?.view else {
                result(FlutterError(code: "VIEW_NOT_FOUND", message: "No macOS native video view for id \(resolvedViewId)", details: nil))
                return
            }
            result(view.currentHandles())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

final class MacOSNativeVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: MacOSNativeVideoPlugin?

    init(plugin: MacOSNativeVideoPlugin) {
        self.plugin = plugin
        super.init()
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let platformView = MacOSNativeVideoPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            plugin: plugin
        )
        plugin?.registerView(platformView, viewId: viewId)
        return platformView
    }
}

final class MacOSNativeVideoPlatformView: NSView {
    private let viewId: Int64
    private weak var plugin: MacOSNativeVideoPlugin?

    init(viewIdentifier viewId: Int64, arguments args: Any?, plugin: MacOSNativeVideoPlugin?) {
        self.viewId = viewId
        self.plugin = plugin
        super.init(frame: .zero)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layerContentsRedrawPolicy = .duringViewResize
        autoresizingMask = [.width, .height]

        if let params = args as? [String: Any],
           let debugLabel = params["debugLabel"] as? String,
           !debugLabel.isEmpty {
            let label = NSTextField(labelWithString: debugLabel)
            label.textColor = NSColor(white: 1.0, alpha: 0.35)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        plugin?.unregisterView(viewId: viewId)
    }

    func currentHandles() -> [String: Any] {
        let viewHandle = Int64(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()))
        let windowHandle = window.map {
            Int64(Int(bitPattern: Unmanaged.passUnretained($0).toOpaque()))
        } ?? 0
        return [
            "viewHandle": viewHandle,
            "windowHandle": windowHandle,
            "viewId": viewId,
        ]
    }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // 注册自定义安全书签插件
    SecurityBookmarkPlugin.register(with: flutterViewController.registrar(forPlugin: "SecurityBookmarkPlugin"))
    SystemSharePlugin.register(with: flutterViewController.registrar(forPlugin: "SystemSharePlugin"))
    MacOSNativeVideoPlugin.register(with: flutterViewController.registrar(forPlugin: "MacOSNativeVideoPlugin"))

    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      SecurityBookmarkPlugin.register(with: controller.registrar(forPlugin: "SecurityBookmarkPlugin"))
      SystemSharePlugin.register(with: controller.registrar(forPlugin: "SystemSharePlugin"))
      MacOSNativeVideoPlugin.register(with: controller.registrar(forPlugin: "MacOSNativeVideoPlugin"))
    }

    super.awakeFromNib()
  }
}
