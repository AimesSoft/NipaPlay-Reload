Pod::Spec.new do |s|
  s.name = 'adaptive_platform_ui'
  s.version = '0.1.98'
  s.summary = 'Native Apple media controls.'
  s.description = 'Native AppKit Liquid Glass media detail controls with runtime availability checks.'
  s.homepage = 'https://github.com/berkaycatak/adaptive_platform_ui'
  s.license = { :file => '../LICENSE' }
  s.author = { 'NipaPlay' => 'nipaplay@example.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.swift_version = '5.0'
end
