import AppKit
import CoreVideo
import OpenGL.GL
import OpenGL.GL3
import QuartzCore

private let macOSHdrExitTraceEnabled =
  ProcessInfo.processInfo.environment["NIPAPLAY_MACOS_HDR_EXIT_TRACE"] == "1"

private func macOSHdrExitTrace(_ message: String) {
  guard macOSHdrExitTraceEnabled else {
    return
  }
  NSLog("[HDRExit][Layer] %@", message)
}

private final class MediaKitOpenGLVideoLayerCallbackBox: NSObject {
  weak var layer: MediaKitOpenGLVideoLayer?
  var isActive = true

  init(layer: MediaKitOpenGLVideoLayer? = nil) {
    self.layer = layer
  }

  func invalidate() {
    isActive = false
    layer = nil
  }
}

private final class MediaKitOpenGLVideoLayerCallbackRetainer {
  static let shared = MediaKitOpenGLVideoLayerCallbackRetainer()

  private let queue = DispatchQueue(
    label: "com.aimessoft.nipaplay.mpvgl-callback-retainer"
  )
  private var nextToken: UInt64 = 0
  private var retained: [UInt64: AnyObject] = [:]

  func retainTemporarily(_ object: AnyObject, seconds: TimeInterval = 2.0) {
    queue.async {
      self.nextToken += 1
      let token = self.nextToken
      self.retained[token] = object
      self.queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
        self?.retained.removeValue(forKey: token)
      }
    }
  }
}

public final class MediaKitOpenGLVideoRenderer {
  public let layer: MediaKitOpenGLVideoLayer

  private weak var hostView: NSView?

  public init?(playerHandle: Int64, hostView: NSView) {
    guard let handle = OpaquePointer(bitPattern: Int(playerHandle)) else {
      return nil
    }

    self.hostView = hostView
    self.layer = MediaKitOpenGLVideoLayer(handle: handle, hostView: hostView)
    attach(to: hostView)
  }

  deinit {
    macOSHdrExitTrace("renderer deinit hostView=\(String(describing: hostView))")
    detach()
  }

  public func attach(to hostView: NSView) {
    macOSHdrExitTrace("renderer attach hostView=\(hostView)")
    self.hostView = hostView
    hostView.wantsLayer = true
    hostView.wantsBestResolutionOpenGLSurface = true
    hostView.wantsExtendedDynamicRangeOpenGLSurface = true
    hostView.layer = layer
    hostView.layerContentsRedrawPolicy = .duringViewResize
    layer.frame = hostView.bounds
    layer.hostViewDidChange()
  }

  public func detach() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.detach()
      }
      return
    }
    macOSHdrExitTrace("renderer detach hostView=\(String(describing: hostView))")
    layer.invalidate()
    if hostView?.layer === layer {
      hostView?.layer = nil
    }
    hostView = nil
  }

  public func hostViewDidChange() {
    layer.hostViewDidChange()
  }
}

public final class MediaKitOpenGLVideoLayer: CAOpenGLLayer {
  private let handle: OpaquePointer
  private weak var hostView: NSView?
  private let cglPixelFormat: CGLPixelFormatObj
  private let cglContext: CGLContextObj
  private let ownsRenderingResources: Bool
  private let renderUpdateCallbackBox: MediaKitOpenGLVideoLayerCallbackBox
  private let displayLinkCallbackBox: MediaKitOpenGLVideoLayerCallbackBox
  private let renderQueue = DispatchQueue(
    label: "com.aimessoft.nipaplay.mpvgl-layer",
    qos: .userInteractive
  )
  private let displayLock = NSRecursiveLock()

  private var renderContext: OpaquePointer?
  private var isInvalidated = false
  private var needsRender = false
  private var forceRender = false
  private var pendingRenderUpdateFlags: UInt64 = 0
  private var fbo: GLint = 1
  private var bufferDepth: GLint = 16
  private var displayLink: CVDisplayLink?
  private var displayLinkDisplayId: UInt32?
  private var lastOutputConfigurationKey: String?
  private var lastOutputConfigurationTime: CFTimeInterval = 0
  private var lastLoggedHDRConfigurationKey: String?
  private var nextOutputConfigurationRefreshTime: CFTimeInterval = 0
  private var renderedFrameCount = 0
  private var lastRenderedFrameLogTime: CFTimeInterval = 0
  private var consecutiveBlackFramebufferFrames = 0
  private var lastBlackFramebufferLogTime: CFTimeInterval = 0
  private let shouldLogRenderFPS =
    ProcessInfo.processInfo.environment["NIPAPLAY_MACOS_HDR_RENDER_FPS"] == "1"
  private let shouldLogBlackFramebufferFrames =
    ProcessInfo.processInfo.environment["NIPAPLAY_MACOS_HDR_GL_BLACK_FRAME_LOG"] == "1"

