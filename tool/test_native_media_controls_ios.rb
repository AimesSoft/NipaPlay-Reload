#!/usr/bin/env ruby
# Isolated UIKit tests against the real plugin source, without building the
# media engine or modifying the app's Pods / Xcode project.
require 'tmpdir'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
sdk = ENV.fetch('FLUTTER_ROOT', File.join(root, '.dart_tool/ios-flutter-sdk'))
frameworks = File.join(sdk, 'bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator')
destination = ENV.fetch('IOS_TEST_DESTINATION', 'platform=iOS Simulator,name=iPhone 17 Pro')

Dir.mktmpdir('nipaplay-ios-media-tests.') do |dir|
  project = Xcodeproj::Project.new(File.join(dir, 'MediaControls.xcodeproj'))
  # UIButton dispatch uses UIApplication. A host-less logic-test bundle would
  # silently skip target actions even though configuration checks pass.
  host_source = File.join(dir, 'Host.swift')
  File.write(host_source, <<~SWIFT)
    import UIKit
    @main final class TestHost: UIResponder, UIApplicationDelegate {
      var window: UIWindow?
      func application(_ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
      }
    }
  SWIFT
  host = project.new_target(:application, 'MediaControlHost', :ios, '15.0')
  host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))
  host.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.nipaplay.native-media-test-host',
      'CODE_SIGNING_ALLOWED' => 'NO', 'SUPPORTED_PLATFORMS' => 'iphonesimulator',
      'TARGETED_DEVICE_FAMILY' => '1,2'
    })
  end
  target = project.new_target(:unit_test_bundle, 'MediaControls', :ios, '15.0')
  target.add_dependency(host)
  %w[Classes/MediaDetailControl.swift Tests/MediaDetailControlTests.swift].each do |file|
    ref = project.main_group.new_file(File.join(root, 'packages/adaptive_platform_ui/ios', file))
    target.source_build_phase.add_file_reference(ref)
  end
  flutter = project.main_group.new_file(File.join(frameworks, 'Flutter.framework'))
  target.frameworks_build_phase.add_file_reference(flutter)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.nipaplay.native-media-tests',
      'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', frameworks],
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', frameworks],
      'CODE_SIGNING_ALLOWED' => 'NO',
      'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/MediaControlHost.app/MediaControlHost',
      'BUNDLE_LOADER' => '$(TEST_HOST)',
      'SUPPORTED_PLATFORMS' => 'iphonesimulator',
      'TARGETED_DEVICE_FAMILY' => '1,2'
    })
  end
  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(host)
  scheme.add_build_target(target)
  scheme.add_test_target(target)
  scheme.save_as(project.path, 'MediaControls', true)
  ok = system('xcodebuild', 'test', '-project', project.path.to_s,
              '-scheme', 'MediaControls', '-sdk', 'iphonesimulator',
              '-destination', destination, '-derivedDataPath', File.join(dir, 'build'),
              '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO')
  exit 1 unless ok
end
