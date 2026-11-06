import Flutter
import Foundation

/// Mesh itself is called from Dart worker isolates through the C ABI.
public final class RustLibNipaplayPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {}
}
