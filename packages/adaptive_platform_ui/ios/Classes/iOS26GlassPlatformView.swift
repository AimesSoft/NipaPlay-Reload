import Flutter
import UIKit

/// Factory for bare Liquid Glass surfaces.
class iOS26GlassViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26GlassPlatformView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// A Liquid Glass surface with nothing on it: Flutter draws the content
/// above. A capsule unless a corner radius is given. It takes no touches;
/// what sits on it handles them.
class iOS26GlassPlatformView: NSObject, FlutterPlatformView {
    private let effectView: UIVisualEffectView
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        effectView = UIVisualEffectView(effect: nil)
        effectView.frame = frame
        effectView.isUserInteractionEnabled = false
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_glass_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        apply(args as? [String: Any] ?? [:])
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update", let self else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.apply(call.arguments as? [String: Any] ?? [:])
            result(nil)
        }
    }

    func view() -> UIView {
        return effectView
    }

    private func apply(_ params: [String: Any]) {
        let radius = (params["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) }
        let tint = (params["tint"] as? NSNumber).map { Self.color($0.intValue) }
        let clear = (params["style"] as? String) == "clear"
        // Whatever the system appearance, the glass matches the app's.
        if let dark = params["dark"] as? Bool {
            effectView.overrideUserInterfaceStyle = dark ? .dark : .light
        }
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: clear ? .clear : .regular)
            glass.tintColor = tint
            effectView.effect = glass
            effectView.cornerConfiguration = radius.map { .corners(radius: .fixed($0)) } ?? .capsule()
        } else {
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            effectView.layer.cornerRadius = radius ?? effectView.bounds.height / 2
            effectView.clipsToBounds = true
        }
    }

    private static func color(_ argb: Int) -> UIColor {
        return UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}
