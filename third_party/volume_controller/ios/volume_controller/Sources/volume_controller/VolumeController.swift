import AVFoundation
import MediaPlayer
import UIKit

public class VolumeController {
  private let audioSession: AVAudioSession
  private let volumeView: MPVolumeView = MPVolumeView()
  private var tempMuteVolume: Float?

  init(audioSession: AVAudioSession) {
    self.audioSession = audioSession
  }

  public func getVolume() -> Float {
    return audioSession.getVolume()
  }

  public func setVolume(volume: Float, showSystemUI: Bool) {
    let clampedVolume = volume.clamp(to: 0.0...1.0)
    if clampedVolume != 0.0 {
      tempMuteVolume = nil
    }

    if showSystemUI {
      volumeView.frame = CGRect()
      volumeView.showsRouteButton = true
      volumeView.removeFromSuperview()
    } else {
      volumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
      volumeView.showsRouteButton = false
      UIApplication.shared.keyWindow?.insertSubview(volumeView, at: 0)
    }

    guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
      return
    }

    slider.value = clampedVolume
  }

  public func isMuted() -> Bool {
    return getVolume() == 0
  }

  public func setMute(isMute: Bool, showSystemUI: Bool) {
    if isMute {
      tempMuteVolume = getVolume()
      setVolume(volume: 0, showSystemUI: showSystemUI)
    } else {
      guard let previousVolume = tempMuteVolume else { return }
      setVolume(volume: previousVolume, showSystemUI: showSystemUI)
      tempMuteVolume = nil
    }
  }
}
