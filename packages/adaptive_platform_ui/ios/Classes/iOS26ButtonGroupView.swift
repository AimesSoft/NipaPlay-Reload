import Flutter
import UIKit

class iOS26ButtonGroupViewFactory: NSObject, FlutterPlatformViewFactory {
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
        iOS26ButtonGroupView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Uses UIKit's toolbar grouping so iOS 26 owns the shared Liquid Glass
/// background instead of approximating it with a segmented control.
class iOS26ButtonGroupView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let toolbar = UIToolbar()
    private let channel: FlutterMethodChannel
    private var buttonGroup: UIBarButtonItemGroup?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        containerView = UIView(frame: frame)
        let params = args as? [String: Any]
        let id = params?["id"] as? Int ?? Int(viewId)
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_button_group_\(id)",
            binaryMessenger: messenger
        )
        super.init()

        configureToolbar()
        setItems(params?["items"] as? [[String: Any]] ?? [])

        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "setItems",
                  let items = call.arguments as? [[String: Any]] else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.setItems(items)
            result(nil)
        }
    }

    func view() -> UIView {
        containerView
    }

    private func configureToolbar() {
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        toolbar.isTranslucent = true
        toolbar.clipsToBounds = false

        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance

        containerView.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private func setItems(_ items: [[String: Any]]) {
        let barItems = items.enumerated().map { index, item in
            let symbol = item["sfSymbol"] as? String ?? "circle"
            let image = UIImage(systemName: symbol)
            let barItem = UIBarButtonItem(
                image: image,
                style: .plain,
                target: self,
                action: #selector(buttonPressed(_:))
            )
            barItem.tag = index
            barItem.isEnabled = item["enabled"] as? Bool ?? true
            barItem.accessibilityLabel = item["label"] as? String
            if #available(iOS 26.0, *) {
                barItem.sharesBackground = true
                barItem.hidesSharedBackground = false
            }
            return barItem
        }

        if barItems.isEmpty {
            buttonGroup = nil
            toolbar.setItems([], animated: false)
            return
        }

        if #available(iOS 16.0, *) {
            buttonGroup = UIBarButtonItemGroup.fixedGroup(
                representativeItem: nil,
                items: barItems
            )
        } else {
            buttonGroup = nil
        }
        toolbar.setItems(barItems, animated: false)
    }

    @objc private func buttonPressed(_ sender: UIBarButtonItem) {
        channel.invokeMethod("pressed", arguments: ["index": sender.tag])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
