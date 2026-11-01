import Flutter
import UIKit

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
        MediaDetailControlView(frame, viewId, messenger, args as? [String: Any] ?? [:])
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
        var config: UIButton.Configuration = primary ? .prominentGlass() : .glass()
        config.title = args["label"] as? String
        config.subtitle = args["detail"] as? String
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
        config.imagePadding = 10
        config.titlePadding = 2
        config.titleAlignment = .leading
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
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
