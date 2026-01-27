import Flutter
import UIKit

/// iOS 26+ Native Tab Bar Controller with Search Tab Support
/// This implementation uses UITabBarController to enable native search bar transformation
@available(iOS 26.0, *)
class iOS26SearchTabBarController: UITabBarController, UISearchResultsUpdating, UISearchBarDelegate {

    private let channel: FlutterMethodChannel
    private let flutterEngine: FlutterEngine?
    private var searchController: UISearchController?
    private var searchTabIndex: Int = -1
    private var tabConfigurations: [TabConfiguration] = []

    struct TabConfiguration {
        let title: String?
        let sfSymbol: String?
        let isSearch: Bool
        let index: Int
    }

    init(viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_search_tab_bar_\(viewId)",
            binaryMessenger: messenger
        )
        self.flutterEngine = nil

        super.init(nibName: nil, bundle: nil)

        // Parse configuration
        if let args = args {
            setupFromArgs(args)
        }

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup tab bar appearance for iOS 26 Liquid Glass
        setupTabBarAppearance()

        // Create view controllers for each tab
        setupViewControllers()

        // Setup search controller if there's a search tab
        if searchTabIndex >= 0 {
            setupSearchController()
        }

        self.delegate = self
    }

    private func setupFromArgs(_ args: [String: Any]) {
        let labels = (args["labels"] as? [String]) ?? []
        let symbols = (args["sfSymbols"] as? [String]) ?? []
        let searchFlags = (args["searchFlags"] as? [Bool]) ?? []
        let selectedIndex = (args["selectedIndex"] as? Int) ?? 0

        let count = max(labels.count, symbols.count)
        tabConfigurations = (0..<count).map { i in
            let isSearch = (i < searchFlags.count) && searchFlags[i]
            if isSearch {
                searchTabIndex = i
            }
            return TabConfiguration(
                title: i < labels.count ? labels[i] : nil,
                sfSymbol: i < symbols.count ? symbols[i] : nil,
                isSearch: isSearch,
                index: i
            )
        }

        self.selectedIndex = selectedIndex
    }

    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()

        // iOS 26 Liquid Glass effect
        appearance.configureWithDefaultBackground()

        // Enable blur effect for liquid glass
        if #available(iOS 26.0, *) {
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        }

        // Configure colors
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        appearance.shadowColor = .clear

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func setupViewControllers() {
        var controllers: [UIViewController] = []

        for config in tabConfigurations {
            // Create a container view controller for each tab
            let vc = TabContentViewController()
            vc.tabIndex = config.index
            vc.onAppear = { [weak self] index in
                self?.notifyTabSelected(index)
            }

            // Setup tab bar item
            if config.isSearch {
                // Use search system item for iOS 26
                vc.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: config.index)
                if let title = config.title {
                    vc.tabBarItem.title = title
                }
            } else {
                var image: UIImage?
                if let symbol = config.sfSymbol {
                    image = UIImage(systemName: symbol)
                }
                vc.tabBarItem = UITabBarItem(
                    title: config.title ?? "Tab \(config.index + 1)",
                    image: image,
                    selectedImage: image
                )
                vc.tabBarItem.tag = config.index
            }

            // Wrap in navigation controller for search tab
            if config.isSearch {
                let navController = UINavigationController(rootViewController: vc)
                controllers.append(navController)
            } else {
                controllers.append(vc)
            }
        }

        self.viewControllers = controllers
    }

    private func setupSearchController() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"

        // Configure for iOS 26 integration
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.automaticallyShowsCancelButton = true

        // Get the search tab's navigation controller
        if searchTabIndex >= 0,
           let searchVC = viewControllers?[searchTabIndex] as? UINavigationController,
           let rootVC = searchVC.topViewController {
            rootVC.navigationItem.searchController = searchController
            rootVC.navigationItem.hidesSearchBarWhenScrolling = false
        }

        self.searchController = searchController
    }

    private func notifyTabSelected(_ index: Int) {
        channel.invokeMethod("onTabSelected", arguments: ["index": index])
    }

    private func notifySearchQueryChanged(_ query: String) {
        channel.invokeMethod("onSearchQueryChanged", arguments: ["query": query])
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSelectedIndex":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "invalid_args", message: "Invalid index", details: nil))
                return
            }
            self.selectedIndex = index
            result(nil)

        case "updateSearchQuery":
            guard let args = call.arguments as? [String: Any],
                  let query = args["query"] as? String else {
                result(FlutterError(code: "invalid_args", message: "Invalid query", details: nil))
                return
            }
            searchController?.searchBar.text = query
            result(nil)

        case "showSearch":
            if let searchController = self.searchController {
                searchController.isActive = true
            }
            result(nil)

        case "hideSearch":
            if let searchController = self.searchController {
                searchController.isActive = false
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else { return }
        notifySearchQueryChanged(query)
    }

    // MARK: - UISearchBarDelegate

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text else { return }
        channel.invokeMethod("onSearchSubmitted", arguments: ["query": query])
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        channel.invokeMethod("onSearchCancelled", arguments: nil)
    }
}

// MARK: - UITabBarControllerDelegate

@available(iOS 26.0, *)
extension iOS26SearchTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = viewControllers?.firstIndex(of: viewController) ?? 0
        notifyTabSelected(index)
    }
}

// MARK: - Tab Content View Controller

private class TabContentViewController: UIViewController {
    var tabIndex: Int = 0
    var onAppear: ((Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Add a placeholder label
        let label = UILabel()
        label.text = "Tab \(tabIndex + 1) Content\n\nThis area will be controlled by Flutter"
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
        onAppear?(tabIndex)
    }
}

// MARK: - Platform View Wrapper

@available(iOS 26.0, *)
class iOS26SearchTabBarPlatformView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let tabBarController: iOS26SearchTabBarController?

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.containerView = UIView(frame: frame)

        var argsDict: [String: Any]?
        if let args = args as? [String: Any] {
            argsDict = args
        }

        if #available(iOS 26.0, *) {
            let controller = iOS26SearchTabBarController(
                viewId: viewId,
                args: argsDict,
                messenger: messenger
            )
            self.tabBarController = controller

            super.init()

            // Add tab bar controller's view as subview
            if let view = controller.view {
                view.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    view.topAnchor.constraint(equalTo: containerView.topAnchor),
                    view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
            }
        } else {
            self.tabBarController = nil
            super.init()
        }
    }

    func view() -> UIView {
        return containerView
    }
}

// MARK: - Platform View Factory

@available(iOS 26.0, *)
class iOS26SearchTabBarViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return iOS26SearchTabBarPlatformView(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
