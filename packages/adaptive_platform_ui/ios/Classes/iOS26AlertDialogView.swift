import Flutter
import UIKit

/// A UIAlertController that manages its own background dimming
class TintAdjustingAlertController: UIAlertController {
    private var backgroundDimmingView: UIView?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Disable automatic tint adjustment
        if let presentingVC = presentingViewController {
            presentingVC.view.tintAdjustmentMode = .normal
            if let navController = presentingVC as? UINavigationController {
                navController.navigationBar.tintAdjustmentMode = .normal
                navController.viewControllers.forEach { $0.view.tintAdjustmentMode = .normal }
            }
        }

        // Add custom dimming view
        addCustomDimmingView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remove custom dimming and restore normal tint
        removeCustomDimmingView()

        // Force all views to normal tint mode
        if let presentingVC = presentingViewController {
            presentingVC.view.tintAdjustmentMode = .automatic
            if let navController = presentingVC as? UINavigationController {
                navController.navigationBar.tintAdjustmentMode = .automatic
                navController.viewControllers.forEach { $0.view.tintAdjustmentMode = .automatic }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeCustomDimmingView()
    }

    private func addCustomDimmingView() {
        guard let presentingVC = presentingViewController,
              backgroundDimmingView == nil else { return }

        let dimmingView = UIView()
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimmingView.frame = presentingVC.view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.alpha = 0

        presentingVC.view.insertSubview(dimmingView, belowSubview: view)
        backgroundDimmingView = dimmingView

        UIView.animate(withDuration: 0.3) {
            dimmingView.alpha = 1
        }
    }

    private func removeCustomDimmingView() {
        guard let dimmingView = backgroundDimmingView else { return }

        UIView.animate(withDuration: 0.3, animations: {
            dimmingView.alpha = 0
        }) { _ in
            dimmingView.removeFromSuperview()
        }

        backgroundDimmingView = nil
    }
}

/// Platform view for iOS 26 alert dialog
class iOS26AlertDialogView: NSObject, FlutterPlatformView {
    private let channel: FlutterMethodChannel
    private let container: UIView
    private var alertController: TintAdjustingAlertController?
    private var alertStyle: String = "glass"

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_alert_dialog_\(viewId)", binaryMessenger: messenger)
        self.container = UIView(frame: frame)

        var title: String = ""
        var message: String? = nil
        var actionTitles: [String] = []
        var actionStyles: [String] = []
        var actionEnabled: [Bool] = []
        var iconName: String? = nil
        var iconSize: CGFloat? = nil
        var iconColor: UIColor? = nil
        var oneTimeCode: String? = nil
        var isDark: Bool = false
        var tint: UIColor? = nil
        var alertStyleParam: String = "glass"
        var textFieldPlaceholder: String? = nil
        var textFieldInitialValue: String? = nil
        var textFieldObscureText: Bool = false
        var textFieldMaxLength: Int? = nil
        var textFieldKeyboardType: String? = nil

        if let dict = args as? [String: Any] {
            if let t = dict["title"] as? String { title = t }
            if let m = dict["message"] as? String { message = m }
            if let at = dict["actionTitles"] as? [String] { actionTitles = at }
            if let ast = dict["actionStyles"] as? [String] { actionStyles = ast }
            if let ae = dict["actionEnabled"] as? [Bool] { actionEnabled = ae }
            if let iconNameValue = dict["iconName"] as? String { iconName = iconNameValue }
            if let iconSizeValue = dict["iconSize"] as? NSNumber { iconSize = CGFloat(truncating: iconSizeValue) }
            if let ic = dict["iconColor"] as? NSNumber { iconColor = UIColor(argb: ic.intValue) }
            if let otc = dict["oneTimeCode"] as? String { oneTimeCode = otc }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let t = dict["tint"] as? NSNumber { tint = UIColor(argb: t.intValue) }
            if let alertStyleValue = dict["alertStyle"] as? String { alertStyleParam = alertStyleValue }
            if let tfp = dict["textFieldPlaceholder"] as? String { textFieldPlaceholder = tfp }
            if let tfiv = dict["textFieldInitialValue"] as? String { textFieldInitialValue = tfiv }
            if let tfot = dict["textFieldObscureText"] as? Bool { textFieldObscureText = tfot }
            if let tfml = dict["textFieldMaxLength"] as? NSNumber { textFieldMaxLength = tfml.intValue }
            if let tfkt = dict["textFieldKeyboardType"] as? String { textFieldKeyboardType = tfkt }
        }

