import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "AirPlayRoutePicker") {
      let factory = AirPlayRoutePickerFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "nipaplay/airplay_route_picker")
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "nipaplay/system_share",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak controller] call, result in
        guard call.method == "share" else {
          result(FlutterMethodNotImplemented)
          return
        }

        guard let args = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENTS",
              message: "Arguments are required",
              details: nil
            )
          )
          return
        }

        let text = args["text"] as? String
        let urlString = args["url"] as? String
        let filePath = args["filePath"] as? String

        var items: [Any] = []
        if let filePath = filePath, !filePath.isEmpty {
          items.append(URL(fileURLWithPath: filePath))
        }
        if let urlString = urlString, let url = URL(string: urlString) {
          items.append(url)
        }
        if let text = text, !text.isEmpty {
          items.append(text)
        }

        if items.isEmpty {
          result(
            FlutterError(
              code: "NO_ITEMS",
              message: "Nothing to share",
              details: nil
            )
          )
          return
        }

        DispatchQueue.main.async {
          let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
          if let popover = activity.popoverPresentationController, let view = controller?.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
          }
          controller?.present(activity, animated: true)
          result(true)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
