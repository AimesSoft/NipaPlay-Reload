import AVFoundation
import Foundation

extension Comparable {
  func clamp(to limits: ClosedRange<Self>) -> Self {
    return min(max(self, limits.lowerBound), limits.upperBound)
  }
}

extension AVAudioSession {
  func getVolume() -> Float {
    return outputVolume
  }

  func activateAudioSession() {
    do {
      try setAudioSessionCategory()
      try setActive(true)
    } catch {
      print("Error activating audio session: \(error)")
    }
  }

  func deactivateAudioSession() {
    do {
      try setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Error deactivating audio session: \(error)")
    }
  }

  func setAudioSessionCategory() {
    do {
      try setCategory(.playback, options: [.mixWithOthers])
    } catch {
      print("Error setting audio session category: \(error)")
    }
  }
}