        self.alertStyle = alertStyleParam

        super.init()

        setupAlert(
            title: title,
            message: message,
            actionTitles: actionTitles,
            actionStyles: actionStyles,
            actionEnabled: actionEnabled,
            iconName: iconName,
            iconSize: iconSize,
            iconColor: iconColor,
            oneTimeCode: oneTimeCode,
            isDark: isDark,
            tint: tint,
            textFieldPlaceholder: textFieldPlaceholder,
            textFieldInitialValue: textFieldInitialValue,
            textFieldObscureText: textFieldObscureText,
            textFieldMaxLength: textFieldMaxLength,
            textFieldKeyboardType: textFieldKeyboardType
        )

        self.channel.setMethodCallHandler(onMethodCall)
    }

    func view() -> UIView {
        return container
    }

    private func setupAlert(
        title: String,
        message: String?,
        actionTitles: [String],
        actionStyles: [String],
        actionEnabled: [Bool],
        iconName: String?,
        iconSize: CGFloat?,
        iconColor: UIColor?,
        oneTimeCode: String?,
        isDark: Bool,
        tint: UIColor?,
        textFieldPlaceholder: String?,
        textFieldInitialValue: String?,
        textFieldObscureText: Bool,
        textFieldMaxLength: Int?,
        textFieldKeyboardType: String?
    ) {
        // Create TintAdjustingAlertController
        alertController = TintAdjustingAlertController(title: title, message: message, preferredStyle: .alert)

        guard let alert = alertController else { return }

        // Apply liquid glass styling for iOS 15+
        if #available(iOS 15.0, *) {
            // Configure with iOS corner radius and continuous curve
            alert.view.layer.cornerRadius = 28.0
            alert.view.layer.cornerCurve = .continuous

            // Add subtle shadow for depth
            alert.view.layer.shadowOpacity = 0.1
            alert.view.layer.shadowOffset = CGSize(width: 0, height: 2)
            alert.view.layer.shadowRadius = 10
            alert.view.layer.masksToBounds = false

            // Add glass effect with proper iOS materials
            let blurEffect = UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.frame = alert.view.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.layer.cornerRadius = 28.0
            blurView.layer.cornerCurve = .continuous
            blurView.clipsToBounds = true

            // Insert blur view behind content
            alert.view.insertSubview(blurView, at: 0)

            // Make alert background transparent to show blur
            alert.view.backgroundColor = UIColor.clear

            // Apply tint if available
            if let tintColor = tint {
                alert.view.tintColor = tintColor
            }
        }

