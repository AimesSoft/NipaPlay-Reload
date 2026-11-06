import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    private var keyboardChannel: FlutterMethodChannel?
    private var keyboardIsPresented = false
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
#if targetEnvironment(simulator) && !DEBUG
        NipaInstallTVOSReleaseSimulatorShaderOverride()
#endif

        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        GeneratedPluginRegistrant.register(with: self)
        keyboardChannel = FlutterMethodChannel(
            name: "nipaplay/tvos_keyboard",
            binaryMessenger: flutterViewController.binaryMessenger
        )
        keyboardChannel?.setMethodCallHandler { [weak self] call, result in
            guard call.method == "editText" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let self = self, !self.keyboardIsPresented else {
                result(FlutterError(code: "keyboard_busy", message: "Keyboard is already open", details: nil))
                return
            }
            let arguments = call.arguments as? [String: Any] ?? [:]
            let alert = UIAlertController(
                title: arguments["title"] as? String ?? "输入文字",
                message: nil,
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.text = arguments["value"] as? String ?? ""
                field.isSecureTextEntry = arguments["obscureText"] as? Bool ?? false
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
                field.spellCheckingType = .no
                field.returnKeyType = .done
                switch arguments["inputType"] as? String {
                case "number": field.keyboardType = .numberPad
                case "email": field.keyboardType = .emailAddress
                case "url": field.keyboardType = .URL
                default: field.keyboardType = .default
                }
            }
            var completed = false
            let finish: (Any?) -> Void = { value in
                guard !completed else { return }
                completed = true
                self.keyboardIsPresented = false
                result(value)
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in finish(nil) })
            alert.addAction(UIAlertAction(title: "手机扫码输入", style: .default) { _ in
                finish(["usePhone": true])
            })
            let done = UIAlertAction(title: "完成", style: .default) { [weak alert] _ in
                finish(["value": alert?.textFields?.first?.text ?? ""])
            }
            alert.addAction(done)
            alert.preferredAction = done
            var presenter: UIViewController = flutterViewController
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            self.keyboardIsPresented = true
            presenter.present(alert, animated: true) {
                alert.textFields?.first?.becomeFirstResponder()
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
