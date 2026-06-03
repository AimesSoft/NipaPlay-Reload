import AVFoundation
import AudioToolbox
import Cocoa
import CoreAudio
import MediaPlayer

public class VolumeController {
  public func getVolume() -> Float {
    let volume = AudioHelper.getVolume()

    return Float(volume)
  }

  public func setVolume(volume: Float) {
    AudioHelper.setVolume(volume: volume)
  }

  public func isMuted() -> Bool {
    return AudioHelper.isMuted()
  }

  public func setMute(isMute: Bool) {
    AudioHelper.setMute(isMute: isMute)
  }
}
