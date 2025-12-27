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
  # paths, so Classes contains forwarder C files that relatively import
  # `../src/*` and third-party sources.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_CONFIG_H=1 _U_=__attribute__((unused))',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include/smb2" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/include/apple" "${PODS_TARGET_SRCROOT}/../third_party/libsmb2/lib"',
  }
  s.swift_version = '5.0'
end

