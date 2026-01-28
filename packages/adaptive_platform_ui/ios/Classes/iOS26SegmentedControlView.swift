import Flutter
import UIKit

/// Factory for creating iOS 26 native segmented control platform views
class iOS26SegmentedControlViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26SegmentedControlView(
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

/// Native iOS 26 segmented control implementation
class iOS26SegmentedControlView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var segmentedControl: UISegmentedControl!
    private var channel: FlutterMethodChannel
    private var controlId: Int
    private var isDark: Bool = false

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _view = UIView(frame: frame)

        if let config = args as? [String: Any] {
            controlId = config["id"] as? Int ?? 0
            isDark = config["isDark"] as? Bool ?? false
        } else {
            controlId = 0
        }

        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_segmented_control_\(controlId)",
            binaryMessenger: messenger
        )

        super.init()

        createNativeSegmentedControl(with: args)

        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _view
    }

    private func createNativeSegmentedControl(with args: Any?) {
        segmentedControl = UISegmentedControl()
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.isUserInteractionEnabled = true
        _view.isUserInteractionEnabled = true

        if let config = args as? [String: Any] {
            // Check for SF symbols first
            if let sfSymbols = config["sfSymbols"] as? [String], !sfSymbols.isEmpty {
                // Use SF symbols for segments
                for (index, symbolName) in sfSymbols.enumerated() {
                    if let image = UIImage(systemName: symbolName) {
                        segmentedControl.insertSegment(with: image, at: index, animated: false)
                    } else {
                        // Fallback if symbol not found
                        print("⚠️ SF Symbol not found: \(symbolName)")
                    }
                }

                // Apply icon size if provided
                if let iconSizeNumber = config["iconSize"] as? NSNumber {
                    let iconSize = CGFloat(iconSizeNumber.doubleValue)
                    let configuration = UIImage.SymbolConfiguration(pointSize: iconSize)
                    for i in 0..<segmentedControl.numberOfSegments {
                        if let image = segmentedControl.imageForSegment(at: i) {
                            segmentedControl.setImage(image.withConfiguration(configuration), forSegmentAt: i)
                        }
                    }
                }

                // Apply icon color if provided
                if let iconColorValue = config["iconColor"] as? Int {
                    let iconColor = colorFromARGB(iconColorValue)
                    segmentedControl.setTitleTextAttributes([.foregroundColor: iconColor], for: .normal)
                }
            }
            // Otherwise use labels
            else if let labels = config["labels"] as? [String] {
                for (index, label) in labels.enumerated() {
                    segmentedControl.insertSegment(withTitle: label, at: index, animated: false)
                }
            }

            // Set enabled state
            if let enabled = config["enabled"] as? Bool {
                segmentedControl.isEnabled = enabled
            }

            // Set tint color if provided
            if let tintColorValue = config["tintColor"] as? Int {
                let tintColor = colorFromARGB(tintColorValue)
                segmentedControl.selectedSegmentTintColor = tintColor
            }

            // Set selected index
            if let selectedIndex = config["selectedIndex"] as? Int, selectedIndex >= 0 {
                segmentedControl.selectedSegmentIndex = selectedIndex
            }

            // Apply dark mode
            if let isDark = config["isDark"] as? Bool {
                if #available(iOS 13.0, *) {
                    _view.overrideUserInterfaceStyle = isDark ? .dark : .light
                }
            }
        }

        _view.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: _view.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: _view.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: _view.topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: _view.bottomAnchor),
        ])

        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }

    private func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    @objc private func segmentChanged() {
        channel.invokeMethod("valueChanged", arguments: ["index": segmentedControl.selectedSegmentIndex])

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSelectedIndex":
            if let args = call.arguments as? [String: Any],
               let index = args["index"] as? Int {
                if index >= 0 && index < segmentedControl.numberOfSegments {
                    segmentedControl.selectedSegmentIndex = index
                } else if index == -1 {
                    segmentedControl.selectedSegmentIndex = UISegmentedControl.noSegment
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
