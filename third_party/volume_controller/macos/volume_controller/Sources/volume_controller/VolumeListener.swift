import AVFoundation
import CoreAudio
import FlutterMacOS

public class VolumeListener: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var defaultDeviceID: AudioObjectID?
  private var isObserving = false

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    let args = arguments as! [String: Any]
    let fetchInitialVolume = args[EventArgument.fetchInitialVolume] as! Bool

    self.eventSink = events
    startObservingVolumeChanges()

    if fetchInitialVolume {
      let volume = AudioHelper.getVolume()

      events(volume)
    }

    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopObservingVolumeChanges()
    self.eventSink = nil
    return nil
  }

  private let volumeChangeListener: AudioObjectPropertyListenerProc = {
    (inObjectID, inNumberAddresses, inAddresses, inClientData) in
    guard let inClientData = inClientData else {
      return noErr
    }
    let listener = Unmanaged<VolumeListener>.fromOpaque(inClientData).takeUnretainedValue()
    listener.notifyVolumeChange()
    return noErr
  }

  private func startObservingVolumeChanges() {
    guard !isObserving else { return }

    defaultDeviceID = AudioHelper.getDefaultOutputDeviceID()
    guard let deviceID = defaultDeviceID else {
      print("Could not get default output device ID")
      return
    }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectAddPropertyListener(
      deviceID, &address, volumeChangeListener, Unmanaged.passUnretained(self).toOpaque())

    if status == noErr {
      isObserving = true
    } else {
      print("Error adding volume property listener: \(status)")
    }
  }

  private func stopObservingVolumeChanges() {
    guard isObserving, let deviceID = defaultDeviceID else { return }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectRemovePropertyListener(
      deviceID, &address, volumeChangeListener, Unmanaged.passUnretained(self).toOpaque())

    if status == noErr {
      isObserving = false
    } else {
      print("Error removing volume property listener: \(status)")
    }
  }

  private func notifyVolumeChange() {
    let volume = AudioHelper.getVolume()

    eventSink?(volume)
  }
}
