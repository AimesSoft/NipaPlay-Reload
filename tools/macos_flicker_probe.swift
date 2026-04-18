#!/usr/bin/env swift

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

struct Config {
  var windowQuery = "NipaPlay"
  var rect: CGRect?
  var duration: Double = 8
  var fps: Double = 30
  var autoVideo = false
  var aspectRatio: CGFloat = 16.0 / 9.0
  var insetTop: CGFloat = 0
  var insetLeft: CGFloat = 0
  var insetRight: CGFloat = 0
  var insetBottom: CGFloat = 0
  var meanBlackThreshold: Double = 0.035
  var darkPixelThreshold: Double = 0.06
  var darkRatioThreshold: Double = 0.85
  var listWindows = false
}

struct WindowCandidate {
  let owner: String
  let title: String
  let bounds: CGRect
  let layer: Int

  var area: CGFloat {
    bounds.width * bounds.height
  }
}

struct FrameStats {
  let mean: Double
  let max: Double
  let darkRatio: Double

  var isBlack: Bool {
    mean < config.meanBlackThreshold || darkRatio > config.darkRatioThreshold
  }
}

private var config = Config()

func usage() -> Never {
  print(
    """
    Usage:
      swift tools/macos_flicker_probe.swift [options]

    Options:
      --window TEXT          Window owner/title substring. Default: NipaPlay
      --rect x,y,w,h         Global screen rect to sample.
      --auto-video           Fit a 16:9 video rect inside the selected window.
      --aspect VALUE         Aspect ratio for --auto-video. Default: 1.777777
      --inset-top VALUE      Top inset before --auto-video, in screen points.
      --inset-left VALUE     Left inset before --auto-video.
      --inset-right VALUE    Right inset before --auto-video.
      --inset-bottom VALUE   Bottom inset before --auto-video.
      --duration SECONDS     Sampling duration. Default: 8
      --fps VALUE            Sampling FPS. Default: 30
      --mean-threshold VALUE Mean luminance threshold for black frame. Default: 0.035
      --dark-threshold VALUE Per-pixel dark luminance threshold. Default: 0.06
      --dark-ratio VALUE     Dark-pixel ratio threshold. Default: 0.85
      --list-windows         Print visible windows and exit.
    """
  )
  exit(2)
}

func parseRect(_ value: String) -> CGRect? {
  let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
  guard parts.count == 4 else {
    return nil
  }
  return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

func parseArguments() {
  var args = Array(CommandLine.arguments.dropFirst())
  while !args.isEmpty {
    let arg = args.removeFirst()
    func requireValue() -> String {
      guard !args.isEmpty else {
        usage()
      }
      return args.removeFirst()
    }

    switch arg {
    case "--window":
      config.windowQuery = requireValue()
    case "--rect":
      guard let rect = parseRect(requireValue()) else {
        usage()
      }
      config.rect = rect
    case "--duration":
      config.duration = Double(requireValue()) ?? config.duration
    case "--fps":
      config.fps = Double(requireValue()) ?? config.fps
    case "--auto-video":
      config.autoVideo = true
    case "--aspect":
      config.aspectRatio = CGFloat(Double(requireValue()) ?? Double(config.aspectRatio))
    case "--inset-top":
      config.insetTop = CGFloat(Double(requireValue()) ?? 0)
    case "--inset-left":
      config.insetLeft = CGFloat(Double(requireValue()) ?? 0)
    case "--inset-right":
      config.insetRight = CGFloat(Double(requireValue()) ?? 0)
    case "--inset-bottom":
      config.insetBottom = CGFloat(Double(requireValue()) ?? 0)
    case "--mean-threshold":
      config.meanBlackThreshold = Double(requireValue()) ?? config.meanBlackThreshold
    case "--dark-threshold":
      config.darkPixelThreshold = Double(requireValue()) ?? config.darkPixelThreshold
    case "--dark-ratio":
      config.darkRatioThreshold = Double(requireValue()) ?? config.darkRatioThreshold
    case "--list-windows":
      config.listWindows = true
    case "--help", "-h":
      usage()
    default:
      print("Unknown argument: \(arg)")
      usage()
    }
  }
}

func number(_ value: Any?) -> CGFloat? {
  if let number = value as? NSNumber {
    return CGFloat(truncating: number)
  }
  if let value = value as? Double {
    return CGFloat(value)
  }
  return nil
}

func windowBounds(from dictionary: [String: Any]) -> CGRect? {
  guard let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
        let x = number(bounds["X"]),
        let y = number(bounds["Y"]),
        let width = number(bounds["Width"]),
        let height = number(bounds["Height"]) else {
    return nil
  }
  return CGRect(x: x, y: y, width: width, height: height)
}

func visibleWindows() -> [WindowCandidate] {
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    return []
  }

  return raw.compactMap { info in
    guard let bounds = windowBounds(from: info), bounds.width > 1, bounds.height > 1 else {
      return nil
    }
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let title = info[kCGWindowName as String] as? String ?? ""
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    return WindowCandidate(owner: owner, title: title, bounds: bounds, layer: layer)
  }
}

