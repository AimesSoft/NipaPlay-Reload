import Flutter
import UIKit

/// Platform view for iOS 26 popup menu button
class iOS26PopupMenuButtonView: NSObject, FlutterPlatformView {
    private let channel: FlutterMethodChannel
    private let container: UIView
    private let button: UIButton
    private var currentButtonStyle: String = "plain"
    private var isRoundButton: Bool = false
    private var labels: [String] = []
    private var symbols: [String] = []
    private var dividers: [Bool] = []
    private var enabled: [Bool] = []

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_popup_menu_button_\(viewId)", binaryMessenger: messenger)
        self.container = UIView(frame: frame)
        self.button = UIButton(type: .system)

        var title: String? = nil
        var iconName: String? = nil
        var makeRound: Bool = false
        var isDark: Bool = false
        var tint: UIColor? = nil
        var buttonStyle: String = "plain"
        var labels: [String] = []
        var symbols: [String] = []
        var dividers: [NSNumber] = []
        var enabled: [NSNumber] = []
        var isCustomWidget: Bool = false

        if let dict = args as? [String: Any] {
            if let t = dict["buttonTitle"] as? String { title = t }
            if let s = dict["buttonIconName"] as? String { iconName = s }
            if let r = dict["round"] as? NSNumber { makeRound = r.boolValue }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let tintArgb = dict["tint"] as? NSNumber { tint = UIColor(argb: tintArgb.intValue) }
            if let bs = dict["buttonStyle"] as? String { buttonStyle = bs }
            if let cw = dict["customWidget"] as? NSNumber { isCustomWidget = cw.boolValue }
            labels = (dict["labels"] as? [String]) ?? []
            symbols = (dict["sfSymbols"] as? [String]) ?? []
            dividers = (dict["isDivider"] as? [NSNumber]) ?? []
            enabled = (dict["enabled"] as? [NSNumber]) ?? []
        }

        super.init()

        container.backgroundColor = .clear
        if #available(iOS 13.0, *) { container.overrideUserInterfaceStyle = isDark ? .dark : .light }

        button.translatesAutoresizingMaskIntoConstraints = false
        if let t = tint { button.tintColor = t }
        else if #available(iOS 13.0, *) { button.tintColor = .label }

        // Add button and pin to container
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Store menu items
        self.labels = labels
        self.symbols = symbols
        self.dividers = dividers.map { $0.boolValue }
        self.enabled = enabled.map { $0.boolValue }

        self.isRoundButton = makeRound
        currentButtonStyle = buttonStyle

