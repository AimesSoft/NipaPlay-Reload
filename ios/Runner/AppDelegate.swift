import Flutter
import UIKit
import AVKit
import Photos

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

      let photoChannel = FlutterMethodChannel(
        name: "nipaplay/photo_library",
        binaryMessenger: controller.binaryMessenger
      )

      photoChannel.setMethodCallHandler { call, result in
        guard call.method == "saveImage" else {
          result(FlutterMethodNotImplemented)
          return
        }

        guard
          let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENTS",
              message: "Image bytes are required",
              details: nil
            )
          )
          return
        }

        let data = typedData.data
        guard let image = UIImage(data: data) else {
          result(
            FlutterError(
              code: "INVALID_IMAGE",
              message: "Unable to decode image bytes",
              details: nil
            )
          )
          return
        }

        let saveBlock = {
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
          }) { success, error in
            DispatchQueue.main.async {
              if success {
                result(true)
              } else {
                result(
                  FlutterError(
                    code: "SAVE_FAILED",
                    message: error?.localizedDescription ?? "Failed to save image",
                    details: nil
                  )
                )
              }
            }
          }
        }

        if #available(iOS 14, *) {
          let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
          if status == .authorized {
            saveBlock()
            return
          }

          PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            DispatchQueue.main.async {
              if newStatus == .authorized {
                saveBlock()
              } else {
                result(
                  FlutterError(
                    code: "PERMISSION_DENIED",
                    message: "Photo library permission denied",
                    details: nil
                  )
                )
              }
            }
          }
        } else {
          let status = PHPhotoLibrary.authorizationStatus()
          if status == .authorized {
            saveBlock()
            return
          }

          PHPhotoLibrary.requestAuthorization { newStatus in
            DispatchQueue.main.async {
              if newStatus == .authorized {
                saveBlock()
              } else {
                result(
                  FlutterError(
                    code: "PERMISSION_DENIED",
                    message: "Photo library permission denied",
                    details: nil
                  )
                )
              }
            }
          }
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
