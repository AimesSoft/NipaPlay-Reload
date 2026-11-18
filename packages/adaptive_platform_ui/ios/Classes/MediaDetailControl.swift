import Flutter
import UIKit
import SwiftUI

extension AdaptivePlatformUiPlugin {
    static func registerMediaDetailControls(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "nipaplay/native_media_controls", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            guard call.method == "supportsGlass" else {
                result(FlutterMethodNotImplemented)
                return
            }
            if #available(iOS 26.0, *) { result(true) } else { result(false) }
        }
        registrar.register(MediaDetailControlFactory(registrar.messenger()),
                           withId: "nipaplay/native_media_control")
    }
}

private final class MediaDetailControlFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        let params = args as? [String: Any] ?? [:]
        if #available(iOS 26.0, *), params["actions"] != nil {
            return MediaDetailActionGroupView(frame, viewId, messenger, params)
        }
        return MediaDetailControlView(frame, viewId, messenger, params)
    }
}

/// Keep content inside UIButton so UIKit owns highlight, pointer, keyboard focus,
/// cancellation, and accessibility transitions as well as the glass material.
final class MediaDetailControlView: NSObject, FlutterPlatformView {
    let button = UIButton(type: .system)
    private let channel: FlutterMethodChannel

    init(_ frame: CGRect, _ id: Int64, _ messenger: FlutterBinaryMessenger,
         _ args: [String: Any]) {
        channel = FlutterMethodChannel(name: "nipaplay/native_media_control_\(id)",
                                       binaryMessenger: messenger)
        super.init()
        button.frame = frame
        if #available(iOS 13.0, *) {
            // This control is used on the dark immersive artwork surface.
            button.overrideUserInterfaceStyle = .dark
        }
        if #available(iOS 13.4, *) { button.isPointerInteractionEnabled = true }
        button.addTarget(self, action: #selector(pressed), for: .primaryActionTriggered)
        update(args)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update" else {
                result(FlutterMethodNotImplemented)
                return
            }
            if let args = call.arguments as? [String: Any] { self?.update(args) }
            result(nil)
        }
    }

    deinit { channel.setMethodCallHandler(nil) }
    func view() -> UIView { button }

    func update(_ args: [String: Any]) {
        guard #available(iOS 26.0, *) else { return }
        let primary = args["primary"] as? Bool ?? false
        var config: UIButton.Configuration = (args["plain"] as? Bool ?? false)
            ? .plain() : (primary ? .prominentGlass() : .glass())
        let iconOnly = args["iconOnly"] as? Bool ?? false
        config.title = iconOnly ? nil : args["label"] as? String
        config.subtitle = iconOnly ? nil : args["detail"] as? String
        config.image = UIImage(systemName: args["symbol"] as? String ?? "")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: UIFont.systemFont(ofSize: 15, weight: .semibold))
            return result
        }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
                for: UIFont.systemFont(ofSize: 11))
            return result
        }
        config.titleLineBreakMode = .byClipping
        config.imagePadding = iconOnly ? 0 : 10
        config.titlePadding = 2
        config.titleAlignment = .leading
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: iconOnly ? 0 : 16, bottom: 6, trailing: iconOnly ? 0 : 16)
        config.baseForegroundColor = .white
        if primary, let argb = args["color"] as? NSNumber {
            let value = argb.uint32Value
            let accent = UIColor(red: CGFloat((value >> 16) & 255) / 255,
                                 green: CGFloat((value >> 8) & 255) / 255,
                                 blue: CGFloat(value & 255) / 255,
                                 alpha: CGFloat((value >> 24) & 255) / 255)
            button.tintColor = accent
            config.baseBackgroundColor = accent
        } else {
            button.tintColor = .white
        }
        // No manual blur, opacity, scale animation, or UIGlassEffect overlay:
        // the system button handles Reduce Motion / Reduce Transparency and
        // contrast preferences, including changes while this view is visible.
        button.configuration = config
        button.titleLabel?.numberOfLines = 1
        button.accessibilityLabel = args["label"] as? String
        button.isEnabled = args["enabled"] as? Bool ?? false

        if let entries = args["items"] as? [[String: Any]] {
            button.menu = UIMenu(children: entries.enumerated().map { index, entry in
                UIAction(title: entry["label"] as? String ?? "",
                         attributes: (entry["enabled"] as? Bool ?? true) ? [] : .disabled) { [weak self] _ in
                    self?.channel.invokeMethod("selected", arguments: index)
                }
            })
            button.showsMenuAsPrimaryAction = true
        } else {
            button.menu = nil
            button.showsMenuAsPrimaryAction = false
        }
    }

    @objc private func pressed() {
        if #available(iOS 14.0, *), button.menu != nil { return }
        channel.invokeMethod("pressed", arguments: nil)
    }
}


/// One SwiftUI host owns the shared interactive glass and its native controls.
@available(iOS 26.0, *)
final class MediaDetailActionGroupView: NSObject, FlutterPlatformView {
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
