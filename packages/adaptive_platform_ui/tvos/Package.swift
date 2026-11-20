// swift-tools-version: 5.9
import PackageDescription

// flutter-tvos supplies the Flutter module through FlutterFramework in its
// generated FlutterGeneratedPluginSwiftPackage umbrella. The CocoaPods Flutter
// pod is iOS-only and must not be used as a tvOS engine dependency.
let package = Package(
    name: "adaptive_platform_ui",
    platforms: [.tvOS("13.0")],
    products: [
        .library(name: "adaptive-platform-ui", targets: ["adaptive_platform_ui"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "adaptive_platform_ui", path: "Classes"),
    ]
)
