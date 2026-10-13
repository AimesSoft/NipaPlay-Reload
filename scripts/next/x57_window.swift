import CoreGraphics
import Foundation

// Select by the PID returned by this experiment's Popen, never by app name.
let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]
let own = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int) == pid &&
    ($0[kCGWindowLayer as String] as? Int) == 0 &&
    (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 300
}
guard own.count == 1, let id = own[0][kCGWindowNumber as String] as? Int else {
    exit(1)
}
print(id)
