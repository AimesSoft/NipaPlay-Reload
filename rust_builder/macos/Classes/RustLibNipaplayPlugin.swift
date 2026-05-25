import Cocoa
import CoreVideo
import FlutterMacOS
import Foundation
import Metal

@_silgen_name("next2_engine_create")
private func next2_engine_create(_ width: UInt32, _ height: UInt32) -> UInt64

@_silgen_name("next2_engine_get_mtl_device")
private func next2_engine_get_mtl_device(_ engineHandle: UInt64) -> UnsafeMutableRawPointer?

@_silgen_name("next2_engine_attach_present_texture")
private func next2_engine_attach_present_texture(
  _ engineHandle: UInt64,
  _ mtlTexturePtr: UnsafeMutableRawPointer?,
  _ width: UInt32,
  _ height: UInt32,
  _ bytesPerRow: UInt32
)

@_silgen_name("next2_engine_dispose")
private func next2_engine_dispose(_ engineHandle: UInt64)

@_silgen_name("next2_engine_poll_frame_ready")
private func next2_engine_poll_frame_ready(_ engineHandle: UInt64) -> Bool

@_silgen_name("next2_engine_set_frame")
private func next2_engine_set_frame(
  _ engineHandle: UInt64,
  _ frameJson: UnsafePointer<CChar>?,
  _ fontSize: Float,
  _ outlineWidth: Float,
  _ shadowStyle: UInt8,
  _ opacity: Float,
  _ customFontFamily: UnsafePointer<CChar>?,
  _ customFontFilePath: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("next2_engine_resize")
private func next2_engine_resize(_ engineHandle: UInt64, _ width: UInt32, _ height: UInt32) -> UInt8

@_silgen_name("next2_engine_reset_scene")
private func next2_engine_reset_scene(_ engineHandle: UInt64) -> UInt8

private final class Next2Texture: NSObject, FlutterTexture {
  fileprivate let pixelBuffer: CVPixelBuffer

  init(width: Int, height: Int) {
    var buffer: CVPixelBuffer?

    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]

    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &buffer
    )

    guard status == kCVReturnSuccess, let resolved = buffer else {
      fatalError("Failed to create CVPixelBuffer: \(status)")
    }

    pixelBuffer = resolved
    super.init()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    Unmanaged.passRetained(pixelBuffer)
  }
}

private final class Next2SurfaceState {
  var surfaceId: String
  var texture: Next2Texture
  var textureId: Int64?
  var textureWidth: Int
  var textureHeight: Int
  var engineHandle: UInt64
  var textureCache: CVMetalTextureCache?
  var presentTexture: CVMetalTexture?
  var initInProgress: Bool
  var pendingTextureInfoResults: [FlutterResult]

  init(surfaceId: String, width: Int, height: Int) {
    self.surfaceId = surfaceId
    self.texture = Next2Texture(width: width, height: height)
    self.textureId = nil
    self.textureWidth = width
    self.textureHeight = height
    self.engineHandle = 0
    self.textureCache = nil
    self.presentTexture = nil
    self.initInProgress = false
    self.pendingTextureInfoResults = []
  }
}

private func next2DisplayLinkCallback(
  displayLink: CVDisplayLink,
  inNow: UnsafePointer<CVTimeStamp>,
  inOutputTime: UnsafePointer<CVTimeStamp>,
  flagsIn: CVOptionFlags,
  flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
  guard let displayLinkContext else {
    return kCVReturnError
  }
  autoreleasepool {
    let plugin = Unmanaged<RustLibNipaplayPlugin>.fromOpaque(displayLinkContext).takeUnretainedValue()
    plugin.onDisplayLinkTick()
  }
  return kCVReturnSuccess
}

public final class RustLibNipaplayPlugin: NSObject, FlutterPlugin {
  private static let channelName = "nipaplay/next2_texture"
  private static var didRegister = false