        // Custom content with OTP code
        if let otpCode = oneTimeCode {
            let contentViewController = UIViewController()
            var constraints: [NSLayoutConstraint] = []
            var currentTopAnchor: NSLayoutYAxisAnchor = contentViewController.view.topAnchor
            var currentTopConstant: CGFloat = 16

            // 1. Icon (if provided)
            if let iconName = iconName, let image = UIImage(systemName: iconName) {
                var finalImage = image

                // Apply icon styling
                if let size = iconSize {
                    let config = UIImage.SymbolConfiguration(pointSize: size)
                    finalImage = finalImage.withConfiguration(config)
                }
                if let color = iconColor {
                    finalImage = finalImage.withTintColor(color, renderingMode: .alwaysOriginal)
                }

                let imageView = UIImageView(image: finalImage)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.contentMode = .scaleAspectFit
                contentViewController.view.addSubview(imageView)

                constraints.append(contentsOf: [
                    imageView.topAnchor.constraint(equalTo: currentTopAnchor, constant: currentTopConstant),
                    imageView.centerXAnchor.constraint(equalTo: contentViewController.view.centerXAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: iconSize ?? 32),
                    imageView.heightAnchor.constraint(equalToConstant: iconSize ?? 32)
                ])

                currentTopAnchor = imageView.bottomAnchor
                currentTopConstant = 12
            }

            // 2. Title
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            contentViewController.view.addSubview(titleLabel)

            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: currentTopAnchor, constant: currentTopConstant),
                titleLabel.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor, constant: 20),
                titleLabel.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor, constant: -20)
            ])

            currentTopAnchor = titleLabel.bottomAnchor
            currentTopConstant = 8

            // 3. Description (if provided)
            if let messageText = message, !messageText.isEmpty {
                let messageLabel = UILabel()
                messageLabel.text = messageText
                messageLabel.font = UIFont.systemFont(ofSize: 13)
                messageLabel.textColor = .secondaryLabel
                messageLabel.textAlignment = .center
                messageLabel.numberOfLines = 0
                messageLabel.translatesAutoresizingMaskIntoConstraints = false
                contentViewController.view.addSubview(messageLabel)

                constraints.append(contentsOf: [
                    messageLabel.topAnchor.constraint(equalTo: currentTopAnchor, constant: currentTopConstant),
                    messageLabel.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor, constant: 20),
                    messageLabel.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor, constant: -20)
                ])

                currentTopAnchor = messageLabel.bottomAnchor
                currentTopConstant = 12
            }

            // 4. OTP Code
            let otpLabel = UILabel()
            otpLabel.text = otpCode
            otpLabel.font = UIFont.monospacedSystemFont(ofSize: 28, weight: .bold)
            otpLabel.textColor = .label
            otpLabel.textAlignment = .center
            otpLabel.layer.cornerRadius = 8
            otpLabel.layer.masksToBounds = true
            otpLabel.translatesAutoresizingMaskIntoConstraints = false
            contentViewController.view.addSubview(otpLabel)

            constraints.append(contentsOf: [
                otpLabel.topAnchor.constraint(equalTo: currentTopAnchor, constant: currentTopConstant),
                otpLabel.centerXAnchor.constraint(equalTo: contentViewController.view.centerXAnchor),
                otpLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
                otpLabel.heightAnchor.constraint(equalToConstant: 44),
                otpLabel.bottomAnchor.constraint(equalTo: contentViewController.view.bottomAnchor, constant: -8),
                contentViewController.view.widthAnchor.constraint(equalToConstant: 280),
                contentViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
            ])

            NSLayoutConstraint.activate(constraints)

            // Clear alert's title and message
            alert.title = nil
            alert.message = nil
            alert.setValue(contentViewController, forKey: "contentViewController")

        } else if let iconName = iconName, let image = UIImage(systemName: iconName) {
            // Icon without OTP
            var finalImage = image

            if let size = iconSize {
                let config = UIImage.SymbolConfiguration(pointSize: size)
                finalImage = finalImage.withConfiguration(config)
            }
            if let color = iconColor {
                finalImage = finalImage.withTintColor(color, renderingMode: .alwaysOriginal)
            }

            let contentViewController = UIViewController()
            let imageView = UIImageView(image: finalImage)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            contentViewController.view.addSubview(imageView)

            if let messageText = message, !messageText.isEmpty {
                let messageLabel = UILabel()
                messageLabel.text = messageText
                messageLabel.numberOfLines = 0
                messageLabel.textAlignment = .center
                messageLabel.font = UIFont.systemFont(ofSize: 13)
                messageLabel.textColor = .secondaryLabel
                messageLabel.translatesAutoresizingMaskIntoConstraints = false
                contentViewController.view.addSubview(messageLabel)

                NSLayoutConstraint.activate([
                    imageView.topAnchor.constraint(equalTo: contentViewController.view.topAnchor, constant: 8),
                    imageView.centerXAnchor.constraint(equalTo: contentViewController.view.centerXAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: iconSize ?? 24),
                    imageView.heightAnchor.constraint(equalToConstant: iconSize ?? 24),

                    messageLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
                    messageLabel.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor, constant: 16),
                    messageLabel.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor, constant: -16),
                    messageLabel.bottomAnchor.constraint(equalTo: contentViewController.view.bottomAnchor, constant: -4),

                    contentViewController.view.widthAnchor.constraint(equalToConstant: 250),
                    contentViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
                ])

                alert.message = nil
            } else {
                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: contentViewController.view.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: contentViewController.view.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: iconSize ?? 24),
                    imageView.heightAnchor.constraint(equalToConstant: iconSize ?? 24),

                    contentViewController.view.widthAnchor.constraint(equalToConstant: 250),
                    contentViewController.view.heightAnchor.constraint(equalToConstant: 60)
                ])
            }

            alert.setValue(contentViewController, forKey: "contentViewController")
        }

        // Add text field if placeholder is provided
        if let placeholder = textFieldPlaceholder {
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.text = textFieldInitialValue
                textField.isSecureTextEntry = textFieldObscureText

                // Set keyboard type
                if let keyboardType = textFieldKeyboardType {
                    switch keyboardType {
                    case "emailAddress":
                        textField.keyboardType = .emailAddress
                    case "number":
                        textField.keyboardType = .numberPad
                    case "phone":
                        textField.keyboardType = .phonePad
                    case "url":
                        textField.keyboardType = .URL
                    default:
                        textField.keyboardType = .default
                    }
                }

                // Add max length if specified
                if let maxLength = textFieldMaxLength {
                    textField.addTarget(self, action: #selector(self.textFieldDidChange(_:)), for: .editingChanged)
                    textField.accessibilityValue = "\(maxLength)" // Store maxLength in accessibilityValue
                }
            }
        }

        // Add actions
        var primaryAction: UIAlertAction?
        var cancelAction: UIAlertAction?

        // Determine preferred action
        var preferredActionStyle: String?
        for (index, _) in actionTitles.enumerated() {
            let style = index < actionStyles.count ? actionStyles[index] : "defaultAction"

            if style == "primary" && preferredActionStyle == nil {
                preferredActionStyle = "primary"
            } else if style == "cancel" && preferredActionStyle != "primary" {
                preferredActionStyle = "cancel"
            }
        }

        for (index, actionTitle) in actionTitles.enumerated() {
            let style = index < actionStyles.count ? actionStyles[index] : "defaultAction"
            let enabled = index < actionEnabled.count ? actionEnabled[index] : true

            let isDarkMode: Bool
            if #available(iOS 13.0, *) {
                isDarkMode = alert.traitCollection.userInterfaceStyle == .dark
            } else {
                isDarkMode = false
            }

            let alertActionStyle: UIAlertAction.Style
            var textColor: UIColor?
            var textFont: UIFont?

            switch style {
            case "cancel":
                alertActionStyle = .default
                textColor = nil
            case "destructive":
                alertActionStyle = .destructive
                textColor = nil
            case "primary":
                alertActionStyle = .default
                textColor = nil  // Don't set color - let preferred action make it white
                textFont = .boldSystemFont(ofSize: 17)
            case "secondary":
                alertActionStyle = .default
                textColor = isDarkMode ? UIColor.secondaryLabel.withAlphaComponent(0.8) : .secondaryLabel
            case "success":
                alertActionStyle = .default
                textColor = isDarkMode ? UIColor.systemGreen.withAlphaComponent(0.9) : .systemGreen
            case "warning":
                alertActionStyle = .default
                textColor = isDarkMode ? UIColor.systemOrange.withAlphaComponent(0.9) : .systemOrange
            case "info":
                alertActionStyle = .default
                textColor = isDarkMode ? UIColor.systemBlue.withAlphaComponent(0.8) : .systemBlue
            case "disabled":
                alertActionStyle = .default
                textColor = isDarkMode ? UIColor.tertiaryLabel.withAlphaComponent(0.6) : .tertiaryLabel
            default:
                alertActionStyle = .default
            }

            let action = UIAlertAction(title: actionTitle, style: alertActionStyle) { [weak self] _ in
                guard let self = self, let alert = self.alertController else { return }

                // Get text field value if exists
                var textFieldValue: String? = nil
                if let textField = alert.textFields?.first {
                    textFieldValue = textField.text
                }

                var arguments: [String: Any] = ["index": index]
                if let value = textFieldValue {
                    arguments["textFieldValue"] = value
                }

                self.channel.invokeMethod("actionPressed", arguments: arguments)
            }

            // Apply custom colors (but not for primary, which will be white as preferred action)
            if let color = textColor, style != "destructive", style != "primary" {
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                    .font: textFont ?? UIFont.systemFont(ofSize: 17)
                ]
                let attributedTitle = NSAttributedString(string: actionTitle, attributes: attributes)

                if action.responds(to: Selector(("_setTitleTextColor:"))) {
                    action.setValue(color, forKey: "_titleTextColor")
                }

                if action.responds(to: Selector(("setAttributedTitle:"))) {
                    action.setValue(attributedTitle, forKey: "attributedTitle")
                }
            }

            // Apply bold font for primary action
            if style == "primary", let font = textFont {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font
                ]
                let attributedTitle = NSAttributedString(string: actionTitle, attributes: attributes)

                if action.responds(to: Selector(("setAttributedTitle:"))) {
                    action.setValue(attributedTitle, forKey: "attributedTitle")
                }
            }

            action.isEnabled = enabled && style != "disabled"
            alert.addAction(action)

            switch style {
            case "cancel":
                cancelAction = action
            case "primary":
                primaryAction = action
            default:
                break
            }
        }

        // Set preferred action
        if let action = primaryAction {
            alert.preferredAction = action
            alert.view.tintColor = UIColor.systemBlue
        } else if let action = cancelAction {
            alert.preferredAction = action
            alert.view.tintColor = UIColor.systemRed
        }

        // Present the alert
        DispatchQueue.main.async { [weak self] in
            if let topController = self?.topViewController() {
                topController.present(alert, animated: true)
            }
        }
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        // Enforce max length if stored in accessibilityValue
        if let maxLengthString = textField.accessibilityValue,
           let maxLength = Int(maxLengthString),
           let text = textField.text,
           text.count > maxLength {
            textField.text = String(text.prefix(maxLength))
        }
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }

        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }

    private func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setBrightness":
            if let args = call.arguments as? [String: Any],
               let isDark = args["isDark"] as? Bool {
                updateBrightness(isDark: isDark)
            }
            result(nil)

        case "setStyle":
            if let args = call.arguments as? [String: Any],
               let tint = args["tint"] as? NSNumber {
                updateStyle(tint: UIColor(argb: tint.intValue))
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func updateBrightness(isDark: Bool) {
        guard let alert = alertController else { return }

        if #available(iOS 15.0, *) {
            if alertStyle == "glass" {
                let blurEffect = UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)

                for subview in alert.view.subviews {
                    if let blurView = subview as? UIVisualEffectView {
                        blurView.effect = blurEffect
                        break
                    }
                }
            }
        }
    }

    private func updateStyle(tint: UIColor) {
        guard let alert = alertController else { return }
        alert.view.tintColor = tint
    }
}

/// Factory for creating iOS26AlertDialogView instances
class iOS26AlertDialogViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return iOS26AlertDialogView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
