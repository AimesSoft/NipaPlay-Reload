#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public protocol ResizableTextureProtocol: NSObject, FlutterTexture {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
  // Frees the mpv render context; later renders draw nothing. mpv aborts
  // when its core is destroyed while a render context is still alive.
  func dispose()
}
