import Flutter
import UIKit

/// Factory for creating iOS 26 native slider platform views
class iOS26SliderViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26SliderView(
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

/// Native iOS 26 slider implementation with native UISlider
class iOS26SliderView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var sliderControl: UISlider!
    private var channel: FlutterMethodChannel
    private var sliderId: Int

    // Configuration
    private var minValue: Float = 0.0
    private var maxValue: Float = 1.0
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
            sliderId = config["id"] as? Int ?? 0
            isEnabled = config["enabled"] as? Bool ?? true
            isDark = config["isDark"] as? Bool ?? false

            if let min = config["min"] as? Double {
                minValue = Float(min)
            }
            if let max = config["max"] as? Double {
                maxValue = Float(max)
            }
        } else {
            sliderId = 0
        }

        // Setup method channel for communication
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_slider_\(sliderId)",
            binaryMessenger: messenger
        )

        super.init()

        // Create the native slider
        createNativeSlider(with: args)

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _view
    }

    private func createNativeSlider(with args: Any?) {
        // Create iOS UISlider
        sliderControl = UISlider()
        sliderControl.translatesAutoresizingMaskIntoConstraints = false

        // Enable user interaction
        sliderControl.isUserInteractionEnabled = true
        _view.isUserInteractionEnabled = true

        // Set min/max values
        sliderControl.minimumValue = minValue
        sliderControl.maximumValue = maxValue

        // Extract initial configuration
        if let config = args as? [String: Any] {
            // Set initial value
            if let value = config["value"] as? Double {
                sliderControl.value = Float(value)
            }

            // Set active (track) color
            if let argb = config["activeColor"] as? Int {
                sliderControl.minimumTrackTintColor = UIColor(argb: argb)
            }

            // Set thumb color
            if let argb = config["thumbColor"] as? Int {
                sliderControl.thumbTintColor = UIColor(argb: argb)
            }
        }

        // Setup constraints
        _view.addSubview(sliderControl)
        NSLayoutConstraint.activate([
            sliderControl.leadingAnchor.constraint(equalTo: _view.leadingAnchor),
            sliderControl.trailingAnchor.constraint(equalTo: _view.trailingAnchor),
            sliderControl.topAnchor.constraint(equalTo: _view.topAnchor),
            sliderControl.bottomAnchor.constraint(equalTo: _view.bottomAnchor),
        ])

        // Add value changed actions
        sliderControl.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        sliderControl.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        sliderControl.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside])

        // Apply enabled state
        sliderControl.isEnabled = isEnabled
    }

    @objc private func sliderValueChanged() {
        // Notify Flutter side about value change
        channel.invokeMethod("valueChanged", arguments: ["value": Double(sliderControl.value)])

        // Add haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    @objc private func sliderTouchDown() {
        // Notify Flutter side about touch start
        channel.invokeMethod("changeStart", arguments: ["value": Double(sliderControl.value)])
    }

    @objc private func sliderTouchUp() {
        // Notify Flutter side about touch end
        channel.invokeMethod("changeEnd", arguments: ["value": Double(sliderControl.value)])

        // Add haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setValue":
            if let args = call.arguments as? [String: Any],
               let value = args["value"] as? Double {
                sliderControl.setValue(Float(value), animated: true)
            }
            result(nil)

        case "setRange":
            if let args = call.arguments as? [String: Any] {
                if let min = args["min"] as? Double {
                    minValue = Float(min)
                    sliderControl.minimumValue = minValue
                }
                if let max = args["max"] as? Double {
                    maxValue = Float(max)
                    sliderControl.maximumValue = maxValue
                }
            }
            result(nil)

        case "setEnabled":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                isEnabled = enabled
                sliderControl.isEnabled = enabled
                sliderControl.alpha = enabled ? 1.0 : 0.5
            }
            result(nil)

        case "setActiveColor":
            if let args = call.arguments as? [String: Any],
               let argb = args["color"] as? Int {
                sliderControl.minimumTrackTintColor = UIColor(argb: argb)
            }
            result(nil)

        case "setThumbColor":
            if let args = call.arguments as? [String: Any],
               let argb = args["color"] as? Int {
                sliderControl.thumbTintColor = UIColor(argb: argb)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
