import Flutter
import UIKit
import AVKit
import CryptoKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var fileAssociationChannel: FlutterMethodChannel?
  private var pendingOpenFiles: [String] = []
  private var pendingOpenErrors: [String] = []
  private var lastOpenedFileURL: URL?
  private var lastOpenedFileDate: Date?
  private let fileImportQueue = DispatchQueue(
    label: "com.aimessoft.nipaplay.file-import",
    qos: .userInitiated
  )

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
      let deviceProfileChannel = FlutterMethodChannel(
        name: "nipaplay/device_profile",
        binaryMessenger: controller.binaryMessenger
      )

      deviceProfileChannel.setMethodCallHandler { call, result in
        guard call.method == "getStartupDeviceProfile" else {
          result(FlutterMethodNotImplemented)
          return
        }

        let bounds = UIScreen.main.bounds
        result([
          "isIPad": UIDevice.current.userInterfaceIdiom == .pad,
          "screenWidthDp": Double(bounds.width),
          "screenHeightDp": Double(bounds.height),
          "smallestScreenWidthDp": Double(min(bounds.width, bounds.height)),
        ])
      }

      let fileChannel = FlutterMethodChannel(
        name: "file_association_channel",
        binaryMessenger: controller.binaryMessenger
      )
      fileAssociationChannel = fileChannel
      fileChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        switch call.method {
        case "getOpenFileUri":
          result(self.pendingOpenFiles.isEmpty ? nil : self.pendingOpenFiles.removeFirst())
        case "getOpenFileError":
          result(self.pendingOpenErrors.isEmpty ? nil : self.pendingOpenErrors.removeFirst())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let channel = FlutterMethodChannel(
        name: "nipaplay/system_share",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak controller] call, result in
        if call.method == "exportFile" {
          guard
            let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String,
            !filePath.isEmpty
          else {
            result(
              FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "A file path is required",
                details: nil
              )
            )
            return
          }

          guard FileManager.default.fileExists(atPath: filePath) else {
            result(
              FlutterError(
                code: "FILE_NOT_FOUND",
                message: "The file to export does not exist",
                details: filePath
              )
            )
            return
          }

          DispatchQueue.main.async {
            guard let controller = controller else {
              result(
                FlutterError(
                  code: "NO_CONTROLLER",
                  message: "No view controller is available",
                  details: nil
                )
              )
              return
            }

            let fileURL = URL(fileURLWithPath: filePath)
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) {
              picker = UIDocumentPickerViewController(
                forExporting: [fileURL],
                asCopy: true
              )
            } else {
              picker = UIDocumentPickerViewController(
                url: fileURL,
                in: .exportToService
              )
            }
            controller.present(picker, animated: true) {
              result(true)
            }
          }
          return
        }

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
          guard FileManager.default.fileExists(atPath: filePath) else {
            result(
              FlutterError(
                code: "FILE_NOT_FOUND",
                message: "The file to share does not exist",
                details: filePath
              )
            )
            return
          }
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
          guard let controller = controller else {
            result(
              FlutterError(
                code: "NO_CONTROLLER",
                message: "No view controller is available",
                details: nil
              )
            )
            return
          }
          let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
          if let popover = activity.popoverPresentationController, let view = controller.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
          }
          controller.present(activity, animated: true)
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

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let url = launchOptions?[.url] as? URL, url.isFileURL {
      receiveFileURL(url)
    }
    return launched
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handledByPlugin = super.application(application, open: url, options: options)
    guard url.isFileURL else { return handledByPlugin }
    receiveFileURL(url)
    return true
  }

  private func receiveFileURL(_ url: URL) {
    let videoExtensions: Set<String> = [
      "mp4", "mkv", "avi", "mov", "webm", "wmv", "m4v", "3gp", "flv", "ts", "m2ts"
    ]
    guard videoExtensions.contains(url.pathExtension.lowercased()) else { return }

    // A cold launch can report the same URL in launchOptions and openURL.
    let now = Date()
    if lastOpenedFileURL == url,
       let previous = lastOpenedFileDate,
       now.timeIntervalSince(previous) < 2 {
      return
    }
    lastOpenedFileURL = url
    lastOpenedFileDate = now

    fileImportQueue.async { [weak self] in
      do {
        let filePath = try Self.prepareOpenedFile(url)
        DispatchQueue.main.async {
          self?.pendingOpenFiles.append(filePath)
          self?.fileAssociationChannel?.invokeMethod("onOpenFileUri", arguments: nil)
        }
      } catch {
        NSLog("[FileAssociation] Failed to open %@: %@", url.lastPathComponent, String(describing: error))
        DispatchQueue.main.async {
          self?.pendingOpenErrors.append("无法打开文件：\(url.lastPathComponent)（\(error.localizedDescription)）")
          self?.fileAssociationChannel?.invokeMethod("onOpenFileError", arguments: nil)
        }
      }
    }
  }

  private static func prepareOpenedFile(_ url: URL) throws -> String {
    let fileManager = FileManager.default
    let source = url.resolvingSymlinksInPath().standardizedFileURL
    let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .resolvingSymlinksInPath().standardizedFileURL
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .resolvingSymlinksInPath().standardizedFileURL

    // Files may hand back a document already inside NipaPlay's container.
    if source.path.hasPrefix(documents.path + "/") ||
       source.path.hasPrefix(appSupport.path + "/") {
      guard fileManager.fileExists(atPath: source.path) else {
        throw CocoaError(.fileNoSuchFile)
      }
      return source.path
    }

    // External providers need security-scoped access while the file is read.
    // Keep a local copy because playback and watch history outlive this callback.
    let hasScope = url.startAccessingSecurityScopedResource()
    defer { if hasScope { url.stopAccessingSecurityScopedResource() } }

    var coordinationError: NSError?
    var importError: Error?
    var importedPath: String?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
      do {
        let hash = SHA256.hash(data: Data(source.absoluteString.utf8))
          .map { String(format: "%02x", $0) }.joined()
        var destinationDirectory = appSupport
          .appendingPathComponent("Opened Files", isDirectory: true)
          .appendingPathComponent(hash, isDirectory: true)
        try fileManager.createDirectory(
          at: destinationDirectory,
          withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try destinationDirectory.setResourceValues(resourceValues)

        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let sourceAttributes = try fileManager.attributesOfItem(atPath: readURL.path)
        let existingAttributes = try? fileManager.attributesOfItem(atPath: destination.path)
        let sourceSize = sourceAttributes[.size] as? NSNumber
        let sourceDate = sourceAttributes[.modificationDate] as? Date
        let existingSize = existingAttributes?[.size] as? NSNumber
        let existingDate = existingAttributes?[.modificationDate] as? Date
        if sourceSize != nil && sourceSize == existingSize &&
           sourceDate != nil && sourceDate == existingDate {
          importedPath = destination.path
          return
        }

        let temporary = destinationDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: readURL, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
          _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
          try fileManager.moveItem(at: temporary, to: destination)
        }
        if let sourceDate = sourceDate {
          try fileManager.setAttributes([.modificationDate: sourceDate], ofItemAtPath: destination.path)
        }
        importedPath = destination.path
      } catch {
        importError = error
      }
    }

    if let error = importError ?? coordinationError { throw error }
    guard let importedPath = importedPath else {
      throw CocoaError(.fileReadUnknown)
    }
    return importedPath
  }
}
