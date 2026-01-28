import UIKit
import Flutter

/// Factory for creating iOS 26 native blur view platform views
class iOS26BlurViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26BlurViewPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Native iOS 26 blur view using UIVisualEffectView
class iOS26BlurViewPlatformView: NSObject, FlutterPlatformView {
    private var _blurView: UIVisualEffectView
    private var _channel: FlutterMethodChannel
    private var _viewId: Int64

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _viewId = viewId

        // Parse blur style from arguments
        var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        if let params = args as? [String: Any],
           let styleString = params["blurStyle"] as? String {
            blurStyle = iOS26BlurViewPlatformView.parseBlurStyle(styleString)
        }

        // Create blur effect and view
        let blurEffect = UIBlurEffect(style: blurStyle)
        _blurView = UIVisualEffectView(effect: blurEffect)
        _blurView.frame = frame
        _blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Setup method channel
        _channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_blur_view_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        // Setup method channel handler
        _channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _blurView
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateBlurStyle":
            if let args = call.arguments as? [String: Any],
               let styleString = args["blurStyle"] as? String {
                let blurStyle = iOS26BlurViewPlatformView.parseBlurStyle(styleString)
                let blurEffect = UIBlurEffect(style: blurStyle)
                _blurView.effect = blurEffect
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Parse blur style string to UIBlurEffect.Style
    private static func parseBlurStyle(_ styleString: String) -> UIBlurEffect.Style {
        switch styleString {
        case "systemUltraThinMaterial":
            if #available(iOS 13.0, *) {
                return .systemUltraThinMaterial
            } else {
                return .light
            }
        case "systemThinMaterial":
            if #available(iOS 13.0, *) {
                return .systemThinMaterial
            } else {
                return .light
            }
        case "systemMaterial":
            if #available(iOS 13.0, *) {
                return .systemMaterial
            } else {
                return .light
            }
        case "systemThickMaterial":
            if #available(iOS 13.0, *) {
                return .systemThickMaterial
            } else {
                return .dark
            }
        case "systemChromeMaterial":
            if #available(iOS 13.0, *) {
                return .systemChromeMaterial
            } else {
                return .dark
            }
        default:
            if #available(iOS 13.0, *) {
                return .systemUltraThinMaterial
            } else {
                return .light
            }
        }
    }
}
