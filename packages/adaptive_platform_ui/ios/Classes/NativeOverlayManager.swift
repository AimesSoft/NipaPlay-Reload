import Flutter
import UIKit

final class NativeOverlayManager {
    static let shared = NativeOverlayManager()

    private var scanWindow: UIWindow?
    private var scanTitleLabel: UILabel?
    private var scanMessageLabel: UILabel?
    private var scanProgressView: UIProgressView?

    private var toastWindow: UIWindow?
    private var toastLabel: UILabel?
    private var toastView: UIVisualEffectView?
    private var toastWorkItem: DispatchWorkItem?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            switch call.method {
            case "showScanProgress":
                let args = call.arguments as? [String: Any] ?? [:]
                let title = args["title"] as? String ?? "正在扫描"
                let message = args["message"] as? String ?? ""
                let progress = args["progress"] as? Double ?? 0.0
                self.showScanProgress(title: title, message: message, progress: progress)
                result(nil)
            case "updateScanProgress":
                let args = call.arguments as? [String: Any] ?? [:]
                let message = args["message"] as? String
                let progress = args["progress"] as? Double
                self.updateScanProgress(message: message, progress: progress)
                result(nil)
            case "dismissScanProgress":
                self.dismissScanProgress()
                result(nil)
            case "showToast":
                let args = call.arguments as? [String: Any] ?? [:]
                let message = args["message"] as? String ?? ""
                let durationMs = args["durationMs"] as? Double ?? 2000
                self.showToast(message: message, duration: durationMs / 1000.0)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func activeWindowScene() -> UIWindowScene? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        }
        return nil
    }

    private func showScanProgress(title: String, message: String, progress: Double) {
        if scanWindow == nil {
            let window: UIWindow
            if #available(iOS 13.0, *), let scene = activeWindowScene() {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
            window.windowLevel = .alert + 1
            let root = UIViewController()
            root.view.backgroundColor = UIColor(white: 0.0, alpha: 0.25)
            window.rootViewController = root

            let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            card.translatesAutoresizingMaskIntoConstraints = false
            card.layer.cornerRadius = 16
            card.clipsToBounds = true
            root.view.addSubview(card)

            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            titleLabel.textColor = UIColor.label
            titleLabel.textAlignment = .center

            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            messageLabel.textColor = UIColor.secondaryLabel
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 2

            let progressView = UIProgressView(progressViewStyle: .default)
            progressView.translatesAutoresizingMaskIntoConstraints = false
            progressView.progressTintColor = UIColor.systemPink
            progressView.trackTintColor = UIColor.systemGray5

            card.contentView.addSubview(titleLabel)
            card.contentView.addSubview(messageLabel)
            card.contentView.addSubview(progressView)

            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
                card.centerYAnchor.constraint(equalTo: root.view.centerYAnchor),
                card.widthAnchor.constraint(equalToConstant: 280),

                titleLabel.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 18),
                titleLabel.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),

                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                messageLabel.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
                messageLabel.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),

                progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
                progressView.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 20),
                progressView.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -20),
                progressView.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -18),
            ])

            scanWindow = window
            scanTitleLabel = titleLabel
            scanMessageLabel = messageLabel
            scanProgressView = progressView
        }

        scanTitleLabel?.text = title
        scanMessageLabel?.text = message
        scanProgressView?.progress = Float(min(max(progress, 0.0), 1.0))
        scanWindow?.isHidden = false
    }

    private func updateScanProgress(message: String?, progress: Double?) {
        if let message = message {
            scanMessageLabel?.text = message
        }
        if let progress = progress {
            scanProgressView?.progress = Float(min(max(progress, 0.0), 1.0))
        }
    }

    private func dismissScanProgress() {
        scanWindow?.isHidden = true
        scanWindow = nil
        scanTitleLabel = nil
        scanMessageLabel = nil
        scanProgressView = nil
    }

    private func showToast(message: String, duration: Double) {
        if toastWindow == nil {
            let window: UIWindow
            if #available(iOS 13.0, *), let scene = activeWindowScene() {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
            window.windowLevel = .alert + 2
            window.isUserInteractionEnabled = false
            let root = UIViewController()
            root.view.backgroundColor = .clear
            window.rootViewController = root

            let toast = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            toast.translatesAutoresizingMaskIntoConstraints = false
            toast.layer.cornerRadius = 12
            toast.clipsToBounds = true
            root.view.addSubview(toast)

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            label.textColor = UIColor.label
            label.textAlignment = .center
            label.numberOfLines = 2

            toast.contentView.addSubview(label)

            let safe = root.view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                toast.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
                toast.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -32),
                toast.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

                label.topAnchor.constraint(equalTo: toast.contentView.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: toast.contentView.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: toast.contentView.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: toast.contentView.trailingAnchor, constant: -16),
            ])

            toastWindow = window
            toastLabel = label
            toastView = toast
            toast.alpha = 0.0
        }

        toastWorkItem?.cancel()

        toastLabel?.text = message
        toastWindow?.isHidden = false

        guard let toastView = toastView else { return }
        toastView.alpha = 0.0
        UIView.animate(withDuration: 0.2) {
            toastView.alpha = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.2, animations: {
                toastView.alpha = 0.0
            }, completion: { _ in
                self?.toastWindow?.isHidden = true
                self?.toastWindow = nil
                self?.toastLabel = nil
                self?.toastView = nil
            })
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
