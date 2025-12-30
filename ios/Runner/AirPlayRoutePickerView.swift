import AVKit
import Flutter
import UIKit

final class AirPlayRoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AirPlayRoutePickerPlatformView(frame: frame, viewId: viewId, args: args)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class AirPlayRoutePickerPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView

  init(frame: CGRect, viewId _: Int64, args: Any?) {
    containerView = UIView(frame: frame)
    super.init()

    let pickerView = AVRoutePickerView(frame: containerView.bounds)
    pickerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    pickerView.backgroundColor = .clear

    if let dict = args as? [String: Any] {
      if let rawTint = dict["tintColor"] as? Int {
        pickerView.tintColor = Self.colorFromArgb(rawTint)
      } else {
        pickerView.tintColor = .white
      }

      if let rawActiveTint = dict["activeTintColor"] as? Int {
        pickerView.activeTintColor = Self.colorFromArgb(rawActiveTint)
      } else {
        pickerView.activeTintColor = .white
      }

      if let prioritize = dict["prioritizesVideoDevices"] as? Bool {
        pickerView.prioritizesVideoDevices = prioritize
      }
    } else {
      pickerView.tintColor = .white
      pickerView.activeTintColor = .white
      pickerView.prioritizesVideoDevices = true
    }

    containerView.addSubview(pickerView)
  }

  func view() -> UIView {
    containerView
  }

  private static func colorFromArgb(_ argb: Int) -> UIColor {
    let value = UInt32(bitPattern: Int32(argb))
    let a = CGFloat((value >> 24) & 0xFF) / 255.0
    let r = CGFloat((value >> 16) & 0xFF) / 255.0
    let g = CGFloat((value >> 8) & 0xFF) / 255.0
    let b = CGFloat(value & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}

