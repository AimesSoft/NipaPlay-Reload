import Cocoa
import FlutterMacOS
import ObjectiveC.runtime
import QuartzCore
import media_kit_video

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
                options: [.withSecurityScope],
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

private let macOSWindowHostedVideoSurfaceId: Int64 = -1
private let macOSHdrExitTraceEnabled =
    ProcessInfo.processInfo.environment["NIPAPLAY_MACOS_HDR_EXIT_TRACE"] == "1"
private let macOSNativeVideoDebugLabelsEnabled =
    ProcessInfo.processInfo.environment["NIPAPLAY_MACOS_NATIVE_VIDEO_DEBUG_LABELS"] == "1"

private func macOSHdrExitTrace(_ message: String) {
    guard macOSHdrExitTraceEnabled else {
        return
    }
    NSLog("[HDRExit][Native] %@", message)
}

private protocol MacOSNativeVideoSurfaceHost: AnyObject {
    var platformViewId: Int64 { get }
    var hostView: NSView { get }

    func attachPlayer(handle: Int64)
    func detachPlayer()
    func updateOverlayFrame(_ frame: CGRect?, visible: Bool, debugLabel: String?)
}

private extension MacOSNativeVideoSurfaceHost {
    func currentHandles() -> [String: Any] {
        hostView.nipaplayNativeVideoHandles(viewId: platformViewId)
    }

    func currentDiagnostics() -> [String: Any] {
        hostView.nipaplayNativeVideoDiagnostics(viewId: platformViewId)
    }

    func updateOverlayFrame(_ frame: CGRect?, visible: Bool, debugLabel: String?) {
        _ = frame
        _ = visible
        _ = debugLabel
    }
}

private final class WeakMacOSNativeVideoSurfaceHostBox {
    weak var host: (NSView & MacOSNativeVideoSurfaceHost)?

    init(host: NSView & MacOSNativeVideoSurfaceHost) {
        self.host = host
    }
}

final class MacOSWindowNativeVideoOverlayView: NSView, MacOSNativeVideoSurfaceHost {
    let platformViewId: Int64 = macOSWindowHostedVideoSurfaceId
    var hostView: NSView { self }

    private var videoRenderer: MediaKitOpenGLVideoRenderer?
    private var attachedPlayerHandle: Int64?
    private var overlayFrameGeneration: Int64?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installBaseLayer()
        layerContentsRedrawPolicy = .duringViewResize
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        macOSHdrExitTrace("overlayView deinit attachedPlayerHandle=\(attachedPlayerHandle ?? 0)")
        detachPlayer()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        videoRenderer?.layer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        videoRenderer?.hostViewDidChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoRenderer?.hostViewDidChange()
    }

    func attachPlayer(handle: Int64) {
        macOSHdrExitTrace("overlayView attachPlayer handle=\(handle) existing=\(attachedPlayerHandle ?? 0)")
        if attachedPlayerHandle == handle, let existing = videoRenderer {
            existing.hostViewDidChange()
            return
        }

        detachPlayer()
        guard let renderer = MediaKitOpenGLVideoRenderer(
            playerHandle: handle,
            hostView: self
        ) else {
            NSLog("MacOSWindowNativeVideoOverlayView: failed to create libmpv OpenGL renderer")
            return
        }
        videoRenderer = renderer
        attachedPlayerHandle = handle
        renderer.hostViewDidChange()
    }

    func detachPlayer() {
        macOSHdrExitTrace("overlayView detachPlayer attachedPlayerHandle=\(attachedPlayerHandle ?? 0)")
        videoRenderer?.detach()
        videoRenderer = nil
        attachedPlayerHandle = nil
        installBaseLayer()
    }

    func updateOverlayFrame(_ frame: CGRect?, visible: Bool, debugLabel: String?) {
        updateOverlayFrame(frame, visible: visible, debugLabel: debugLabel, generation: nil)
    }

    func updateOverlayFrame(_ frame: CGRect?, visible: Bool, debugLabel: String?, generation: Int64?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateOverlayFrame(
                    frame,
                    visible: visible,
                    debugLabel: debugLabel,
                    generation: generation
                )
            }
            return
        }

        if visible {
            overlayFrameGeneration = generation
        } else if let generation,
                  let overlayFrameGeneration,
                  generation != overlayFrameGeneration {
            macOSHdrExitTrace(
                "overlayView ignore stale hide generation=\(generation) active=\(overlayFrameGeneration) label=\(debugLabel ?? "")"
            )
            return
        }

        toolTip = macOSNativeVideoDebugLabelsEnabled ? debugLabel : nil
        let shouldShow = visible &&
            (frame?.width ?? 0) > 0 &&
            (frame?.height ?? 0) > 0

        guard shouldShow, let frame else {
            macOSHdrExitTrace("overlayView updateOverlayFrame hide label=\(debugLabel ?? "")")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            isHidden = true
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.frame != frame {
            self.frame = frame.integral
        }
        isHidden = false
        videoRenderer?.layer.frame = bounds
        CATransaction.commit()
        videoRenderer?.hostViewDidChange()
    }

    private func installBaseLayer() {
        wantsLayer = true
        if layer == nil || layer is CAOpenGLLayer {
            layer = CALayer()
        }
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
        ]
    }
}

