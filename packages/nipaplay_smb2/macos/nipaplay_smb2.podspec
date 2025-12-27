#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint nipaplay_smb2.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'nipaplay_smb2'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  # NOTE: `source_files` globs are resolved relative to this `.podspec` folder
  # (`.../nipaplay_smb2/macos`). Keep paths platform-folder relative so CocoaPods
  # actually picks up and compiles the C sources into `nipaplay_smb2.framework`.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'nipaplay_smb2_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_CONFIG_H=1 _U_=__attribute__((unused))',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include/smb2" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include/apple" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/lib"',
  }
  s.swift_version = '5.0'
end
