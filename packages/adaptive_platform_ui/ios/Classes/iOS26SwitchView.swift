import Flutter
import UIKit

/// Factory for creating iOS 26 native switch platform views
class iOS26SwitchViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26SwitchView(
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

/// Native iOS 26 switch implementation with native UISwitch
class iOS26SwitchView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var switchControl: UISwitch!
    private var channel: FlutterMethodChannel
    private var switchId: Int

    // Configuration
    private var isEnabled: Bool = true
    private var isDark: Bool = false

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _view = UIView(frame: frame)

        // Extract configuration from arguments
        if let config = args as? [String: Any] {
            switchId = config["id"] as? Int ?? 0
            isEnabled = config["enabled"] as? Bool ?? true
            isDark = config["isDark"] as? Bool ?? false
        } else {
            switchId = 0
        }

        // Setup method channel for communication
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_switch_\(switchId)",
            binaryMessenger: messenger
        )

        super.init()

        // Create the native switch
        createNativeSwitch(with: args)

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _view
    }

    private func createNativeSwitch(with args: Any?) {
        // Create iOS UISwitch
        switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false

        // Enable user interaction
        switchControl.isUserInteractionEnabled = true
        _view.isUserInteractionEnabled = true

        // Extract initial configuration
        if let config = args as? [String: Any] {
            // Set initial value
            if let value = config["value"] as? Bool {
                switchControl.isOn = value
            }

            // Set active (on) color
            if let argb = config["activeColor"] as? Int {
                switchControl.onTintColor = UIColor(argb: argb)
            }

            // Set thumb color
            if let argb = config["thumbColor"] as? Int {
                switchControl.thumbTintColor = UIColor(argb: argb)
            }
        }

        // Setup constraints
        _view.addSubview(switchControl)
        NSLayoutConstraint.activate([
            switchControl.leadingAnchor.constraint(equalTo: _view.leadingAnchor),
            switchControl.trailingAnchor.constraint(equalTo: _view.trailingAnchor),
            switchControl.topAnchor.constraint(equalTo: _view.topAnchor),
            switchControl.bottomAnchor.constraint(equalTo: _view.bottomAnchor),
        ])

        // Add value changed action
        switchControl.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)

        // Apply enabled state
        switchControl.isEnabled = isEnabled
    }

    @objc private func switchValueChanged() {
        // Notify Flutter side about value change
        channel.invokeMethod("valueChanged", arguments: ["value": switchControl.isOn])

        // Add haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setValue":
            if let args = call.arguments as? [String: Any],
               let value = args["value"] as? Bool {
                switchControl.setOn(value, animated: true)
            }
            result(nil)

        case "setEnabled":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                isEnabled = enabled
                switchControl.isEnabled = enabled
                switchControl.alpha = enabled ? 1.0 : 0.5
            }
            result(nil)

        case "setActiveColor":
            if let args = call.arguments as? [String: Any],
               let argb = args["color"] as? Int {
                switchControl.onTintColor = UIColor(argb: argb)
            }
            result(nil)

        case "setThumbColor":
            if let args = call.arguments as? [String: Any],
               let argb = args["color"] as? Int {
                switchControl.thumbTintColor = UIColor(argb: argb)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
