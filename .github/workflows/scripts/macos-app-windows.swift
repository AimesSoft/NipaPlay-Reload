// Observe only windows owned by the app under test; no Accessibility permission.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]),
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
      ) as? [[String: Any]] else {
    exit(2)
}

let appWindows = windows.filter { window in
    guard let owner = window[kCGWindowOwnerPID as String] as? Int32,
          owner == pid,
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else { return false }
    return width > 100 && height > 100
}
let data = try JSONSerialization.data(withJSONObject: appWindows, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(appWindows.isEmpty ? 1 : 0)
