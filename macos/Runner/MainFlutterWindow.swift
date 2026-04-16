import Cocoa
import FlutterMacOS
import QuartzCore
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
            guard let view = resolveView(from: call.arguments, result: result) else {
                return
            }
            result(view.currentHandles())
        case "getViewDiagnostics":
            guard let view = resolveView(from: call.arguments, result: result) else {
                return
            }
            result(view.currentDiagnostics())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func resolveView(from arguments: Any?, result: @escaping FlutterResult) -> MacOSNativeVideoPlatformView? {
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments are required", details: nil))
            return nil
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
            return nil
        }

        guard let view = views[resolvedViewId]?.view else {
            result(FlutterError(code: "VIEW_NOT_FOUND", message: "No macOS native video view for id \(resolvedViewId)", details: nil))
            return nil
        }

        return view
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

    func currentDiagnostics() -> [String: Any] {
        let hostWindow = window
        let targetScreen = hostWindow?.screen
        let videoLayer = findBestVideoLayer()
        let windowBackingScaleFactor = hostWindow?.backingScaleFactor ?? 0.0
        let windowIsVisible = hostWindow?.isVisible ?? false
        let windowFrame = hostWindow.map { dictionary(for: $0.frame) } ?? [:]

        return [
            "viewId": viewId,
            "hostView": [
                "className": NSStringFromClass(type(of: self)),
                "frame": dictionary(for: frame),
                "bounds": dictionary(for: bounds),
                "isHidden": isHidden,
                "subviewCount": subviews.count,
                "layerClass": layer.map { NSStringFromClass(type(of: $0)) } ?? "nil",
                "layerTree": describeLayerTree(startingAt: layer),
                "subviewTree": describeViewTree(startingAt: self),
            ],
            "window": [
                "title": hostWindow?.title ?? "",
                "windowNumber": hostWindow?.windowNumber ?? 0,
                "backingScaleFactor": windowBackingScaleFactor,
                "isVisible": windowIsVisible,
                "frame": windowFrame,
            ],
            "screen": dictionary(for: targetScreen),
            "videoLayer": dictionary(for: videoLayer),
        ]
    }

    private func findBestVideoLayer() -> CAMetalLayer? {
        if let layer = findMetalLayer(in: self) {
            return layer
        }
        return nil
    }

    private func findMetalLayer(in view: NSView) -> CAMetalLayer? {
        if let layer = findMetalLayer(in: view.layer) {
            return layer
        }
        for subview in view.subviews {
            if let layer = findMetalLayer(in: subview) {
                return layer
            }
        }
        return nil
    }

    private func findMetalLayer(in layer: CALayer?) -> CAMetalLayer? {
        guard let layer else {
            return nil
        }
        if let metalLayer = layer as? CAMetalLayer {
            return metalLayer
        }
        for sublayer in layer.sublayers ?? [] {
            if let metalLayer = findMetalLayer(in: sublayer) {
                return metalLayer
            }
        }
        return nil
    }

    private func describeViewTree(startingAt rootView: NSView, depth: Int = 0, maxDepth: Int = 3) -> [String] {
        guard depth <= maxDepth else {
            return []
        }

        var result: [String] = [
            "\(String(repeating: "  ", count: depth))\(NSStringFromClass(type(of: rootView)))",
        ]
        guard depth < maxDepth else {
            return result
        }
        for subview in rootView.subviews.prefix(8) {
            result.append(contentsOf: describeViewTree(startingAt: subview, depth: depth + 1, maxDepth: maxDepth))
        }
        return result
    }

    private func describeLayerTree(startingAt rootLayer: CALayer?, depth: Int = 0, maxDepth: Int = 3) -> [String] {
        guard let rootLayer, depth <= maxDepth else {
            return []
        }

        var result: [String] = [
            "\(String(repeating: "  ", count: depth))\(NSStringFromClass(type(of: rootLayer)))",
        ]
        guard depth < maxDepth else {
            return result
        }
        for sublayer in (rootLayer.sublayers ?? []).prefix(8) {
            result.append(contentsOf: describeLayerTree(startingAt: sublayer, depth: depth + 1, maxDepth: maxDepth))
        }
        return result
    }

    private func dictionary(for screen: NSScreen?) -> [String: Any] {
        guard let screen else {
            return [
                "present": false,
            ]
        }

        var result: [String: Any] = [
            "present": true,
            "localizedName": screen.localizedName,
            "frame": dictionary(for: screen.frame),
            "visibleFrame": dictionary(for: screen.visibleFrame),
            "backingScaleFactor": screen.backingScaleFactor,
            "colorSpace": describe(colorSpace: screen.colorSpace),
        ]

        if #available(macOS 10.15, *) {
            result["maximumExtendedDynamicRangeColorComponentValue"] =
                screen.maximumExtendedDynamicRangeColorComponentValue
            result["maximumPotentialExtendedDynamicRangeColorComponentValue"] =
                screen.maximumPotentialExtendedDynamicRangeColorComponentValue
            result["maximumReferenceExtendedDynamicRangeColorComponentValue"] =
                screen.maximumReferenceExtendedDynamicRangeColorComponentValue
        }

        return result
    }

    private func dictionary(for metalLayer: CAMetalLayer?) -> [String: Any] {
        guard let metalLayer else {
            return [
                "present": false,
            ]
        }

        var result: [String: Any] = [
            "present": true,
            "className": NSStringFromClass(type(of: metalLayer)),
            "frame": dictionary(for: metalLayer.frame),
            "bounds": dictionary(for: metalLayer.bounds),
            "drawableSize": dictionary(for: metalLayer.drawableSize),
            "contentsScale": metalLayer.contentsScale,
            "isOpaque": metalLayer.isOpaque,
            "pixelFormat": String(describing: metalLayer.pixelFormat),
            "framebufferOnly": metalLayer.framebufferOnly,
            "colorspace": describe(colorSpace: metalLayer.colorspace),
            "wantsExtendedDynamicRangeContent":
                boolValue(metalLayer.value(forKey: "wantsExtendedDynamicRangeContent")) ?? false,
        ]

        if let edrMetadata = metalLayer.value(forKey: "edrMetadata") {
            result["edrMetadata"] = String(describing: edrMetadata)
        }

        return result
    }

    private func dictionary(for rect: CGRect) -> [String: Any] {
        [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.size.width,
            "height": rect.size.height,
        ]
    }

    private func dictionary(for size: CGSize) -> [String: Any] {
        [
            "width": size.width,
            "height": size.height,
        ]
    }

    private func describe(colorSpace: NSColorSpace?) -> String {
        guard let colorSpace else {
            return "nil"
        }
        return colorSpace.localizedName ?? String(describing: colorSpace)
    }

    private func describe(colorSpace: CGColorSpace?) -> String {
        guard let colorSpace else {
            return "nil"
        }
        if let name = colorSpace.name as String? {
            return name
        }
        return String(describing: colorSpace)
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
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
