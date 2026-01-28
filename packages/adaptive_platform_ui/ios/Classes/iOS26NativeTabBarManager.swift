import Flutter
import UIKit

/// Manager for iOS 26+ Native Tab Bar with Search Support
/// This class manages a native UITabBarController at the app level
/// and coordinates with Flutter for content display
@available(iOS 26.0, *)
class iOS26NativeTabBarManager: NSObject {

    static let shared = iOS26NativeTabBarManager()

    private var tabBarController: UITabBarController?
    private var flutterViewController: FlutterViewController?
    private var searchController: UISearchController?
    private var methodChannel: FlutterMethodChannel?

    private var tabConfigurations: [TabConfig] = []
    private var searchTabIndex: Int = -1
    private var isEnabled: Bool = false

    struct TabConfig {
        let title: String
        let sfSymbol: String?
        let isSearchTab: Bool
        let badgeCount: Int?
    }

    private override init() {
        super.init()
    }

    /// Setup native tab bar with Flutter
    func setup(messenger: FlutterBinaryMessenger) {
        // Setup method channel
        self.methodChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/native_tab_bar",
            binaryMessenger: messenger
        )

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    /// Find Flutter view controller
    private func getFlutterViewController() -> FlutterViewController? {
        if let flutterVC = flutterViewController {
            return flutterVC
        }

        // Try to find it from windows
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            if let flutterVC = window.rootViewController as? FlutterViewController {
                self.flutterViewController = flutterVC
                return flutterVC
            }
        }

        return nil
    }

    /// Enable native tab bar mode
    private func enableNativeTabBar(tabs: [TabConfig], selectedIndex: Int) {
        guard let flutterVC = getFlutterViewController() else {
            return
        }

        // Create tab bar controller if needed
        if tabBarController == nil {
            let tabBar = UITabBarController()
            tabBarController = tabBar

            // Setup iOS 26 appearance
            setupTabBarAppearance(tabBar)
        }

        guard let tabBar = tabBarController else { return }

        // Store configuration
        self.tabConfigurations = tabs
        self.searchTabIndex = tabs.firstIndex(where: { $0.isSearchTab }) ?? -1

        // Create view controllers for each tab
        var viewControllers: [UIViewController] = []

        for (index, config) in tabs.enumerated() {
            if config.isSearchTab {
                // Create search tab with navigation controller
                let searchVC = SearchTabViewController()
                searchVC.tabIndex = index
                searchVC.onTabSelected = { [weak self] idx in
                    self?.notifyTabSelected(idx)
                }

                let navController = UINavigationController(rootViewController: searchVC)

                // Setup search controller
                let search = UISearchController(searchResultsController: nil)
                search.searchResultsUpdater = self
                search.searchBar.delegate = self
                search.obscuresBackgroundDuringPresentation = false
                search.searchBar.placeholder = "Search"
                search.hidesNavigationBarDuringPresentation = false

                searchVC.navigationItem.searchController = search
                searchVC.navigationItem.hidesSearchBarWhenScrolling = false

                self.searchController = search

                // Setup tab bar item with search system item
                navController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: index)
                if !config.title.isEmpty {
                    navController.tabBarItem.title = config.title
                }

                viewControllers.append(navController)
            } else {
                // Regular tab - use Flutter view
                let tabVC = FlutterTabViewController()
                tabVC.tabIndex = index
                tabVC.onTabSelected = { [weak self] idx in
                    self?.notifyTabSelected(idx)
                }

                // Setup tab bar item
                var image: UIImage?
                if let symbol = config.sfSymbol {
                    image = UIImage(systemName: symbol)
                }
                tabVC.tabBarItem = UITabBarItem(
                    title: config.title,
                    image: image,
                    selectedImage: image
                )
                tabVC.tabBarItem.tag = index
                
                // Set badge value if provided
                if let count = config.badgeCount, count > 0 {
                    tabVC.tabBarItem.badgeValue = count > 99 ? "99+" : String(count)
                } else {
                    tabVC.tabBarItem.badgeValue = nil
                }

                viewControllers.append(tabVC)
            }
        }

        tabBar.viewControllers = viewControllers
        tabBar.selectedIndex = selectedIndex
        tabBar.delegate = self

        // Replace root view controller
        if let window = flutterVC.view.window {
            // Embed Flutter view in the first non-search tab
            if let firstTab = viewControllers.first(where: { !($0 is UINavigationController) }) as? FlutterTabViewController {
                firstTab.embedFlutterView(flutterVC.view)
            }

            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                window.rootViewController = tabBar
            }

            self.isEnabled = true
        }
    }

    /// Disable native tab bar and return to Flutter-only mode
    private func disableNativeTabBar() {
        guard let flutterVC = getFlutterViewController(),
              let window = flutterVC.view.window else {
            return
        }

        // Remove Flutter view from tab if embedded
        if let tabBar = tabBarController,
           let selectedVC = tabBar.selectedViewController as? FlutterTabViewController {
            selectedVC.removeFlutterView()
        }

        // Restore Flutter as root
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = flutterVC
        }

        self.isEnabled = false
        self.tabBarController = nil
    }

    private func setupTabBarAppearance(_ tabBar: UITabBarController) {
        let appearance = UITabBarAppearance()

        // iOS 26 Liquid Glass design
        appearance.configureWithDefaultBackground()

        // Enable blur for liquid glass effect
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        appearance.shadowColor = .clear

        tabBar.tabBar.standardAppearance = appearance
        tabBar.tabBar.scrollEdgeAppearance = appearance
    }

    private func notifyTabSelected(_ index: Int) {
        methodChannel?.invokeMethod("onTabSelected", arguments: ["index": index])

        // Move Flutter view to selected tab if not search tab
        if index != searchTabIndex,
           let flutterView = getFlutterViewController()?.view,
           let tabBar = tabBarController,
           let selectedVC = tabBar.selectedViewController as? FlutterTabViewController {
            selectedVC.embedFlutterView(flutterView)
        }
    }

    private func notifySearchQueryChanged(_ query: String) {
        methodChannel?.invokeMethod("onSearchQueryChanged", arguments: ["query": query])
    }

    private func notifySearchSubmitted(_ query: String) {
        methodChannel?.invokeMethod("onSearchSubmitted", arguments: ["query": query])
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableNativeTabBar":
            guard let args = call.arguments as? [String: Any],
                  let tabsData = args["tabs"] as? [[String: Any]] else {
                result(FlutterError(code: "invalid_args", message: "Invalid tabs data", details: nil))
                return
            }

            let tabs = tabsData.compactMap { data -> TabConfig? in
                guard let title = data["title"] as? String else { return nil }
                let symbol = data["sfSymbol"] as? String
                let isSearch = (data["isSearch"] as? Bool) ?? false
                let badgeCount = data["badgeCount"] as? Int
                return TabConfig(title: title, sfSymbol: symbol, isSearchTab: isSearch, badgeCount: badgeCount)
            }

            let selectedIndex = (args["selectedIndex"] as? Int) ?? 0
            enableNativeTabBar(tabs: tabs, selectedIndex: selectedIndex)
            result(nil)

        case "disableNativeTabBar":
            disableNativeTabBar()
            result(nil)

        case "setSelectedIndex":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "invalid_args", message: "Invalid index", details: nil))
                return
            }
            tabBarController?.selectedIndex = index
            result(nil)

        case "showSearch":
            searchController?.isActive = true
            result(nil)

        case "hideSearch":
            searchController?.isActive = false
            result(nil)

        case "isEnabled":
            result(isEnabled)

        case "setBadgeCounts":
            guard let args = call.arguments as? [String: Any],
                  let badgeCounts = args["badgeCounts"] as? [Int?] else {
                result(FlutterError(code: "invalid_args", message: "Invalid badge counts", details: nil))
                return
            }

            // Update badge counts for existing tab bar items
            if let tabBar = tabBarController, let viewControllers = tabBar.viewControllers {
                for (index, viewController) in viewControllers.enumerated() {
                    if index < badgeCounts.count {
                        let count = badgeCounts[index]
                        if let count = count, count > 0 {
                            viewController.tabBarItem.badgeValue = count > 99 ? "99+" : String(count)
                        } else {
                            viewController.tabBarItem.badgeValue = nil
                        }
                    }
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - UITabBarControllerDelegate

@available(iOS 26.0, *)
extension iOS26NativeTabBarManager: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = tabBarController.viewControllers?.firstIndex(of: viewController) ?? 0
        notifyTabSelected(index)
    }
}

