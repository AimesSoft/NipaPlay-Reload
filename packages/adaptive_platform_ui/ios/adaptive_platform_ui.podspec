#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint adaptive_platform_ui.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'adaptive_platform_ui'
  s.version          = '0.1.0'
  s.summary          = 'Adaptive platform-specific widgets for Flutter with iOS 26 native support.'
  s.description      = <<-DESC
A Flutter package that provides adaptive platform-specific widgets with native iOS 26+ designs,
traditional Cupertino widgets for older iOS versions, and Material Design for Android.
                       DESC
  s.homepage         = 'https://github.com/berkaycatak/adaptive_platform_ui'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Berkay Catak' => 'berkaycatak@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
