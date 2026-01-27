import Flutter
import UIKit

/// Manager for iOS 26 adaptive scaffold with native tab bar
@available(iOS 13.0, *)
class iOS26ScaffoldManager: NSObject {
    private let channel: FlutterMethodChannel
    private weak var viewController: UIViewController?
    private var tabBarController: UITabBarController?

    init(channel: FlutterMethodChannel, viewController: UIViewController?) {
        self.channel = channel
        self.viewController = viewController
        super.init()

        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setupTabBar":
            setupTabBar(call, result: result)
        case "setSelectedIndex":
            setSelectedIndex(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setupTabBar(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let tabsData = args["tabs"] as? [[String: Any]],
              let selectedIndex = args["selectedIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        // Get or create tab bar controller
        if tabBarController == nil {
            tabBarController = UITabBarController()

            // Apply iOS 26 styling if available
            if #available(iOS 26.0, *) {
                // Configure tab bar appearance for iOS 26 Liquid Glass
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()

                // Apply Liquid Glass effect
                if let tabBar = tabBarController?.tabBar {
                    tabBar.standardAppearance = appearance
                    tabBar.scrollEdgeAppearance = appearance
                }
            }
        }

        // Create tab bar items
        var items: [UITabBarItem] = []
        for (index, tabData) in tabsData.enumerated() {
            let label = tabData["label"] as? String ?? "Tab \(index + 1)"
            let iconName = tabData["icon"] as? String ?? "circle"
            let selectedIconName = tabData["selectedIcon"] as? String ?? iconName

            let item = UITabBarItem(
                title: label,
                image: UIImage(systemName: iconName),
                selectedImage: UIImage(systemName: selectedIconName)
            )

            items.append(item)
        }

        // Update tab bar items
        tabBarController?.tabBar.items = items
        tabBarController?.selectedIndex = selectedIndex

        // Set up tab bar item selection callback
        setupTabBarDelegate()

        result(nil)
    }

    private func setupTabBarDelegate() {
        // Create a custom delegate to handle tab selection
        tabBarController?.delegate = self
    }

    private func setSelectedIndex(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let index = call.arguments as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid index", details: nil))
            return
        }

        tabBarController?.selectedIndex = index
        result(nil)
    }
}

// MARK: - UITabBarControllerDelegate
@available(iOS 13.0, *)
extension iOS26ScaffoldManager: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = tabBarController.selectedIndex
        channel.invokeMethod("onTabSelected", arguments: index)
    }
}
