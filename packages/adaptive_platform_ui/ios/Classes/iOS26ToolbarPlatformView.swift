import UIKit
import Flutter

/// Factory for creating iOS 26 native UIToolbar platform views
class iOS26ToolbarFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26ToolbarPlatformView(
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

/// Native iOS 26 UIToolbar platform view
class iOS26ToolbarPlatformView: NSObject, FlutterPlatformView {
    private var _containerView: UIView
    private var _toolbar: UIToolbar
    private var _viewId: Int64
    private var _channel: FlutterMethodChannel

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _containerView = UIView(frame: frame)
        _toolbar = UIToolbar()
        _viewId = viewId
        _channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_toolbar_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        // Add toolbar to container
        _containerView.addSubview(_toolbar)

        // Setup constraints for toolbar with SafeArea
        _toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            _toolbar.topAnchor.constraint(equalTo: _containerView.safeAreaLayoutGuide.topAnchor),
            _toolbar.leadingAnchor.constraint(equalTo: _containerView.leadingAnchor),
            _toolbar.trailingAnchor.constraint(equalTo: _containerView.trailingAnchor),
            _toolbar.bottomAnchor.constraint(equalTo: _containerView.bottomAnchor)
        ])

        // iOS 26+ Liquid Glass appearance with blur effect
        if #available(iOS 13.0, *) {
            let appearance = UIToolbarAppearance()

            // Use transparent background with blur (Liquid Glass effect)
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)

            // Apply system material blur effect for iOS 26+
            if #available(iOS 26.0, *) {
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            } else {
                // Fallback for older iOS versions
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            }

            _toolbar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                _toolbar.scrollEdgeAppearance = appearance
                _toolbar.compactAppearance = appearance
            }
        }

        // Enable blur and translucency
        _toolbar.isTranslucent = true

        // Parse arguments
        if let params = args as? [String: Any] {
            configureToolbar(params)
        }

        // Setup method channel
        _channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _containerView
    }

    private func configureToolbar(_ params: [String: Any]) {
        var items: [UIBarButtonItem] = []

        let hasTitle = params["title"] as? String != nil && !(params["title"] as? String ?? "").isEmpty
        let hasActions = params["actions"] as? [[String: Any]] != nil && !(params["actions"] as? [[String: Any]] ?? []).isEmpty
        let hasLeading = params["leading"] != nil

        // Leading button (left side)
        if let leadingTitle = params["leading"] as? String {
            let leadingButton: UIBarButtonItem
            if leadingTitle.isEmpty {
                // Empty string = show back chevron icon
                leadingButton = UIBarButtonItem(
                    image: UIImage(systemName: "chevron.left"),
                    style: .plain,
                    target: self,
                    action: #selector(leadingTapped)
                )
            } else {
                // Show text
                leadingButton = UIBarButtonItem(
                    title: leadingTitle,
                    style: .plain,
                    target: self,
                    action: #selector(leadingTapped)
                )
            }
            items.append(leadingButton)
        }

        // Actions - process and split into left/right groups if flexible spacer exists
        if let actions = params["actions"] as? [[String: Any]], !actions.isEmpty {
            var leftActions: [UIBarButtonItem] = []
            var rightActions: [UIBarButtonItem] = []
            var foundFlexibleSpacer = false

            for (index, action) in actions.enumerated() {
                var actionButton: UIBarButtonItem?

                if let actionTitle = action["title"] as? String {
                    actionButton = UIBarButtonItem(
                        title: actionTitle,
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                    actionButton?.tag = index
                } else if let actionIcon = action["icon"] as? String {
                    actionButton = UIBarButtonItem(
                        image: UIImage(systemName: actionIcon),
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                    actionButton?.tag = index
                }

                if let btn = actionButton {
                    if foundFlexibleSpacer {
                        rightActions.append(btn)
                    } else {
                        leftActions.append(btn)
                    }
                }

                // Check for spacer after this action
                if let spacerAfter = action["spacerAfter"] as? Int {
                    if spacerAfter == 1 { // Fixed space
                        if #available(iOS 16.0, *) {
                            if foundFlexibleSpacer {
                                rightActions.append(.fixedSpace(12))
                            } else {
                                leftActions.append(.fixedSpace(12))
                            }
                        }
                    } else if spacerAfter == 2 { // Flexible space - marks split point
                        foundFlexibleSpacer = true
                    }
                }
            }

            // If we found a flexible spacer, split actions into left/right groups
            if foundFlexibleSpacer {
                // Add left actions
                items.append(contentsOf: leftActions)

                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

                // Add title in center if exists
                if hasTitle {
                    if let title = params["title"] as? String, !title.isEmpty {
                        let titleLabel = UILabel()
                        titleLabel.text = title
                        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                        titleLabel.textAlignment = .center

                        let titleSize = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])
                        titleLabel.frame = CGRect(x: 0, y: 0, width: max(titleSize.width, 200), height: 44)

                        let titleItem = UIBarButtonItem(customView: titleLabel)
                        items.append(titleItem)
                    }

                    items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
                }

                // Add right actions
                items.append(contentsOf: rightActions)
            } else {
                // No flexible spacer - standard layout: Title on left, actions on right
                // Add spacing after leading button if it exists
                if hasLeading && (hasTitle || !leftActions.isEmpty) {
                    if #available(iOS 16.0, *) {
                        items.append(.fixedSpace(8))
                    }
                }

                if hasTitle {
                    if let title = params["title"] as? String, !title.isEmpty {
                        let titleLabel = UILabel()
                        titleLabel.text = title
                        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                        titleLabel.textAlignment = .left
                        titleLabel.sizeToFit()

                        let titleItem = UIBarButtonItem(customView: titleLabel)
                        items.append(titleItem)
                    }

                    items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
                }

                // Add all actions to the right
                items.append(contentsOf: leftActions)
            }
        } else {
            // No actions - just add title if exists
            if hasTitle {
                // Add spacing after leading button if it exists
                if hasLeading {
                    if #available(iOS 16.0, *) {
                        items.append(.fixedSpace(8))
                    }
                }

                if let title = params["title"] as? String, !title.isEmpty {
                    let titleLabel = UILabel()
                    titleLabel.text = title
                    titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                    titleLabel.textAlignment = .left
                    titleLabel.sizeToFit()

                    let titleItem = UIBarButtonItem(customView: titleLabel)
                    items.append(titleItem)
                }

                // Add flexible space to push everything to the left
                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }
        }

        _toolbar.items = items
    }

    @objc private func leadingTapped() {
        _channel.invokeMethod("onLeadingTapped", arguments: nil)
    }

    @objc private func actionTapped(_ sender: UIBarButtonItem) {
        // Use the tag to get the action index
        let actionIndex = sender.tag
        _channel.invokeMethod("onActionTapped", arguments: ["index": actionIndex])
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
}