  init(handle: OpaquePointer, hostView: NSView) {
    self.handle = handle
    self.hostView = hostView
    self.cglPixelFormat = OpenGLHelpers.createPixelFormat()
    self.cglContext = OpenGLHelpers.createContext(cglPixelFormat)
    self.ownsRenderingResources = true
    self.renderUpdateCallbackBox = MediaKitOpenGLVideoLayerCallbackBox()
    self.displayLinkCallbackBox = MediaKitOpenGLVideoLayerCallbackBox()
    super.init()
    renderUpdateCallbackBox.layer = self
    displayLinkCallbackBox.layer = self

    configureOpenGLContext()

    autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    backgroundColor = NSColor.black.cgColor
    contentsFormat = .RGBA16Float
    isOpaque = true
    isAsynchronous = false

    if #available(macOS 10.15, *) {
      wantsExtendedDynamicRangeContent = false
    }

    initMPV()
    hostViewDidChange()
  }

  override public init(layer: Any) {
    let oldLayer = layer as! MediaKitOpenGLVideoLayer
    self.handle = oldLayer.handle
    self.hostView = oldLayer.hostView
    self.cglPixelFormat = oldLayer.cglPixelFormat
    self.cglContext = oldLayer.cglContext
    self.ownsRenderingResources = false
    self.renderUpdateCallbackBox = oldLayer.renderUpdateCallbackBox
    self.displayLinkCallbackBox = oldLayer.displayLinkCallbackBox
    self.renderContext = oldLayer.renderContext
    self.fbo = oldLayer.fbo
    self.bufferDepth = oldLayer.bufferDepth
    self.pendingRenderUpdateFlags = oldLayer.pendingRenderUpdateFlags
    self.displayLinkDisplayId = oldLayer.displayLinkDisplayId
    self.lastOutputConfigurationKey = oldLayer.lastOutputConfigurationKey
    self.lastOutputConfigurationTime = oldLayer.lastOutputConfigurationTime
    self.lastLoggedHDRConfigurationKey = oldLayer.lastLoggedHDRConfigurationKey
    self.nextOutputConfigurationRefreshTime = oldLayer.nextOutputConfigurationRefreshTime
    self.consecutiveBlackFramebufferFrames = oldLayer.consecutiveBlackFramebufferFrames
    self.lastBlackFramebufferLogTime = oldLayer.lastBlackFramebufferLogTime
    super.init(layer: layer)
    contentsFormat = oldLayer.contentsFormat
    colorspace = oldLayer.colorspace
    if #available(macOS 10.15, *) {
      wantsExtendedDynamicRangeContent = oldLayer.wantsExtendedDynamicRangeContent
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    guard ownsRenderingResources else {
      return
    }
    macOSHdrExitTrace("layer deinit invalidated=\(isInvalidated)")
    invalidate()
    OpenGLHelpers.deletePixelFormat(cglPixelFormat)
    OpenGLHelpers.deleteContext(cglContext)
  }

  public func invalidate() {
    guard ownsRenderingResources else {
      isInvalidated = true
      return
    }
    guard !isInvalidated else {
      return
    }
    macOSHdrExitTrace("layer invalidate start renderContextPresent=\(renderContext != nil)")
    isInvalidated = true
    renderUpdateCallbackBox.invalidate()
    displayLinkCallbackBox.invalidate()
    MediaKitOpenGLVideoLayerCallbackRetainer.shared.retainTemporarily(
      renderUpdateCallbackBox
    )
    MediaKitOpenGLVideoLayerCallbackRetainer.shared.retainTemporarily(
      displayLinkCallbackBox
    )
    stopDisplayLink()
    displayLock.lock()
    defer {
      displayLock.unlock()
    }
    CGLLockContext(cglContext)
    CGLSetCurrentContext(cglContext)
    defer {
      OpenGLHelpers.checkError("MediaKitOpenGLVideoLayer.invalidate")
      CGLSetCurrentContext(nil)
      CGLUnlockContext(cglContext)
    }
    if let renderContext {
      mpv_render_context_set_update_callback(renderContext, nil, nil)
      mpv_render_context_free(renderContext)
      self.renderContext = nil
    }
    macOSHdrExitTrace("layer invalidate end")
  }

  public func hostViewDidChange() {
    guard !isInvalidated else {
      return
    }
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.hostViewDidChange()
      }
      return
    }
    frame = hostView?.bounds ?? frame
    contentsScale = hostView?.window?.backingScaleFactor ??
      hostView?.window?.screen?.backingScaleFactor ??
      NSScreen.main?.backingScaleFactor ??
      1
    updateDisplayLink()
    refreshOutputConfiguration(force: true)
    requestRender(force: true)
  }

  override public func canDraw(
    inCGLContext ctx: CGLContextObj,
    pixelFormat pf: CGLPixelFormatObj,
    forLayerTime t: CFTimeInterval,
    displayTime ts: UnsafePointer<CVTimeStamp>?
  ) -> Bool {
    guard !isInvalidated else {
      return false
    }
    guard needsRender || forceRender, let renderContext else {
      return false
    }

    pendingRenderUpdateFlags = mpv_render_context_update(renderContext)
    if forceRender {
      return true
    }
    return pendingRenderUpdateFlags &
      UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
  }

  override public func draw(
    inCGLContext ctx: CGLContextObj,
    pixelFormat pf: CGLPixelFormatObj,
    forLayerTime t: CFTimeInterval,
    displayTime ts: UnsafePointer<CVTimeStamp>?
  ) {
    guard !isInvalidated else {
      return
    }

    needsRender = false
    forceRender = false

    var currentFbo: GLint = 0
    glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &currentFbo)
    if currentFbo != 0 {
      fbo = currentFbo
    }

    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
    guard viewport[2] > 0, viewport[3] > 0, let renderContext else {
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
      glFlush()
      return
    }

    var openGLFbo = mpv_opengl_fbo(
      fbo: Int32(fbo),
      w: Int32(viewport[2]),
      h: Int32(viewport[3]),
      internal_format: 0
    )
    var flipY: CInt = 1
    var depth = bufferDepth

    withUnsafeMutablePointer(to: &openGLFbo) { openGLFboPtr in
      withUnsafeMutablePointer(to: &flipY) { flipYPtr in
        withUnsafeMutablePointer(to: &depth) { depthPtr in
          var params: [mpv_render_param] = [
            mpv_render_param(
              type: MPV_RENDER_PARAM_OPENGL_FBO,
              data: UnsafeMutableRawPointer(openGLFboPtr)
            ),
            mpv_render_param(
              type: MPV_RENDER_PARAM_FLIP_Y,
              data: UnsafeMutableRawPointer(flipYPtr)
            ),
            mpv_render_param(
              type: MPV_RENDER_PARAM_DEPTH,
              data: UnsafeMutableRawPointer(depthPtr)
            ),
            mpv_render_param(),
          ]
          mpv_render_context_render(renderContext, &params)
        }
      }
    }

    logBlackFramebufferFrameIfNeeded(viewport: viewport)
    glFlush()
    pendingRenderUpdateFlags = 0
    logRenderedFrameIfNeeded()
  }

  override public func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
    return cglPixelFormat
  }

  override public func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
    return cglContext
  }

  override public func display() {
    displayLock.lock()
    defer {
      displayLock.unlock()
    }

    let isUpdate = needsRender

    if Thread.isMainThread {
      super.display()
    } else {
      CATransaction.begin()
      super.display()
      CATransaction.commit()
    }
    CATransaction.flush()

    guard isUpdate && needsRender, let renderContext else {
      return
    }

    CGLLockContext(cglContext)
    CGLSetCurrentContext(cglContext)
    defer {
      OpenGLHelpers.checkError("MediaKitOpenGLVideoLayer.display.skipRender")
      CGLSetCurrentContext(nil)
      CGLUnlockContext(cglContext)
    }

    let updateFlags = mpv_render_context_update(renderContext)
    guard updateFlags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0 else {
      return
    }

    var skip: CInt = 1
    withUnsafeMutablePointer(to: &skip) { skipPtr in
      var params: [mpv_render_param] = [
        mpv_render_param(
          type: MPV_RENDER_PARAM_SKIP_RENDERING,
          data: UnsafeMutableRawPointer(skipPtr)
        ),
        mpv_render_param(),
      ]
      mpv_render_context_render(renderContext, &params)
    }
  }

  private func initMPV() {
    guard ownsRenderingResources else {
      return
    }
    CGLLockContext(cglContext)
    CGLSetCurrentContext(cglContext)
    defer {
      OpenGLHelpers.checkError("MediaKitOpenGLVideoLayer.initMPV")
      CGLSetCurrentContext(nil)
      CGLUnlockContext(cglContext)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    var initParams = mpv_opengl_init_params(
      get_proc_address: { _, name in
        MediaKitOpenGLVideoLayer.getProcAddress(name)
      },
      get_proc_address_ctx: nil
    )

    withUnsafeMutablePointer(to: &initParams) { initParamsPtr in
      var advanced: CInt = 1
      withUnsafeMutablePointer(to: &advanced) { advancedPtr in
        var params: [mpv_render_param] = [
          mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
          mpv_render_param(
            type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
            data: UnsafeMutableRawPointer(initParamsPtr)
          ),
          mpv_render_param(
            type: MPV_RENDER_PARAM_ADVANCED_CONTROL,
            data: UnsafeMutableRawPointer(advancedPtr)
          ),
          mpv_render_param(),
        ]
        MPVHelpers.checkError(
          mpv_render_context_create(&renderContext, handle, &params)
        )
      }
    }

    mpv_render_context_set_update_callback(
      renderContext,
      { context in
        guard let context else {
          return
        }
        let callbackBox = Unmanaged<MediaKitOpenGLVideoLayerCallbackBox>
          .fromOpaque(context)
          .takeUnretainedValue()
        guard callbackBox.isActive, let layer = callbackBox.layer else {
          return
        }
        layer.requestRender()
      },
      UnsafeMutableRawPointer(
        Unmanaged.passUnretained(renderUpdateCallbackBox).toOpaque()
      )
    )
  }

  private func requestRender(force: Bool = false) {
    scheduleOutputConfigurationRefresh(force: force)
    renderQueue.async { [weak self] in
      guard let self, !self.isInvalidated else {
        return
      }
      if force {
        self.forceRender = true
      }
      self.needsRender = true
      self.display()
    }
  }

  private func configureOpenGLContext() {
    var swapInterval: GLint = 1
    CGLSetParameter(cglContext, kCGLCPSwapInterval, &swapInterval)
    CGLEnable(cglContext, kCGLCEMPEngine)
  }

  private func updateDisplayLink() {
    guard ownsRenderingResources, !isInvalidated else {
      return
    }
    guard let screen = hostView?.window?.screen ?? NSScreen.main else {
      return
    }
    guard let displayId = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? UInt32 else {
      return
    }

    if displayLink == nil {
      var link: CVDisplayLink?
      let createResult = CVDisplayLinkCreateWithActiveCGDisplays(&link)
      guard createResult == kCVReturnSuccess, let createdLink = link else {
        NSLog(
          "MediaKitOpenGLVideoLayer: CVDisplayLinkCreateWithActiveCGDisplays failed \(createResult)"
        )
        return
      }
      CVDisplayLinkSetOutputCallback(
        createdLink,
        MediaKitOpenGLVideoLayer.displayLinkCallback,
        UnsafeMutableRawPointer(
          Unmanaged.passUnretained(displayLinkCallbackBox).toOpaque()
        )
      )
      displayLink = createdLink
    }

    guard let link = displayLink else {
      return
    }

    if displayLinkDisplayId != displayId {
      let result = CVDisplayLinkSetCurrentCGDisplay(link, displayId)
      if result != kCVReturnSuccess {
        NSLog(
          "MediaKitOpenGLVideoLayer: CVDisplayLinkSetCurrentCGDisplay failed \(result)"
        )
      }
      displayLinkDisplayId = displayId
      let fps = displayRefreshRate(for: link)
      _ = setPropertyDouble("display-fps-override", fps)
      NSLog(
        "MediaKitOpenGLVideoLayer: display link active display=\(displayId) fps=\(String(format: "%.2f", fps))"
      )
    }

    if !CVDisplayLinkIsRunning(link) {
      let result = CVDisplayLinkStart(link)
      if result != kCVReturnSuccess {
        NSLog("MediaKitOpenGLVideoLayer: CVDisplayLinkStart failed \(result)")
      }
    }
  }

  private func stopDisplayLink() {
    guard let link = displayLink else {
      return
    }
    if CVDisplayLinkIsRunning(link) {
      let result = CVDisplayLinkStop(link)
      if result != kCVReturnSuccess {
        NSLog("MediaKitOpenGLVideoLayer: CVDisplayLinkStop failed \(result)")
      }
    }
    displayLink = nil
    displayLinkDisplayId = nil
  }

  private func displayRefreshRate(for link: CVDisplayLink) -> Double {
    let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
    let actualPeriod = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
    var actualFps = actualPeriod > 0 ? 1 / actualPeriod : 0

    if (nominal.flags & Int32(CVTimeFlags.isIndefinite.rawValue)) == 0,
       nominal.timeValue > 0 {
      let nominalFps = Double(nominal.timeScale) / Double(nominal.timeValue)
      if actualFps <= 1 || abs(actualFps - nominalFps) > 1 {
        actualFps = nominalFps
      }
    }

    if actualFps <= 1 {
      actualFps = 60
    }
    return actualFps
  }

  private func reportSwapFromDisplayLink() {
    guard ownsRenderingResources, !isInvalidated, let renderContext else {
      return
    }
    displayLock.lock()
    defer {
      displayLock.unlock()
    }
    guard !isInvalidated else {
      return
    }
    mpv_render_context_report_swap(renderContext)
  }

  private func scheduleOutputConfigurationRefresh(force: Bool) {
    let now = CACurrentMediaTime()
    guard force ||
      lastOutputConfigurationKey == nil ||
      now >= nextOutputConfigurationRefreshTime else {
      return
    }
    nextOutputConfigurationRefreshTime = now + 1
    DispatchQueue.main.async { [weak self] in
      self?.refreshOutputConfiguration(force: force)
    }
  }

  private func logRenderedFrameIfNeeded() {
    guard shouldLogRenderFPS else {
      return
    }
    renderedFrameCount += 1
    let now = CACurrentMediaTime()
    if lastRenderedFrameLogTime == 0 {
      lastRenderedFrameLogTime = now
      return
    }
    let elapsed = now - lastRenderedFrameLogTime
    guard elapsed >= 1 else {
      return
    }
    let fps = Double(renderedFrameCount) / elapsed
    renderedFrameCount = 0
    lastRenderedFrameLogTime = now
    NSLog(
      "MediaKitOpenGLVideoLayer: rendered fps=\(String(format: "%.2f", fps))"
    )
  }

  private func logBlackFramebufferFrameIfNeeded(viewport: [GLint]) {
    guard shouldLogBlackFramebufferFrames, viewport.count >= 4 else {
      return
    }
    let width = viewport[2]
    let height = viewport[3]
    guard width > 0, height > 0 else {
      return
    }

    let samplePoints: [(GLint, GLint)] = [
      (viewport[0] + width / 2, viewport[1] + height / 2),
      (viewport[0] + width / 4, viewport[1] + height / 4),
      (viewport[0] + (width * 3) / 4, viewport[1] + height / 4),
      (viewport[0] + width / 4, viewport[1] + (height * 3) / 4),
      (viewport[0] + (width * 3) / 4, viewport[1] + (height * 3) / 4),
    ]

    var previousReadFbo: GLint = 0
    glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &previousReadFbo)
    if fbo != 0 {
      glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(fbo))
    }
    defer {
      glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(previousReadFbo))
    }

    var maxComponent: GLfloat = 0
    var sumLuminance: GLfloat = 0
    for point in samplePoints {
      var pixel = [GLfloat](repeating: 0, count: 4)
      glReadPixels(
        point.0,
        point.1,
        1,
        1,
        GLenum(GL_RGBA),
        GLenum(GL_FLOAT),
        &pixel
      )
      maxComponent = max(maxComponent, pixel[0], pixel[1], pixel[2])
      sumLuminance += 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]
    }

    let meanLuminance = sumLuminance / GLfloat(samplePoints.count)
    let isBlack = maxComponent < 0.01 && meanLuminance < 0.005
    if isBlack {
      consecutiveBlackFramebufferFrames += 1
      let now = CACurrentMediaTime()
      if now - lastBlackFramebufferLogTime > 0.25 {
        lastBlackFramebufferLogTime = now
        NSLog(
          "MediaKitOpenGLVideoLayer: framebuffer black sample run=\(consecutiveBlackFramebufferFrames) mean=\(String(format: "%.5f", meanLuminance)) max=\(String(format: "%.5f", maxComponent)) viewport=\(width)x\(height)"
        )
      }
    } else if consecutiveBlackFramebufferFrames > 0 {
      NSLog(
        "MediaKitOpenGLVideoLayer: framebuffer recovered after black run=\(consecutiveBlackFramebufferFrames) mean=\(String(format: "%.5f", meanLuminance)) max=\(String(format: "%.5f", maxComponent))"
      )
      consecutiveBlackFramebufferFrames = 0
    }
  }

  private static let displayLinkCallback: CVDisplayLinkOutputCallback = {
    _, _, _, _, _, context in
    guard let context else {
      return kCVReturnSuccess
    }
    let callbackBox = Unmanaged<MediaKitOpenGLVideoLayerCallbackBox>
      .fromOpaque(context)
      .takeUnretainedValue()
    guard callbackBox.isActive, let layer = callbackBox.layer else {
      return kCVReturnSuccess
    }
    layer.reportSwapFromDisplayLink()
    return kCVReturnSuccess
  }

  private func refreshOutputConfiguration(force: Bool) {
    let now = CACurrentMediaTime()
    if !force && now - lastOutputConfigurationTime < 0.25 {
      return
    }
    lastOutputConfigurationTime = now

    let screen = hostView?.window?.screen
    let gamma = getPropertyString("video-params/gamma") ?? ""
    let primaries = getPropertyString("video-params/primaries") ?? ""
    let displayId = screen?.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? UInt32
    let configurationKey = "\(displayId ?? 0)|\(gamma)|\(primaries)"

    if configurationKey == lastOutputConfigurationKey {
      return
    }
    lastOutputConfigurationKey = configurationKey

    let isHDRVideo = gamma == "pq" || gamma == "hlg"
    let supportsEDR: Bool
    if #available(macOS 10.15, *) {
      supportsEDR =
        (screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0
    } else {
      supportsEDR = false
    }

    guard isHDRVideo, supportsEDR, let hdrColorSpace = hdrColorSpace(for: primaries) else {
      if #available(macOS 10.15, *) {
        wantsExtendedDynamicRangeContent = false
      }
      colorspace = screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
      _ = setPropertyString("target-prim", "auto")
      _ = setPropertyString("target-trc", "auto")
      _ = setPropertyString("target-peak", "auto")
      return
    }

    if #available(macOS 10.15, *) {
      wantsExtendedDynamicRangeContent = true
    }
    colorspace = hdrColorSpace
    contentsFormat = .RGBA16Float

    _ = setPropertyString("icc-profile-auto", "no")
    _ = setPropertyString("target-prim", primaries)
    _ = setPropertyString("target-trc", "pq")
    _ = setPropertyString("target-peak", "auto")
    _ = setPropertyString("tone-mapping", "")
    if lastLoggedHDRConfigurationKey != configurationKey {
      lastLoggedHDRConfigurationKey = configurationKey
      NSLog(
        "MediaKitOpenGLVideoLayer: HDR output active gamma=\(gamma) primaries=\(primaries) screen=\(screen?.localizedName ?? "nil")"
      )
    }
  }

  private func hdrColorSpace(for primaries: String) -> CGColorSpace? {
    switch primaries {
    case "display-p3":
      if #available(macOS 10.15.4, *) {
        return CGColorSpace(name: CGColorSpace.displayP3_PQ)
      }
      return CGColorSpace(name: CGColorSpace.displayP3_PQ_EOTF)
    case "bt.2020":
      if #available(macOS 11.0, *) {
        return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
      }
      if #available(macOS 10.15.4, *) {
        return CGColorSpace(name: CGColorSpace.itur_2020_PQ)
      }
      return CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
    default:
      return nil
    }
  }

  private func getPropertyString(_ name: String) -> String? {
    return name.withCString { namePtr in
      guard let value = mpv_get_property_string(handle, namePtr) else {
        return nil
      }
      defer {
        mpv_free(UnsafeMutableRawPointer(value))
      }
      return String(cString: value)
    }
  }

  @discardableResult
  private func setPropertyString(_ name: String, _ value: String) -> CInt {
    return name.withCString { namePtr in
      value.withCString { valuePtr in
        mpv_set_property_string(handle, namePtr, valuePtr)
      }
    }
  }

  @discardableResult
  private func setPropertyDouble(_ name: String, _ value: Double) -> CInt {
    var value = value
    return name.withCString { namePtr in
      mpv_set_property(handle, namePtr, MPV_FORMAT_DOUBLE, &value)
    }
  }

  private static func getProcAddress(_ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
    guard let name else {
      return nil
    }
    let symbol = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
    let address = CFBundleGetFunctionPointerForName(bundle, symbol)
    if address == nil {
      NSLog("MediaKitOpenGLVideoLayer: cannot resolve OpenGL symbol")
    }
    return address
  }
}
