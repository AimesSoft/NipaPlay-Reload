import Cocoa
import FlutterMacOS

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

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // 注册自定义安全书签插件
    SecurityBookmarkPlugin.register(with: flutterViewController.registrar(forPlugin: "SecurityBookmarkPlugin"))

    super.awakeFromNib()
  }
}