func printWindows(_ windows: [WindowCandidate]) {
  for window in windows.sorted(by: { $0.area > $1.area }) {
    print(
      "window owner=\"\(window.owner)\" title=\"\(window.title)\" layer=\(window.layer) rect=\(format(window.bounds))"
    )
  }
}

func selectedWindowRect() -> CGRect? {
  let query = config.windowQuery.lowercased()
  return visibleWindows()
    .filter { window in
      window.layer == 0 &&
        (window.owner.lowercased().contains(query) || window.title.lowercased().contains(query))
    }
    .sorted { $0.area > $1.area }
    .first?
    .bounds
}

func containedAspectRect(in rect: CGRect, aspectRatio: CGFloat) -> CGRect {
  guard rect.width > 0, rect.height > 0, aspectRatio > 0 else {
    return rect
  }
  let currentAspectRatio = rect.width / rect.height
  if currentAspectRatio > aspectRatio {
    let width = rect.height * aspectRatio
    return CGRect(
      x: rect.minX + (rect.width - width) / 2,
      y: rect.minY,
      width: width,
      height: rect.height
    )
  }

  let height = rect.width / aspectRatio
  return CGRect(
    x: rect.minX,
    y: rect.minY + (rect.height - height) / 2,
    width: rect.width,
    height: height
  )
}

func sampleRect() -> CGRect? {
  if let rect = config.rect {
    return rect
  }

  guard let windowRect = selectedWindowRect() else {
    return nil
  }

  if !config.autoVideo {
    return windowRect
  }

  let contentRect = CGRect(
    x: windowRect.minX + config.insetLeft,
    y: windowRect.minY + config.insetTop,
    width: windowRect.width - config.insetLeft - config.insetRight,
    height: windowRect.height - config.insetTop - config.insetBottom
  )
  return containedAspectRect(in: contentRect, aspectRatio: config.aspectRatio)
}

func onlineDisplays() -> [CGDirectDisplayID] {
  var count: UInt32 = 0
  CGGetOnlineDisplayList(0, nil, &count)
  var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
  CGGetOnlineDisplayList(count, &displays, &count)
  return Array(displays.prefix(Int(count)))
}

func displayForRect(_ rect: CGRect) -> (CGDirectDisplayID, CGRect)? {
  let center = CGPoint(x: rect.midX, y: rect.midY)
  let displays = onlineDisplays()
  if let display = displays.first(where: { CGDisplayBounds($0).contains(center) }) {
    return (display, CGDisplayBounds(display))
  }
  if let display = displays.first(where: { CGDisplayBounds($0).intersects(rect) }) {
    return (display, CGDisplayBounds(display))
  }
  guard let first = displays.first else {
    return nil
  }
  return (first, CGDisplayBounds(first))
}

func stats(for pixelBuffer: CVPixelBuffer) -> FrameStats? {
  CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
  defer {
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
  }

  guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    return nil
  }

  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  guard width > 0, height > 0, bytesPerRow >= width * 4 else {
    return nil
  }

  let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
  let sampleStepX = max(1, width / 96)
  let sampleStepY = max(1, height / 96)
  var sum = 0.0
  var maxValue = 0.0
  var darkPixels = 0
  var pixelCount = 0

  for y in stride(from: 0, to: height, by: sampleStepY) {
    let row = pointer.advanced(by: y * bytesPerRow)
    for x in stride(from: 0, to: width, by: sampleStepX) {
      let offset = x * 4
      let b = Double(row[offset]) / 255.0
      let g = Double(row[offset + 1]) / 255.0
      let r = Double(row[offset + 2]) / 255.0
      let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
      sum += luminance
      maxValue = max(maxValue, luminance)
      if luminance < config.darkPixelThreshold {
        darkPixels += 1
      }
      pixelCount += 1
    }
  }

  guard pixelCount > 0 else {
    return nil
  }

  return FrameStats(
    mean: sum / Double(pixelCount),
    max: maxValue,
    darkRatio: Double(darkPixels) / Double(pixelCount)
  )
}

