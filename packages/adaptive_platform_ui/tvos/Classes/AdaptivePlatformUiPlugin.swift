import UIKit
import SwiftUI
import Metal
import Flutter

public final class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "nipaplay/native_media_controls", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            guard call.method == "supportsGlass" else { result(FlutterMethodNotImplemented); return }
            guard #available(tvOS 26.0, *) else { result(false); return }
#if targetEnvironment(simulator)
            result(true)
#else
            // Apple limits Liquid Glass to Apple TV 4K (2nd generation, A12)
            // and newer. Apple GPU family 5 starts at A12, excluding HD/A10X.
            result(MTLCreateSystemDefaultDevice()?.supportsFamily(.apple5) ?? false)
#endif
        }
        registrar.register(MediaControlFactory(registrar.messenger()), withId: "nipaplay/native_media_control")
    }
}

private final class MediaControlFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let params = args as? [String: Any] ?? [:]
        if #available(tvOS 26.0, *), params["actions"] != nil {
            return MediaActionGroupView(frame, viewId, messenger, params)
        }
        return MediaControlView(frame, viewId, messenger, params)
    }
}

private final class MediaControlView: NSObject, FlutterPlatformView {
    let button = UIButton(type: .system)
    let channel: FlutterMethodChannel
    init(_ frame: CGRect, _ id: Int64, _ messenger: FlutterBinaryMessenger, _ args: [String: Any]) {
        channel = FlutterMethodChannel(name: "nipaplay/native_media_control_\(id)", binaryMessenger: messenger)
        super.init()
        button.frame = frame
        button.addTarget(self, action: #selector(pressed), for: .primaryActionTriggered)
        update(args)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
            if let args = call.arguments as? [String: Any] { self?.update(args) }
            result(nil)
        }
    }
    deinit { channel.setMethodCallHandler(nil) }
    func view() -> UIView { button }
    func update(_ args: [String: Any]) {
        guard #available(tvOS 26.0, *) else { return }
        var config: UIButton.Configuration = (args["plain"] as? Bool ?? false)
            ? .plain() : ((args["primary"] as? Bool ?? false) ? .prominentGlass() : .glass())
        let iconOnly = args["iconOnly"] as? Bool ?? false
        config.title = iconOnly ? nil : args["label"] as? String
        config.subtitle = iconOnly ? nil : args["detail"] as? String
        config.baseForegroundColor = .white
        button.accessibilityLabel = args["label"] as? String
        config.image = UIImage(systemName: args["symbol"] as? String ?? "")
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return result
        }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = UIFont.systemFont(ofSize: 11)
            return result
        }
        config.imagePadding = 10
        config.cornerStyle = .capsule
        if let argb = args["color"] as? NSNumber {
            let value = argb.uint32Value
            config.baseBackgroundColor = UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
                alpha: CGFloat((value >> 24) & 255) / 255)
        }
        button.configuration = config
        button.isEnabled = args["enabled"] as? Bool ?? false
        if let entries = args["items"] as? [[String: Any]] {
            button.menu = UIMenu(children: entries.enumerated().map { index, entry in
                UIAction(title: entry["label"] as? String ?? "", attributes: (entry["enabled"] as? Bool ?? true) ? [] : .disabled) { [weak self] _ in
                    self?.channel.invokeMethod("selected", arguments: index)
                }
            })
            button.showsMenuAsPrimaryAction = true
        } else {
            button.menu = nil
            button.showsMenuAsPrimaryAction = false
        }
    }
    @objc func pressed() {
        if #available(tvOS 17.0, *), button.menu != nil { return }
        channel.invokeMethod("pressed", arguments: nil)
    }
}


/// One SwiftUI host owns the shared interactive glass and its native controls.
@available(tvOS 26.0, *)
final class MediaActionGroupView: NSObject, FlutterPlatformView {
    let model = MediaCapsuleModel()
    let container: MediaCapsuleHostingContainer
    private let channel: FlutterMethodChannel

    init(_ frame: CGRect, _ id: Int64, _ messenger: FlutterBinaryMessenger,
         _ args: [String: Any]) {
        container = MediaCapsuleHostingContainer(frame: frame, model: model)
        channel = FlutterMethodChannel(name: "nipaplay/native_media_control_\(id)", binaryMessenger: messenger)
        super.init()
        model.onPressed = { [weak self] index in
            self?.channel.invokeMethod("pressed", arguments: ["index": index])
        }
        model.onSelected = { [weak self] index, selected in
            self?.channel.invokeMethod("selected", arguments: ["index": index, "selected": selected])
        }
        model.update(args)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
            if let args = call.arguments as? [String: Any] { self?.model.update(args) }
            result(nil)
        }
    }

    deinit { channel.setMethodCallHandler(nil) }
    func view() -> UIView { container }
    func update(_ args: [String: Any]) { model.update(args) }
}