  private let textureRegistry: FlutterTextureRegistry
  private let stateLock = NSLock()
  private var surfaces: [String: Next2SurfaceState] = [:]
  private var displayLink: CVDisplayLink?
  private let initQueue = DispatchQueue(label: "nipaplay.next2.engine-init", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    if didRegister {
      return
    }
    didRegister = true

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
    let instance = RustLibNipaplayPlugin(textureRegistry: registrar.textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.startDisplayLink()
  }

  private init(textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    super.init()
  }

  deinit {
    if let displayLink {
      CVDisplayLinkStop(displayLink)
    }

    var handlesToDispose: [UInt64] = []
    var texturesToUnregister: [Int64] = []

    stateLock.lock()
    for entry in surfaces.values {
      if entry.engineHandle != 0 {
        handlesToDispose.append(entry.engineHandle)
      }
      if let id = entry.textureId {
        texturesToUnregister.append(id)
      }
    }
    surfaces.removeAll()
    stateLock.unlock()

    for textureId in texturesToUnregister {
      textureRegistry.unregisterTexture(textureId)
    }
    for handle in handlesToDispose {
      next2_engine_dispose(handle)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getTextureInfo":
      let requested = parseRequestedTextureInfo(arguments: call.arguments)
      getTextureInfo(surfaceId: requested.surfaceId, width: requested.width, height: requested.height, result: result)
    case "disposeTexture":
      let surfaceId = parseSurfaceId(arguments: call.arguments)
      disposeSurface(surfaceId: surfaceId, result: result)
    case "setFrame":
      setFrame(arguments: call.arguments, result: result)
    case "resetScene":
      resetScene(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func parseRequestedTextureInfo(arguments: Any?) -> (surfaceId: String, width: Int, height: Int) {
    let fallbackWidth = 512
    let fallbackHeight = 512
    let fallbackSurfaceId = "default"

    guard let dict = arguments as? [String: Any] else {
      return (fallbackSurfaceId, fallbackWidth, fallbackHeight)
    }

    let w = (dict["width"] as? NSNumber)?.intValue ?? fallbackWidth
    let h = (dict["height"] as? NSNumber)?.intValue ?? fallbackHeight
    let surfaceIdValue = dict["surfaceId"]

    let surfaceId: String
    if let str = surfaceIdValue as? String, !str.isEmpty {
      surfaceId = str
    } else if let num = surfaceIdValue as? NSNumber {
      surfaceId = num.stringValue
    } else {
      surfaceId = fallbackSurfaceId
    }

    return (surfaceId, max(1, min(w, 16384)), max(1, min(h, 16384)))
  }

  private func parseSurfaceId(arguments: Any?) -> String {
    let fallbackSurfaceId = "default"
    guard let dict = arguments as? [String: Any] else {
      return fallbackSurfaceId
    }
    let surfaceIdValue = dict["surfaceId"]
    if let str = surfaceIdValue as? String, !str.isEmpty {
      return str
    }
    if let num = surfaceIdValue as? NSNumber {
      return num.stringValue
    }
    return fallbackSurfaceId
  }

  private func parseEngineHandle(arguments: Any?) -> UInt64? {
    guard let dict = arguments as? [String: Any] else {
      return nil
    }

    if let raw = dict["engineHandle"] as? NSNumber {
      return raw.uint64Value
    }

    if let str = dict["engineHandle"] as? String, let parsed = UInt64(str) {
      return parsed
    }

    return nil
  }

  private func getTextureInfo(
    surfaceId: String,
    width: Int,
    height: Int,
    result: @escaping FlutterResult
  ) {
    stateLock.lock()
    let entry: Next2SurfaceState
    if let existing = surfaces[surfaceId] {
      entry = existing
    } else {
      let created = Next2SurfaceState(surfaceId: surfaceId, width: width, height: height)
      surfaces[surfaceId] = created
      entry = created
    }

    let hasMatchingEngine = entry.engineHandle != 0 && entry.textureWidth == width && entry.textureHeight == height
    if hasMatchingEngine, let textureId = entry.textureId {
      let currentHandle = entry.engineHandle
      stateLock.unlock()
      result([
        "textureId": textureId,
        "engineHandle": NSNumber(value: currentHandle),
        "width": width,
        "height": height,
        "isNewEngine": false,
      ])
      return
    }

    if entry.initInProgress {
      entry.pendingTextureInfoResults.append(result)
      stateLock.unlock()
      return
    }

    entry.initInProgress = true
    entry.pendingTextureInfoResults.append(result)

    let handleToReuse = entry.engineHandle
    let oldTextureId = entry.textureId
    let needsResize = entry.textureWidth != width || entry.textureHeight != height
    let recreateTexture = needsResize
    let oldTexture = entry.texture

    entry.engineHandle = 0
    entry.textureId = nil
    entry.presentTexture = nil
    stateLock.unlock()

    initQueue.async { [weak self] in
      guard let self else {
        return
      }

      let targetTexture = recreateTexture ? Next2Texture(width: width, height: height) : oldTexture
      let resolvedWidth = CVPixelBufferGetWidth(targetTexture.pixelBuffer)
      let resolvedHeight = CVPixelBufferGetHeight(targetTexture.pixelBuffer)
      let bytesPerRow = CVPixelBufferGetBytesPerRow(targetTexture.pixelBuffer)

      var handle = handleToReuse
      var engineCreated = false

      if handle == 0 {
        handle = next2_engine_create(UInt32(resolvedWidth), UInt32(resolvedHeight))
        engineCreated = true
      } else if needsResize {
        let resizeOk = next2_engine_resize(handle, UInt32(resolvedWidth), UInt32(resolvedHeight)) != 0
        if !resizeOk {
          next2_engine_dispose(handle)
          handle = next2_engine_create(UInt32(resolvedWidth), UInt32(resolvedHeight))
          engineCreated = true
        }
      }

      guard handle != 0 else {
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(code: "engine_create_failed", message: "next2_engine_create returned 0", details: nil)
          )
        }
        return
      }

      guard let devicePtr = next2_engine_get_mtl_device(handle) else {
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "engine_get_mtl_device_failed",
              message: "next2_engine_get_mtl_device returned null",
              details: nil
            )
          )
        }
        return
      }

      let mtlDevice = Unmanaged<AnyObject>.fromOpaque(devicePtr).takeUnretainedValue() as! MTLDevice

      var cache: CVMetalTextureCache?
      let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, mtlDevice, nil, &cache)
      guard cacheStatus == kCVReturnSuccess, let resolvedCache = cache else {
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_cache_failed",
              message: "CVMetalTextureCacheCreate failed: \(cacheStatus)",
              details: nil
            )
          )
        }
        return
      }

      var cvTexture: CVMetalTexture?
      let textureAttributes: [CFString: Any] = [
        kCVMetalTextureUsage: NSNumber(
          value: MTLTextureUsage.shaderRead.rawValue
            | MTLTextureUsage.shaderWrite.rawValue
            | MTLTextureUsage.renderTarget.rawValue
        )
      ]

      let texStatus = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        resolvedCache,
        targetTexture.pixelBuffer,
        textureAttributes as CFDictionary,
        .bgra8Unorm,
        resolvedWidth,
        resolvedHeight,
        0,
        &cvTexture
      )

      guard texStatus == kCVReturnSuccess, let resolvedCvTexture = cvTexture else {
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_failed",
              message: "CVMetalTextureCacheCreateTextureFromImage failed: \(texStatus)",
              details: nil
            )
          )
        }
        return
      }

      guard let mtlTexture = CVMetalTextureGetTexture(resolvedCvTexture) else {
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_get_failed",
              message: "CVMetalTextureGetTexture returned null",
              details: nil
            )
          )
        }
        return
      }

      let texturePtr = Unmanaged.passRetained(mtlTexture as AnyObject).toOpaque()
      next2_engine_attach_present_texture(
        handle,
        texturePtr,
        UInt32(resolvedWidth),
        UInt32(resolvedHeight),
        UInt32(bytesPerRow)
      )

      DispatchQueue.main.async {
        self.stateLock.lock()
        guard let entry = self.surfaces[surfaceId] else {
          self.stateLock.unlock()
          self.initQueue.async {
            next2_engine_dispose(handle)
          }
          return
        }

        if let oldTextureId {
          self.textureRegistry.unregisterTexture(oldTextureId)
        }

        entry.texture = targetTexture
        entry.textureWidth = resolvedWidth
        entry.textureHeight = resolvedHeight
        let textureId = self.textureRegistry.register(entry.texture)
        entry.textureId = textureId
        entry.engineHandle = handle
        entry.textureCache = resolvedCache
        entry.presentTexture = resolvedCvTexture
        self.stateLock.unlock()

        self.completePendingTextureInfoRequests(surfaceId: surfaceId, response: [
          "textureId": textureId,
          "engineHandle": NSNumber(value: handle),
          "width": resolvedWidth,
          "height": resolvedHeight,
          "isNewEngine": engineCreated || needsResize,
        ])
      }
    }
  }

  private func setFrame(arguments: Any?, result: @escaping FlutterResult) {
    guard let dict = arguments as? [String: Any],
          let handle = parseEngineHandle(arguments: arguments),
          let frameJson = dict["frameJson"] as? String else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing engineHandle/frameJson",
          details: nil
        )
      )
      return
    }

    let fontSize = (dict["fontSize"] as? NSNumber)?.floatValue ?? 24.0
    let outlineWidth = (dict["outlineWidth"] as? NSNumber)?.floatValue ?? 1.0
    let shadowStyle = (dict["shadowStyle"] as? NSNumber)?.uint8Value ?? 1
    let opacity = (dict["opacity"] as? NSNumber)?.floatValue ?? 1.0
    let customFontFamily = (dict["customFontFamily"] as? String) ?? ""
    let customFontFilePath = (dict["customFontFilePath"] as? String) ?? ""

    let ok = frameJson.withCString { ptr in
      customFontFamily.withCString { familyPtr in
        customFontFilePath.withCString { filePtr in
          next2_engine_set_frame(handle, ptr, fontSize, outlineWidth, shadowStyle, opacity, familyPtr, filePtr) != 0
        }
      }
    }
    result(ok)
  }

  private func resetScene(arguments: Any?, result: @escaping FlutterResult) {
    guard let handle = parseEngineHandle(arguments: arguments) else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing engineHandle",
          details: nil
        )
      )
      return
    }
    let ok = next2_engine_reset_scene(handle) != 0
    result(ok)
  }

  private func disposeSurface(surfaceId: String, result: @escaping FlutterResult) {
    var removed: Next2SurfaceState?
    stateLock.lock()
    removed = surfaces.removeValue(forKey: surfaceId)
    stateLock.unlock()

    if let entry = removed {
      if let textureId = entry.textureId {
        textureRegistry.unregisterTexture(textureId)
      }
      if entry.engineHandle != 0 {
        initQueue.async {
          next2_engine_dispose(entry.engineHandle)
        }
      }

      for callback in entry.pendingTextureInfoResults {
        callback(
          FlutterError(
            code: "surface_disposed",
            message: "surface disposed",
            details: nil
          )
        )
      }
    }

    result(nil)
  }

  private func completePendingTextureInfoRequests(surfaceId: String, response: Any?) {
    stateLock.lock()
    guard let entry = surfaces[surfaceId] else {
      stateLock.unlock()
      return
    }
    let callbacks = entry.pendingTextureInfoResults
    entry.pendingTextureInfoResults.removeAll()
    entry.initInProgress = false
    stateLock.unlock()

    for callback in callbacks {
      callback(response)
    }
  }

  private func startDisplayLink() {
    var link: CVDisplayLink?
    let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard status == kCVReturnSuccess, let link else {
      return
    }

    displayLink = link
    CVDisplayLinkSetOutputCallback(
      link,
      next2DisplayLinkCallback,
      Unmanaged.passUnretained(self).toOpaque()
    )
    CVDisplayLinkStart(link)
  }

  fileprivate func onDisplayLinkTick() {
    var entries: [(UInt64, Int64)] = []
    stateLock.lock()
    for entry in surfaces.values {
      if entry.engineHandle != 0, let textureId = entry.textureId {
        entries.append((entry.engineHandle, textureId))
      }
    }
    stateLock.unlock()

    for (handle, textureId) in entries {
      let ready = next2_engine_poll_frame_ready(handle)
      if ready {
        if Thread.isMainThread {
          textureRegistry.textureFrameAvailable(textureId)
        } else {
          DispatchQueue.main.async { [textureRegistry] in
            textureRegistry.textureFrameAvailable(textureId)
          }
        }
      }
    }
  }
}