func stats(for image: CGImage) -> FrameStats? {
  let width = max(1, min(96, image.width))
  let height = max(1, min(96, image.height))
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
    CGBitmapInfo.byteOrder32Big.rawValue

  let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let baseAddress = buffer.baseAddress,
          let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
          ) else {
      return false
    }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }

  guard ok else {
    return nil
  }

  var sum = 0.0
  var maxValue = 0.0
  var darkPixels = 0
  let pixelCount = width * height
  for index in stride(from: 0, to: pixels.count, by: 4) {
    let r = Double(pixels[index]) / 255.0
    let g = Double(pixels[index + 1]) / 255.0
    let b = Double(pixels[index + 2]) / 255.0
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    sum += luminance
    maxValue = max(maxValue, luminance)
    if luminance < config.darkPixelThreshold {
      darkPixels += 1
    }
  }

  return FrameStats(
    mean: sum / Double(pixelCount),
    max: maxValue,
    darkRatio: Double(darkPixels) / Double(pixelCount)
  )
}

@available(macOS 12.3, *)
final class CaptureOutput: NSObject, SCStreamOutput {
  private let start: CFAbsoluteTime
  private var frameIndex = 0
  private var blackFrameCount = 0
  private var longestBlackRun = 0
  private var currentBlackRun = 0

  init(start: CFAbsoluteTime) {
    self.start = start
    super.init()
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen,
          sampleBuffer.isValid,
          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }

    let now = CFAbsoluteTimeGetCurrent()
    guard let stats = stats(for: pixelBuffer) else {
      print("\(frameIndex),\(format((now - start) * 1000.0)),nan,nan,nan,-1")
      frameIndex += 1
      return
    }

    let isBlack = stats.isBlack
    if isBlack {
      blackFrameCount += 1
      currentBlackRun += 1
      longestBlackRun = max(longestBlackRun, currentBlackRun)
    } else {
      currentBlackRun = 0
    }

    print(
      "\(frameIndex),\(format((now - start) * 1000.0)),\(format(stats.mean)),\(format(stats.max)),\(format(stats.darkRatio)),\(isBlack ? 1 : 0)"
    )
    frameIndex += 1
  }

  func summary() -> String {
    let blackRatio = frameIndex > 0 ? Double(blackFrameCount) / Double(frameIndex) : 0
    return
      "summary frames=\(frameIndex) black_frames=\(blackFrameCount) black_ratio=\(format(blackRatio)) longest_black_run=\(longestBlackRun)"
  }
}

func format(_ value: Double) -> String {
  String(format: "%.4f", value)
}

func format(_ rect: CGRect) -> String {
  String(
    format: "%.1f,%.1f,%.1f,%.1f",
    Double(rect.minX),
    Double(rect.minY),
    Double(rect.width),
    Double(rect.height)
  )
}

parseArguments()

let windows = visibleWindows()
if config.listWindows {
  printWindows(windows)
  exit(0)
}

guard let rect = sampleRect() else {
  print("No target rect found. Try --list-windows or pass --rect x,y,w,h.")
  exit(1)
}

guard let (display, displayBounds) = displayForRect(rect) else {
  print("No online display found.")
  exit(1)
}

let interval = max(1.0 / max(config.fps, 1), 0.001)

print(
  "probe rect=\(format(rect)) display=\(display) displayBounds=\(format(displayBounds)) duration=\(format(config.duration)) fps=\(format(config.fps))"
)
print("frame,t_ms,mean,max,dark_ratio,is_black")

if #available(macOS 12.3, *) {
  let localRect = rect.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)

  Task {
    do {
      let shareableContent = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
      )
      guard let screenCaptureDisplay = shareableContent.displays.first(where: {
        $0.displayID == display
      }) else {
        print("ScreenCaptureKit display \(display) was not found.")
        exit(1)
      }

      let filter = SCContentFilter(
        display: screenCaptureDisplay,
        excludingWindows: []
      )
      let configuration = SCStreamConfiguration()
      configuration.sourceRect = localRect.integral
      configuration.width = max(1, Int(localRect.width.rounded()))
      configuration.height = max(1, Int(localRect.height.rounded()))
      configuration.pixelFormat = kCVPixelFormatType_32BGRA
      configuration.queueDepth = 3
      configuration.minimumFrameInterval = CMTime(
        value: 1,
        timescale: CMTimeScale(max(1, Int(config.fps.rounded())))
      )
      configuration.showsCursor = false

      let output = CaptureOutput(start: CFAbsoluteTimeGetCurrent())
      let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
      try stream.addStreamOutput(
        output,
        type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "nipaplay.flicker-probe.capture")
      )
      try await stream.startCapture()
      try await Task.sleep(nanoseconds: UInt64(max(config.duration, interval) * 1_000_000_000))
      try await stream.stopCapture()
      print(output.summary())
      exit(0)
    } catch {
      print("ScreenCaptureKit capture failed: \(error)")
      exit(1)
    }
  }

  dispatchMain()
} else {
  print("ScreenCaptureKit requires macOS 12.3 or newer.")
  exit(1)
}
