import AVFoundation
import Flutter
import UIKit

public class VolumeControllerPlugin: NSObject, FlutterPlugin, FlutterApplicationLifeCycleDelegate {
  private static let audioSession = AVAudioSession.sharedInstance()
  private static let volumeController = VolumeController(audioSession: audioSession)
  private static let volumeListener = VolumeListener(audioSession: audioSession)

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Method Channel
    let methodChannel = FlutterMethodChannel(
      name: ChannelName.methodChannel, binaryMessenger: registrar.messenger())
    let instance = VolumeControllerPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    // Volume Listener Event Channel
    let eventChannel: FlutterEventChannel = FlutterEventChannel(
      name: ChannelName.eventChannel,
      binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(volumeListener)

    // Application Life Cycle
    registrar.addApplicationDelegate(instance)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case MethodName.getVolume:
      let volume = VolumeControllerPlugin.volumeController.getVolume()
      result(volume)
    case MethodName.setVolume:
      let arg = call.arguments as? [String: Any]
      let volume = arg?[MethodArgument.volume] as? Double
      let showSystemUI = arg?[MethodArgument.showSystemUI] as? Bool

      VolumeControllerPlugin.volumeController.setVolume(
        volume: Float(volume!), showSystemUI: showSystemUI!)
      result(nil)
    case MethodName.isMuted:
      let isMuted = VolumeControllerPlugin.volumeController.isMuted()
      result(isMuted)
    case MethodName.setMute:
      let arg = call.arguments as? [String: Any]
      let isMute = arg?[MethodArgument.isMute] as? Bool
      let showSystemUI = arg?[MethodArgument.showSystemUI] as? Bool

      VolumeControllerPlugin.volumeController.setMute(isMute: isMute!, showSystemUI: showSystemUI!)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func applicationWillEnterForeground(_ application: UIApplication) {
    // On iOS 13 and above, the scene delegate's sceneWillEnterForeground will be called instead of this method.
    if #available(iOS 13.0, *) {
      return
    }

    guard VolumeControllerPlugin.volumeListener.isObservingVolume else {
      return
    }

    VolumeControllerPlugin.audioSession.setAudioSessionCategory()
    VolumeControllerPlugin.audioSession.activateAudioSession()
    VolumeControllerPlugin.volumeListener.sendVolumeChangeEvent()
  }

}

@available(iOS 13.0, *)
extension VolumeControllerPlugin: FlutterSceneLifeCycleDelegate {
  public func sceneWillEnterForeground(_ scene: UIScene) {
    guard VolumeControllerPlugin.volumeListener.isObservingVolume else {
      return
    }

    VolumeControllerPlugin.audioSession.setAudioSessionCategory()
    VolumeControllerPlugin.audioSession.activateAudioSession()
    VolumeControllerPlugin.volumeListener.sendVolumeChangeEvent()
  }
}