extension NSWindow {
    var nipaplayFlutterViewController: FlutterViewController? {
        contentViewController as? FlutterViewController
    }

    var nipaplayNativeVideoOverlayHost: MacOSWindowNativeVideoOverlayView? {
        get {
            objc_getAssociatedObject(
                self,
                &AssociatedObjectKeys.nativeVideoOverlayHost
            ) as? MacOSWindowNativeVideoOverlayView
        }
        set {
            objc_setAssociatedObject(
                self,
                &AssociatedObjectKeys.nativeVideoOverlayHost,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var nipaplayIsDetachedPlayerWindow: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                &AssociatedObjectKeys.detachedPlayerWindow
            ) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &AssociatedObjectKeys.detachedPlayerWindow,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var nipaplayPictureInPictureRestoreFrame: NSRect? {
        get {
            (objc_getAssociatedObject(
                self,
                &AssociatedObjectKeys.pictureInPictureRestoreFrame
            ) as? NSValue)?.rectValue
        }
        set {
            objc_setAssociatedObject(
                self,
                &AssociatedObjectKeys.pictureInPictureRestoreFrame,
                newValue.map { NSValue(rect: $0) },
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

private enum AssociatedObjectKeys {
    static var nativeVideoOverlayHost: UInt8 = 0
    static var detachedPlayerWindow: UInt8 = 0
    static var pictureInPictureRestoreFrame: UInt8 = 0
}

private extension NSView {
    func nipaplayNativeVideoHandles(viewId: Int64) -> [String: Any] {
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

    func nipaplayNativeVideoDiagnostics(viewId: Int64) -> [String: Any] {
        let hostWindow = window
        let targetScreen = hostWindow?.screen
        let videoLayer = nipaplayFindBestVideoLayer()
        let windowBackingScaleFactor = hostWindow?.backingScaleFactor ?? 0.0
        let windowIsVisible = hostWindow?.isVisible ?? false
        let windowFrame = hostWindow.map { nipaplayDictionary(for: $0.frame) } ?? [:]

        return [
            "viewId": viewId,
            "hostView": [
                "className": NSStringFromClass(type(of: self)),
                "frame": nipaplayDictionary(for: frame),
                "bounds": nipaplayDictionary(for: bounds),
                "isHidden": isHidden,
                "subviewCount": subviews.count,
                "layerClass": layer.map { NSStringFromClass(type(of: $0)) } ?? "nil",
            ],
            "window": [
                "title": hostWindow?.title ?? "",
                "windowNumber": hostWindow?.windowNumber ?? 0,
                "backingScaleFactor": windowBackingScaleFactor,
                "isVisible": windowIsVisible,
                "frame": windowFrame,
            ],
            "screen": nipaplayDictionary(for: targetScreen),
            "videoLayer": nipaplayDictionary(for: videoLayer),
        ]
    }

    private func nipaplayFindBestVideoLayer() -> CALayer? {
        if let layer = nipaplayFindVideoLayer(in: self) {
            return layer
        }
        return nil
    }

    private func nipaplayFindVideoLayer(in view: NSView) -> CALayer? {
        if let layer = nipaplayFindVideoLayer(in: view.layer) {
            return layer
        }
        for subview in view.subviews {
            if let layer = nipaplayFindVideoLayer(in: subview) {
                return layer
            }
        }
        return nil
    }

    private func nipaplayFindVideoLayer(in layer: CALayer?) -> CALayer? {
        guard let layer else {
            return nil
        }
        if let metalLayer = layer as? CAMetalLayer {
            return metalLayer
        }
        if layer is CAOpenGLLayer {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let videoLayer = nipaplayFindVideoLayer(in: sublayer) {
                return videoLayer
            }
        }
        return nil
    }
}

private func nipaplayDictionary(for screen: NSScreen?) -> [String: Any] {
    guard let screen else {
        return [
            "present": false,
        ]
    }

    var result: [String: Any] = [
        "present": true,
        "localizedName": screen.localizedName,
        "frame": nipaplayDictionary(for: screen.frame),
        "visibleFrame": nipaplayDictionary(for: screen.visibleFrame),
        "backingScaleFactor": screen.backingScaleFactor,
        "colorSpace": nipaplayDescribe(colorSpace: screen.colorSpace),
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

private func nipaplayDictionary(for videoLayer: CALayer?) -> [String: Any] {
    guard let videoLayer else {
        return [
            "present": false,
        ]
    }

    var result: [String: Any] = [
        "present": true,
        "className": NSStringFromClass(type(of: videoLayer)),
        "frame": nipaplayDictionary(for: videoLayer.frame),
        "bounds": nipaplayDictionary(for: videoLayer.bounds),
        "contentsScale": videoLayer.contentsScale,
        "contentsFormat": videoLayer.contentsFormat.rawValue,
        "isOpaque": videoLayer.isOpaque,
        "colorspace": nipaplayDescribe(colorSpace: nipaplayColorSpace(for: videoLayer)),
        "wantsExtendedDynamicRangeContent":
            nipaplayBoolValue(nipaplayOptionalValue(forKey: "wantsExtendedDynamicRangeContent", on: videoLayer)) ?? false,
    ]

    if let metalLayer = videoLayer as? CAMetalLayer {
        result["drawableSize"] = nipaplayDictionary(for: metalLayer.drawableSize)
        result["pixelFormat"] = String(describing: metalLayer.pixelFormat)
        result["framebufferOnly"] = metalLayer.framebufferOnly
    }

    if let edrMetadata = nipaplayOptionalValue(forKey: "edrMetadata", on: videoLayer) {
        result["edrMetadata"] = String(describing: edrMetadata)
    }

    return result
}

private func nipaplayColorSpace(for layer: CALayer) -> CGColorSpace? {
    if let metalLayer = layer as? CAMetalLayer {
        return metalLayer.colorspace
    }
    if let openGLLayer = layer as? CAOpenGLLayer {
        return openGLLayer.colorspace
    }
    return nil
}

private func nipaplayDictionary(for rect: CGRect) -> [String: Any] {
    [
        "x": rect.origin.x,
        "y": rect.origin.y,
        "width": rect.size.width,
        "height": rect.size.height,
    ]
}

private func nipaplayDictionary(for size: CGSize) -> [String: Any] {
    [
        "width": size.width,
        "height": size.height,
    ]
}

private func nipaplayDescribe(colorSpace: NSColorSpace?) -> String {
    guard let colorSpace else {
        return "nil"
    }
    return colorSpace.localizedName ?? String(describing: colorSpace)
}

private func nipaplayDescribe(colorSpace: CGColorSpace?) -> String {
    guard let colorSpace else {
        return "nil"
    }
    if let name = colorSpace.name as String? {
        return name
    }
    return String(describing: colorSpace)
}

private func nipaplayBoolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
        return value
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}

private func nipaplayOptionalValue(forKey key: String, on object: NSObject) -> Any? {
    let selector = NSSelectorFromString(key)
    guard object.responds(to: selector) else {
        return nil
    }
    return object.value(forKey: key)
}

final class MacOSNativeVideoPlugin: NSObject, FlutterPlugin {
    private static let channelName = "nipaplay/macos_native_video"
    private static let viewType = "nipaplay/macos_native_video_view"

    private var views: [Int64: WeakMacOSNativeVideoSurfaceHostBox] = [:]
    private weak var flutterHostView: NSView?
    private weak var flutterHostViewController: NSViewController?
    private weak var windowHostedOverlay: MacOSWindowNativeVideoOverlayView?
    private var requestedFlutterViewIdentifier: Int64?

    init(flutterHostView: NSView?, flutterHostViewController: NSViewController?) {
        self.flutterHostView = flutterHostView
        self.flutterHostViewController = flutterHostViewController
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = MacOSNativeVideoPlugin(
            flutterHostView: registrar.view,
            flutterHostViewController: registrar.viewController
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            MacOSNativeVideoViewFactory(plugin: instance),
            withId: viewType
        )
    }

    fileprivate func registerView(_ view: NSView & MacOSNativeVideoSurfaceHost, viewId: Int64) {
        views[viewId] = WeakMacOSNativeVideoSurfaceHostBox(host: view)
    }

    fileprivate func unregisterView(viewId: Int64) {
        views.removeValue(forKey: viewId)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getViewHandles":
            guard let host = resolveHost(from: call.arguments, result: result) else {
                return
            }
            result(host.currentHandles())
        case "attachPlayer":
            guard let host = resolveHost(from: call.arguments, result: result) else {
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let playerHandle = int64Value(args["playerHandle"]),
                  playerHandle > 0 else {
                result(FlutterError(code: "INVALID_PLAYER_HANDLE", message: "playerHandle is required", details: nil))
                return
            }
            macOSHdrExitTrace("plugin attachPlayer viewId=\(host.platformViewId) handle=\(playerHandle)")
            host.attachPlayer(handle: playerHandle)
            result(nil)
        case "detachPlayer":
            guard let host = resolveHost(from: call.arguments, result: result) else {
                return
            }
            macOSHdrExitTrace("plugin detachPlayer viewId=\(host.platformViewId)")
            host.detachPlayer()
            result(nil)
        case "getViewDiagnostics":
            guard let host = resolveHost(from: call.arguments, result: result) else {
                return
            }
            result(host.currentDiagnostics())
        case "setOverlayFrame":
            guard let host = resolveHost(from: call.arguments, result: result) else {
                return
            }
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments are required", details: nil))
                return
            }
            let visible = boolValue(args["visible"]) ?? true
            if let flutterViewId = int64Value(args["flutterViewId"]) {
                requestedFlutterViewIdentifier = flutterViewId
            }
            let frame = convertedRectValue(from: args, host: host)
            if !visible {
                macOSHdrExitTrace("plugin setOverlayFrame hide viewId=\(host.platformViewId)")
            }
            let generation = int64Value(args["generation"])
            if let overlayHost = host as? MacOSWindowNativeVideoOverlayView {
                overlayHost.updateOverlayFrame(
                    frame,
                    visible: visible,
                    debugLabel: args["debugLabel"] as? String,
                    generation: generation
                )
            } else {
                host.updateOverlayFrame(
                    frame,
                    visible: visible,
                    debugLabel: args["debugLabel"] as? String
                )
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func resolveHost(from arguments: Any?, result: @escaping FlutterResult) -> (NSView & MacOSNativeVideoSurfaceHost)? {
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments are required", details: nil))
            return nil
        }

        guard let viewId = int64Value(args["viewId"]) else {
            result(FlutterError(code: "INVALID_VIEW_ID", message: "viewId is required", details: nil))
            return nil
        }

        if viewId == macOSWindowHostedVideoSurfaceId {
            if let overlayHost = resolveWindowHostedOverlay() {
                return overlayHost
            }
            result(FlutterError(
                code: "VIEW_NOT_FOUND",
                message: "No window-hosted macOS native video overlay is available",
                details: nil
            ))
            return nil
        }

        guard let host = views[viewId]?.host else {
            result(FlutterError(code: "VIEW_NOT_FOUND", message: "No macOS native video view for id \(viewId)", details: nil))
            return nil
        }

        return host
    }

    private func resolveWindowHostedOverlay() -> MacOSWindowNativeVideoOverlayView? {
        if let installedHost = ensureWindowHostedOverlayInstalled() {
            return installedHost
        }
        if let hostWindow = flutterHostView?.window,
           let overlayHost = hostWindow.nipaplayNativeVideoOverlayHost {
            return overlayHost
        }
        if let hostWindow = flutterHostViewController?.view.window,
           let overlayHost = hostWindow.nipaplayNativeVideoOverlayHost {
            return overlayHost
        }
        if let keyWindowHost = NSApp.keyWindow?.nipaplayNativeVideoOverlayHost {
            return keyWindowHost
        }
        if let mainWindowHost = NSApp.mainWindow?.nipaplayNativeVideoOverlayHost {
            return mainWindowHost
        }
        return NSApp.windows.compactMap(\.nipaplayNativeVideoOverlayHost).first
    }

    private func ensureWindowHostedOverlayInstalled() -> MacOSWindowNativeVideoOverlayView? {
        guard let activeFlutterHostView else {
            return nil
        }
        guard let hostWindow = activeFlutterHostView.window else {
            return nil
        }
        guard let hostSuperview = activeFlutterHostView.superview else {
            return nil
        }

        let overlayHost = windowHostedOverlay ??
            hostWindow.nipaplayNativeVideoOverlayHost ??
            MacOSWindowNativeVideoOverlayView(frame: .zero)
        let previousWindow = overlayHost.window

        if overlayHost.superview !== hostSuperview {
            overlayHost.removeFromSuperview()
            overlayHost.frame = .zero
            overlayHost.translatesAutoresizingMaskIntoConstraints = true
            hostSuperview.addSubview(
                overlayHost,
                positioned: shouldPlaceWindowHostedOverlayAboveFlutter() ? .above : .below,
                relativeTo: activeFlutterHostView
            )
        } else {
            hostSuperview.addSubview(
                overlayHost,
                positioned: shouldPlaceWindowHostedOverlayAboveFlutter() ? .above : .below,
                relativeTo: activeFlutterHostView
            )
        }

        if previousWindow !== hostWindow {
            previousWindow?.nipaplayNativeVideoOverlayHost = nil
        }
        hostWindow.nipaplayNativeVideoOverlayHost = overlayHost
        windowHostedOverlay = overlayHost
        return overlayHost
    }

    /// The player page can move between FlutterViews without rebuilding its
    /// State. Follow the active Flutter window so the existing native renderer
    /// moves with that page instead of remaining under the main window.
    private var activeFlutterHostView: NSView? {
        if let requestedFlutterViewIdentifier,
           let requestedController = NSApp.windows
            .compactMap(\.nipaplayFlutterViewController)
            .first(where: {
                Int64($0.viewIdentifier) == requestedFlutterViewIdentifier
            }) {
            return requestedController.view
        }
        if let keyController = NSApp.keyWindow?.nipaplayFlutterViewController {
            return keyController.view
        }
        if let mainController = NSApp.mainWindow?.nipaplayFlutterViewController {
            return mainController.view
        }
        return flutterHostView ?? flutterHostViewController?.view
    }

    private func shouldPlaceWindowHostedOverlayAboveFlutter() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["NIPAPLAY_MACOS_HDR_WINDOW_OVERLAY_BELOW"] == "1" {
            return false
        }
        return environment["NIPAPLAY_MACOS_HDR_WINDOW_OVERLAY_ABOVE"] == "1"
    }

    private func convertedRectValue(
        from args: [String: Any],
        host: NSView & MacOSNativeVideoSurfaceHost
    ) -> CGRect? {
        guard let x = doubleValue(args["x"]),
              let y = doubleValue(args["y"]),
              let width = doubleValue(args["width"]),
              let height = doubleValue(args["height"]) else {
            return nil
        }
        guard width > 0, height > 0 else {
            return nil
        }
        guard let activeFlutterHostView else {
            return CGRect(x: x, y: y, width: width, height: height)
        }
        guard let targetSuperview = host.hostView.superview else {
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let sourceY = activeFlutterHostView.isFlipped
            ? y
            : activeFlutterHostView.bounds.height - y - height
        let rect = CGRect(x: x, y: sourceY, width: width, height: height)
        return activeFlutterHostView.convert(rect, to: targetSuperview)
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        }
        return nil
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

final class MacOSNativeVideoPlatformView: NSView, MacOSNativeVideoSurfaceHost {
    let platformViewId: Int64
    var hostView: NSView { self }

    private weak var plugin: MacOSNativeVideoPlugin?
    private var videoRenderer: MediaKitOpenGLVideoRenderer?
    private var attachedPlayerHandle: Int64?

    init(viewIdentifier viewId: Int64, arguments args: Any?, plugin: MacOSNativeVideoPlugin?) {
        self.platformViewId = viewId
        self.plugin = plugin
        super.init(frame: .zero)

        installBaseLayer()
        layerContentsRedrawPolicy = .duringViewResize
        autoresizingMask = [.width, .height]

        if macOSNativeVideoDebugLabelsEnabled,
           let params = args as? [String: Any],
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
        detachPlayer()
        plugin?.unregisterView(viewId: platformViewId)
    }

    override func layout() {
        super.layout()
        videoRenderer?.layer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        videoRenderer?.hostViewDidChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoRenderer?.hostViewDidChange()
    }

    func attachPlayer(handle: Int64) {
        if attachedPlayerHandle == handle, let existing = videoRenderer {
            existing.hostViewDidChange()
            return
        }

        detachPlayer()
        guard let renderer = MediaKitOpenGLVideoRenderer(
            playerHandle: handle,
            hostView: self
        ) else {
            NSLog("MacOSNativeVideoPlatformView: failed to create libmpv OpenGL renderer")
            return
        }
        videoRenderer = renderer
        attachedPlayerHandle = handle
        renderer.hostViewDidChange()
    }

    func detachPlayer() {
        videoRenderer?.detach()
        videoRenderer = nil
        attachedPlayerHandle = nil
        installBaseLayer()
    }

    private func installBaseLayer() {
        wantsLayer = true
        if layer == nil || layer is CAOpenGLLayer {
            layer = CALayer()
        }
        layer?.backgroundColor = NSColor.black.cgColor
    }
}

/// Flutter's legacy macOS registrar accessors are hard-coded to view id 0.
/// A multiview engine assigns real views ids starting at 1, so unmodified
/// plugins such as window_manager would otherwise see a nil main window.
/// Keep those backwards-compatible accessors useful until Flutter exposes a
/// public view-aware registrar API.
private final class MultiviewPluginRegistrarCompatibility {
  static let shared = MultiviewPluginRegistrarCompatibility()

  private weak var mainViewController: FlutterViewController?
  private var isInstalled = false

  private init() {}

  func install(
    registrar: FlutterPluginRegistrar,
    mainViewController: FlutterViewController
  ) {
    self.mainViewController = mainViewController
    guard !isInstalled else {
      return
    }

    guard let registrarClass = object_getClass(registrar as AnyObject) else {
      preconditionFailure("Unable to inspect Flutter's plugin registrar")
    }

    replaceGetter(
      on: registrarClass,
      named: "view",
      block: { [weak self] (_: AnyObject) -> NSView? in
        self?.activeFlutterViewController?.view
      } as @convention(block) (AnyObject) -> NSView?
    )
    replaceGetter(
      on: registrarClass,
      named: "viewController",
      block: { [weak self] (_: AnyObject) -> NSViewController? in
        self?.activeFlutterViewController
      } as @convention(block) (AnyObject) -> NSViewController?
    )
    isInstalled = true
  }

  private var activeFlutterViewController: FlutterViewController? {
    if let activeController = NSApp.keyWindow?.contentViewController
        as? FlutterViewController {
      return activeController
    }
    return mainViewController
  }

  private func replaceGetter<T>(
    on registrarClass: AnyClass,
    named name: String,
    block: T
  ) {
    let selector = NSSelectorFromString(name)
    guard let method = class_getInstanceMethod(registrarClass, selector),
          let typeEncoding = method_getTypeEncoding(method) else {
      preconditionFailure("Flutter's plugin registrar is missing \(name)")
    }
    class_replaceMethod(
      registrarClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }
}

private final class DesktopMultiWindowHostPlugin: NSObject, FlutterPlugin {
  private static let channelName = "nipaplay/desktop_multi_window_host"
  private struct WindowDragState {
    let mouseLocation: NSPoint
    let windowOrigin: NSPoint
  }

  private var dragStates: [Int: WindowDragState] = [:]
  private var detachedPlayerClasses: Set<ObjectIdentifier> = []
  private var interactivePopupClasses: Set<ObjectIdentifier> = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(
      DesktopMultiWindowHostPlugin(),
      channel: channel
    )
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      NSLog(
        "[DesktopMultiWindow][Host] invalid arguments method=%@",
        call.method
      )
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Desktop window host arguments are missing",
        details: nil
      ))
      return
    }
    guard let window = resolveWindow(arguments) else {
      NSLog(
        "[DesktopMultiWindow][Host] window not found method=%@ viewId=%@",
        call.method,
        String(describing: arguments["viewId"])
      )
      result(FlutterError(
        code: "WINDOW_NOT_FOUND",
        message: "No macOS window owns the requested FlutterView",
        details: nil
      ))
      return
    }

    switch call.method {
    case "configureWindow":
      if boolValue(arguments["frameless"]) == true {
        makeFrameless(window)
      }
      applyAspectRatio(arguments["aspectRatio"], to: window)
      applyPreferredContentSize(arguments, to: window)
      let alwaysOnTop = boolValue(arguments["alwaysOnTop"]) ?? false
      applyAlwaysOnTop(alwaysOnTop, to: window)
      result(alwaysOnTop)
    case "setAspectRatio":
      applyAspectRatio(arguments["aspectRatio"], to: window)
      result(nil)
    case "setAlwaysOnTop":
      let alwaysOnTop = boolValue(arguments["alwaysOnTop"]) ?? false
      applyAlwaysOnTop(alwaysOnTop, to: window)
      result(alwaysOnTop)
    case "setPictureInPictureMode":
      applyPictureInPictureMode(arguments, to: window)
      result(nil)
    case "configureTransientWindow":
      // Flutter 3.44 initially creates popup views at 0x0. Supplying tight
      // Dart constraints alone does not produce valid view metrics on macOS,
      // so seed the native content size before the first rendered frame.
      let viewIdentifier = int64Value(arguments["viewId"]) ?? -1
      let requestedWidth = doubleValue(arguments["width"]) ?? -1
      let requestedHeight = doubleValue(arguments["height"]) ?? -1
      let interactive = boolValue(arguments["interactive"]) ?? false
      NSLog(
        "[DesktopMultiWindow][Transient] configure viewId=%lld interactive=%@ requested=%.1fx%.1f beforeContent=%@ beforeFrame=%@ class=%@",
        viewIdentifier,
        interactive.description,
        requestedWidth,
        requestedHeight,
        NSStringFromSize(window.contentView?.bounds.size ?? .zero),
        NSStringFromRect(window.frame),
        NSStringFromClass(type(of: window))
      )
      applyPreferredContentSize(arguments, to: window)
      if interactive {
        makeInteractivePopup(window)
      }
      NSLog(
        "[DesktopMultiWindow][Transient] configured viewId=%lld afterContent=%@ afterFrame=%@ visible=%@ level=%ld",
        viewIdentifier,
        NSStringFromSize(window.contentView?.bounds.size ?? .zero),
        NSStringFromRect(window.frame),
        window.isVisible.description,
        window.level.rawValue
      )
      result(nil)
    case "startDragging":
      dragStates[window.windowNumber] = WindowDragState(
        mouseLocation: NSEvent.mouseLocation,
        windowOrigin: window.frame.origin
      )
      result(nil)
    case "updateDragging":
      guard let dragState = dragStates[window.windowNumber] else {
        result(nil)
        return
      }
      let mouseLocation = NSEvent.mouseLocation
      window.setFrameOrigin(NSPoint(
        x: dragState.windowOrigin.x + mouseLocation.x - dragState.mouseLocation.x,
        y: dragState.windowOrigin.y + mouseLocation.y - dragState.mouseLocation.y
      ))
      result(nil)
    case "endDragging":
      dragStates.removeValue(forKey: window.windowNumber)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func resolveWindow(_ arguments: [String: Any]) -> NSWindow? {
    guard let viewIdentifier = int64Value(arguments["viewId"]) else {
      return nil
    }
    return NSApp.windows.first(where: { window in
      guard let controller = window.nipaplayFlutterViewController else {
        return false
      }
      return Int64(controller.viewIdentifier) == viewIdentifier
    })
  }

  private func makeFrameless(_ window: NSWindow) {
    if !window.nipaplayIsDetachedPlayerWindow {
      // Never change the runtime class of an AppKit window. NSWindow owns
      // private KVO registrations for its titlebar and layer context; replacing
      // its class makes those observers crash either immediately or at deinit.
      installDetachedPlayerBehavior(on: window)
      window.nipaplayIsDetachedPlayerWindow = true
      var styleMask = window.styleMask
      styleMask.remove([.titled, .fullSizeContentView])
      styleMask.insert([
        .closable,
        .miniaturizable,
        .resizable,
        .nonactivatingPanel,
      ])
      window.styleMask = styleMask
    }
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.hasShadow = true
  }

  private func installDetachedPlayerBehavior(on window: NSWindow) {
    guard let targetClass = object_getClass(window) else {
      return
    }
    let classIdentifier = ObjectIdentifier(targetClass)
    guard detachedPlayerClasses.insert(classIdentifier).inserted else {
      return
    }

    // A non-activating frameless NSWindow does not accept Flutter pointer
    // input unless it can become key. Patch the existing Flutter window class
    // conditionally, keeping the original behavior for the main window and all
    // other instances of that class.
    replaceDetachedWindowBoolGetter(
      on: targetClass,
      named: "canBecomeKeyWindow",
      detachedValue: true
    )
    replaceDetachedWindowBoolGetter(
      on: targetClass,
      named: "canBecomeMainWindow",
      detachedValue: false
    )
    replaceDetachedWindowBoolGetter(
      on: targetClass,
      named: "acceptsFirstResponder",
      detachedValue: true
    )
  }

  private func replaceDetachedWindowBoolGetter(
    on targetClass: AnyClass,
    named name: String,
    detachedValue: Bool
  ) {
    let selector = NSSelectorFromString(name)
    guard let method = class_getInstanceMethod(targetClass, selector),
          let typeEncoding = method_getTypeEncoding(method) else {
      return
    }
    typealias OriginalBoolGetter = @convention(c) (
      AnyObject,
      Selector
    ) -> Bool
    let originalGetter = unsafeBitCast(
      method_getImplementation(method),
      to: OriginalBoolGetter.self
    )
    let getter = { (object: AnyObject) -> Bool in
      if let candidate = object as? NSWindow,
         candidate.nipaplayIsDetachedPlayerWindow {
        return detachedValue
      }
      return originalGetter(object, selector)
    } as @convention(block) (AnyObject) -> Bool
    class_replaceMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(getter),
      typeEncoding
    )
  }

  private func makeInteractivePopup(_ window: NSWindow) {
    guard let panel = window as? NSPanel,
          let popupClass = object_getClass(window) else {
      return
    }
    let classIdentifier = ObjectIdentifier(popupClass)
    if interactivePopupClasses.insert(classIdentifier).inserted {
      // FlutterPopupWindow deliberately rejects focus. Override its getters on
      // the existing class instead of replacing an individual panel's class;
      // the latter corrupts AppKit's private KVO bookkeeping at deallocation.
      replaceBoolGetter(on: popupClass, named: "canBecomeKeyWindow", value: true)
      replaceBoolGetter(on: popupClass, named: "canBecomeMainWindow", value: false)
      replaceBoolGetter(on: popupClass, named: "acceptsFirstResponder", value: true)
    }
    window.hidesOnDeactivate = false
    window.isExcludedFromWindowsMenu = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.isFloatingPanel = true
  }

  private func replaceBoolGetter(
    on targetClass: AnyClass,
    named name: String,
    value: Bool
  ) {
    let selector = NSSelectorFromString(name)
    guard let method = class_getInstanceMethod(targetClass, selector),
          let typeEncoding = method_getTypeEncoding(method) else {
      return
    }
    let getter = { (_: AnyObject) -> Bool in value }
      as @convention(block) (AnyObject) -> Bool
    class_replaceMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(getter),
      typeEncoding
    )
  }

  private func applyAspectRatio(_ value: Any?, to window: NSWindow) {
    guard let aspectRatio = doubleValue(value),
          aspectRatio.isFinite,
          aspectRatio > 0 else {
      return
    }
    window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)
  }

  private func applyPreferredContentSize(
    _ arguments: [String: Any],
    to window: NSWindow
  ) {
    guard let width = doubleValue(arguments["width"]),
          let height = doubleValue(arguments["height"]),
          width > 0,
          height > 0 else {
      return
    }
    window.setContentSize(NSSize(width: width, height: height))
  }

  private func applyAlwaysOnTop(_ alwaysOnTop: Bool, to window: NSWindow) {
    window.level = alwaysOnTop ? .floating : .normal
    window.hidesOnDeactivate = false
    window.isExcludedFromWindowsMenu = true
    var collectionBehavior = window.collectionBehavior
    if alwaysOnTop {
      collectionBehavior.insert([
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
      ])
    } else {
      collectionBehavior.remove([
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
      ])
    }
    window.collectionBehavior = collectionBehavior
  }

  private func applyPictureInPictureMode(
    _ arguments: [String: Any],
    to window: NSWindow
  ) {
    let enabled = boolValue(arguments["enabled"]) ?? false
    if !enabled {
      guard let restoreFrame = window.nipaplayPictureInPictureRestoreFrame else {
        return
      }
      window.nipaplayPictureInPictureRestoreFrame = nil
      NSLog(
        "[DesktopMultiWindow][PiP] restore frame=%@",
        NSStringFromRect(restoreFrame)
      )
      window.setFrame(restoreFrame, display: true, animate: true)
      return
    }

    if window.nipaplayPictureInPictureRestoreFrame == nil {
      window.nipaplayPictureInPictureRestoreFrame = window.frame
    }
    guard let screen = window.screen ?? NSScreen.main else {
      return
    }
    let visibleFrame = screen.visibleFrame
    let aspectRatio = max(
      0.5,
      min(3.0, doubleValue(arguments["aspectRatio"]) ?? (16.0 / 9.0))
    )
    let margin = max(0, doubleValue(arguments["margin"]) ?? 16)
    let availableWidth = max(1, visibleFrame.width - margin * 2)
    let availableHeight = max(1, visibleFrame.height - margin * 2)
    var contentHeight = min(visibleFrame.height / 3, availableHeight)
    var contentWidth = contentHeight * aspectRatio
    if contentWidth > availableWidth {
      contentWidth = availableWidth
      contentHeight = contentWidth / aspectRatio
    }
    window.setContentSize(NSSize(width: contentWidth, height: contentHeight))

    let frameSize = window.frame.size
    let placement = stringValue(arguments["placement"]) ?? "topRight"
    let left = visibleFrame.minX + margin
    let right = visibleFrame.maxX - frameSize.width - margin
    let bottom = visibleFrame.minY + margin
    let top = visibleFrame.maxY - frameSize.height - margin
    let origin: NSPoint
    switch placement {
    case "topLeft":
      origin = NSPoint(x: left, y: top)
    case "bottomLeft":
      origin = NSPoint(x: left, y: bottom)
    case "bottomRight":
      origin = NSPoint(x: right, y: bottom)
    case "topRight":
      fallthrough
    default:
      origin = NSPoint(x: right, y: top)
    }
    NSLog(
      "[DesktopMultiWindow][PiP] dock placement=%@ screen=%@ content=%.1fx%.1f origin=%@",
      placement,
      NSStringFromRect(visibleFrame),
      contentWidth,
      contentHeight,
      NSStringFromPoint(origin)
    )
    window.setFrameOrigin(origin)
  }

  private func int64Value(_ value: Any?) -> Int64? {
    if let value = value as? Int64 {
      return value
    }
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return nil
  }

  private func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double {
      return value
    }
    if let value = value as? NSNumber {
      return value.doubleValue
    }
    return nil
  }

  private func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    return nil
  }

  private func stringValue(_ value: Any?) -> String? {
    value as? String
  }
}

class MainFlutterWindow: NSWindow {
  private var nipaplayFlutterEngine: FlutterEngine?

  override func awakeFromNib() {
    // macOS must enter multiview mode before its first FlutterViewController
    // is attached. The Dart-side window fork then reuses this same engine.
    let flutterEngine = FlutterEngine(
      name: "io.flutter",
      project: nil,
      allowHeadlessExecution: true
    )
    let enableMultiView = NSSelectorFromString("enableMultiView")
    precondition(
      flutterEngine.responds(to: enableMultiView),
      "This Flutter engine does not expose same-engine desktop multiview"
    )
    flutterEngine.perform(enableMultiView)
    precondition(
      flutterEngine.run(withEntrypoint: nil),
      "Failed to start the multiview Flutter engine"
    )
    nipaplayFlutterEngine = flutterEngine

    let flutterViewController = FlutterViewController(
      engine: flutterEngine,
      nibName: nil,
      bundle: nil
    )
    if Self.shouldUseTransparentFlutterSurface() {
      self.isOpaque = false
      self.backgroundColor = NSColor.clear
      flutterViewController.backgroundColor = NSColor.clear
    }
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentView?.layoutSubtreeIfNeeded()

    // The engine was started before this non-implicit view existed, so its
    // automatic startup metrics pass could not include the main window.
    // Seed the real dimensions now instead of leaving the first Dart view at
    // the zero-sized placeholder used by FlutterAddView.
    let updateMetrics = NSSelectorFromString(
      "updateWindowMetricsForViewController:"
    )
    precondition(
      flutterEngine.responds(to: updateMetrics),
      "This Flutter engine cannot seed multiview window metrics"
    )
    flutterEngine.perform(updateMetrics, with: flutterViewController)

    let compatibilityRegistrar = flutterViewController.registrar(
      forPlugin: "NipaPlayMultiviewRegistrarCompatibility"
    )
    MultiviewPluginRegistrarCompatibility.shared.install(
      registrar: compatibilityRegistrar,
      mainViewController: flutterViewController
    )

    DesktopMultiWindowHostPlugin.register(
      with: flutterViewController.registrar(
        forPlugin: "DesktopMultiWindowHostPlugin"
      )
    )

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // 注册自定义安全书签插件
    SecurityBookmarkPlugin.register(with: flutterViewController.registrar(forPlugin: "SecurityBookmarkPlugin"))
    SystemSharePlugin.register(with: flutterViewController.registrar(forPlugin: "SystemSharePlugin"))
    MacOSNativeVideoPlugin.register(with: flutterViewController.registrar(forPlugin: "MacOSNativeVideoPlugin"))

    super.awakeFromNib()
  }

  private static func shouldUseTransparentFlutterSurface() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    if environment["NIPAPLAY_MACOS_HDR_USE_APPKIT_VIEW"] == "1" ||
       environment["NIPAPLAY_DISABLE_MACOS_WINDOW_OVERLAY"] == "1" {
      return false
    }
    return environment["NIPAPLAY_MACOS_HDR_TRANSPARENT_FLUTTER"] != "0"
  }
}
