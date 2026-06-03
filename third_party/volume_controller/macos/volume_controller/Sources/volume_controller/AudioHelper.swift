import AudioToolbox
import CoreAudio

public class AudioHelper {
  static func getDefaultOutputDeviceID() -> AudioObjectID? {
    var defaultDeviceID = AudioObjectID(0)
    var size = UInt32(MemoryLayout.size(ofValue: defaultDeviceID))
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0,
      nil,
      &size,
      &defaultDeviceID
    )

    return status == noErr ? defaultDeviceID : nil
  }

  static func getVolume() -> Float {
    guard let deviceID = getDefaultOutputDeviceID() else {
      print("Could not get default output device ID")
      return 0.0
    }

    var volume: Float32 = 0.0
    var size = UInt32(MemoryLayout.size(ofValue: volume))
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    if status != noErr {
      print("Error getting volume: \(status)")
      return 0.0
    }

    return Float(volume)
  }

  static func setVolume(volume: Float) {
    guard let deviceID = getDefaultOutputDeviceID() else {
      print("Could not get default output device ID")
      return
    }

    var newVolume = volume
    let size = UInt32(MemoryLayout.size(ofValue: newVolume))
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newVolume)
    if status != noErr {
      print("Error setting volume: \(status)")
    }
  }

  static func setMute(isMute: Bool) {
    guard let deviceID = getDefaultOutputDeviceID() else {
      print("Could not get default output device ID")
      return
    }

    var mute: UInt32 = isMute ? 1 : 0
    let size = UInt32(MemoryLayout.size(ofValue: mute))
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mute)
    if status != noErr {
      print("Error setting mute: \(status)")
    }
  }

  static func isMuted() -> Bool {
    guard let deviceID = getDefaultOutputDeviceID() else {
      print("Could not get default output device ID")
      return false
    }

    var mute: UInt32 = 0
    var size = UInt32(MemoryLayout.size(ofValue: mute))
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
    if status != noErr {
      print("Error getting mute status: \(status)")
      return false
    }

    return mute == 1
  }
}
