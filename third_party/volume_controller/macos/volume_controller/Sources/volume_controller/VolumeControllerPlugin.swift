import Cocoa
import FlutterMacOS

public class VolumeControllerPlugin: NSObject, FlutterPlugin {
  private let volumeController = VolumeController()

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Method Channel
    let methodChannel = FlutterMethodChannel(
      name: ChannelName.methodChannel, binaryMessenger: registrar.messenger)
    let instance = VolumeControllerPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    // Volume Listener Event Channel
    let eventChannel: FlutterEventChannel = FlutterEventChannel(
      name: ChannelName.eventChannel, binaryMessenger: registrar.messenger)
    eventChannel.setStreamHandler(VolumeListener())
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case MethodName.getVolume:
      let volume = volumeController.getVolume()
      result(volume)
    case MethodName.setVolume:
      let arg = call.arguments as? [String: Any]
      let volume = arg?[MethodArgument.volume] as? Double

      volumeController.setVolume(volume: Float(volume!))
      result(nil)
    case MethodName.isMuted:
      let isMuted = volumeController.isMuted()
      result(isMuted)
    case MethodName.setMute:
      let arg = call.arguments as? [String: Any]
      let isMute = arg?[MethodArgument.isMute] as? Bool

      volumeController.setMute(isMute: isMute!)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