        // Set button content (hide if custom widget is used)
        if !isCustomWidget {
            applyButtonStyle(buttonStyle: buttonStyle, round: makeRound)
            setButtonContent(title: title, icon: iconName)
        } else {
            // Make button fully transparent but functional
            button.backgroundColor = .clear
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.plain()
                config.background.backgroundColor = .clear
                config.baseBackgroundColor = .clear
                config.baseForegroundColor = .clear
                button.configuration = config
            }
        }

        // Build menu
        rebuildMenu()

        if #available(iOS 14.0, *) {
            button.showsMenuAsPrimaryAction = true
        } else {
            button.addTarget(self, action: #selector(onButtonPressedLegacy(_:)), for: .touchUpInside)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            switch call.method {
            case "getIntrinsicSize":
                let size = self.button.intrinsicContentSize
                result(["width": Double(size.width), "height": Double(size.height)])
            case "setBrightness":
                if let args = call.arguments as? [String: Any], let isDark = (args["isDark"] as? NSNumber)?.boolValue {
                    if #available(iOS 13.0, *) { self.container.overrideUserInterfaceStyle = isDark ? .dark : .light }
                    result(nil)
                } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
            case "setStyle":
                if let args = call.arguments as? [String: Any] {
                    if let n = args["tint"] as? NSNumber {
                        self.button.tintColor = UIColor(argb: n.intValue)
                        self.applyButtonStyle(buttonStyle: self.currentButtonStyle, round: self.isRoundButton)
                    }
                    if let bs = args["buttonStyle"] as? String {
                        self.currentButtonStyle = bs
                        self.applyButtonStyle(buttonStyle: bs, round: self.isRoundButton)
                    }
                    result(nil)
                } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
            case "updateMenuItems":
                if let args = call.arguments as? [String: Any] {
                    self.labels = (args["labels"] as? [String]) ?? []
                    self.symbols = (args["sfSymbols"] as? [String]) ?? []
                    self.dividers = ((args["isDivider"] as? [NSNumber]) ?? []).map { $0.boolValue }
                    self.enabled = ((args["enabled"] as? [NSNumber]) ?? []).map { $0.boolValue }
                    self.rebuildMenu()
                    result(nil)
                } else { result(FlutterError(code: "bad_args", message: "Missing menu items", details: nil)) }
            case "updateButtonContent":
                if let args = call.arguments as? [String: Any] {
                    let title = args["buttonTitle"] as? String
                    let iconName = args["buttonIconName"] as? String
                    self.setButtonContent(title: title, icon: iconName)
                    result(nil)
                } else { result(FlutterError(code: "bad_args", message: "Missing button content", details: nil)) }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    private func rebuildMenu() {
        // iOS 14+ native menu
        if #available(iOS 14.0, *) {
            var groups: [[UIMenuElement]] = []
            var current: [UIMenuElement] = []
            let count = max(labels.count, max(symbols.count, dividers.count))

            let flushGroup: () -> Void = {
                if !current.isEmpty { groups.append(current); current = [] }
            }

            // Count only selectable items for indexing
            var selectableIndex = 0

            for i in 0..<count {
                let isDiv = i < dividers.count ? dividers[i] : false
                if isDiv { flushGroup(); continue }

                let title = i < labels.count ? labels[i] : ""
                var image: UIImage? = nil
                if i < symbols.count, !symbols[i].isEmpty {
                    image = UIImage(systemName: symbols[i])
                }

                let isEnabled = i < enabled.count ? enabled[i] : true
                let currentSelectableIndex = selectableIndex
                selectableIndex += 1

                let action = UIAction(title: title, image: image, attributes: isEnabled ? [] : [.disabled]) { [weak self] _ in
                    self?.channel.invokeMethod("itemSelected", arguments: ["index": currentSelectableIndex])
                }
                current.append(action)
            }
            flushGroup()

            let children: [UIMenuElement] = groups.map { group in
                UIMenu(title: "", options: .displayInline, children: group)
            }
            button.menu = UIMenu(title: "", children: children)
        }
    }

    @objc private func onButtonPressedLegacy(_ sender: UIButton) {
        // iOS 13 fallback: use action sheet
        let ac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        var selectableIndex = 0
        let count = max(labels.count, max(symbols.count, dividers.count))

        for i in 0..<count {
            if i < dividers.count, dividers[i] {
                let fake = UIAlertAction(title: "—", style: .default, handler: nil)
                fake.isEnabled = false
                ac.addAction(fake)
                continue
            }

            let title = i < labels.count ? labels[i] : ""
            let currentSelectableIndex = selectableIndex
            selectableIndex += 1

            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.channel.invokeMethod("itemSelected", arguments: ["index": currentSelectableIndex])
            }

            if i < enabled.count { action.isEnabled = enabled[i] }

            // Optional: set image where supported
            if i < symbols.count, !symbols[i].isEmpty, let img = UIImage(systemName: symbols[i]) {
                if #available(iOS 13.0, *) { action.setValue(img, forKey: "image") }
            }
            ac.addAction(action)
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let pop = ac.popoverPresentationController {
            pop.sourceView = sender
            pop.sourceRect = sender.bounds
        }
        parentViewController(for: container)?.present(ac, animated: true, completion: nil)
    }

    private func parentViewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    private func applyButtonStyle(buttonStyle: String, round: Bool) {
        if #available(iOS 15.0, *) {
            let currentTitle = button.configuration?.title
            let currentImage = button.configuration?.image
            var config: UIButton.Configuration

            switch buttonStyle {
            case "plain": config = .plain()
            case "gray": config = .gray()
            case "tinted": config = .tinted()
            case "bordered": config = .bordered()
            case "borderedProminent": config = .borderedProminent()
            case "filled": config = .filled()
            case "glass":
                if #available(iOS 26.0, *) { config = .glass() } else { config = .tinted() }
            case "prominentGlass":
                if #available(iOS 26.0, *) { config = .prominentGlass() } else { config = .tinted() }
            default:
                config = .plain()
            }

            config.cornerStyle = round ? .capsule : .dynamic

            if let tint = button.tintColor {
                switch buttonStyle {
                case "filled", "borderedProminent", "prominentGlass":
                    config.baseBackgroundColor = tint
                case "tinted", "bordered", "gray", "plain", "glass":
                    config.baseForegroundColor = tint
                default:
                    break
                }
            }

            // Restore content after style swap
            config.title = currentTitle
            config.image = currentImage
            button.configuration = config
        } else {
            button.layer.cornerRadius = round ? 999 : 8
            button.clipsToBounds = true
            if buttonStyle == "glass" {
                button.backgroundColor = UIColor(white: 1.0, alpha: 0.22)
                button.layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor
                button.layer.borderWidth = 1.0 / UIScreen.main.scale
            } else {
                button.backgroundColor = .clear
                button.layer.borderWidth = 0
            }
        }
    }

    private func setButtonContent(title: String?, icon: String?) {
        if #available(iOS 15.0, *) {
            var cfg = button.configuration ?? .plain()
            cfg.title = title
            if let iconName = icon, let image = UIImage(systemName: iconName) {
                cfg.image = image
            }
            button.configuration = cfg
        } else {
            button.setTitle(title, for: .normal)
            if let iconName = icon, let image = UIImage(systemName: iconName) {
                button.setImage(image, for: .normal)
            }
        }
    }
}

/// Factory for creating iOS26PopupMenuButtonView instances
class iOS26PopupMenuButtonViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return iOS26PopupMenuButtonView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