// MARK: - UISearchResultsUpdating

@available(iOS 26.0, *)
extension iOS26NativeTabBarManager: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else { return }
        notifySearchQueryChanged(query)
    }
}

// MARK: - UISearchBarDelegate

@available(iOS 26.0, *)
extension iOS26NativeTabBarManager: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text else { return }
        notifySearchSubmitted(query)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        methodChannel?.invokeMethod("onSearchCancelled", arguments: nil)
    }
}

// MARK: - Tab View Controllers

private class FlutterTabViewController: UIViewController {
    var tabIndex: Int = 0
    var onTabSelected: ((Int) -> Void)?
    private var embeddedFlutterView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onTabSelected?(tabIndex)
    }

    func embedFlutterView(_ flutterView: UIView) {
        // Remove from previous parent
        flutterView.removeFromSuperview()

        // Add to this view controller
        flutterView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flutterView)
        NSLayoutConstraint.activate([
            flutterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            flutterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            flutterView.topAnchor.constraint(equalTo: view.topAnchor),
            flutterView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        embeddedFlutterView = flutterView
    }

    func removeFlutterView() {
        embeddedFlutterView?.removeFromSuperview()
        embeddedFlutterView = nil
    }
}

private class SearchTabViewController: UIViewController {
    var tabIndex: Int = 0
    var onTabSelected: ((Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Search"

        // Add placeholder content
        let label = UILabel()
        label.text = "Search results will appear here\n\nSearch functionality is controlled by Flutter"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onTabSelected?(tabIndex)
    }
}
