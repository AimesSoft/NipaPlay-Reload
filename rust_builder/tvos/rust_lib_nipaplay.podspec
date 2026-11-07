Pod::Spec.new do |s|
  s.name = 'rust_lib_nipaplay'
  s.version = '0.0.1'
  s.summary = 'NipaPlay tvOS authenticated Mesh transport.'
  s.description = 'The shared Mesh implementation without desktop-only dependencies.'
  s.homepage = 'https://github.com/MCJQD/NipaPlay-Reload'
  s.license = { :type => 'MIT' }
  s.author = { 'NipaPlay' => 'dev@aimesoft.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.platform = :tvos, '13.0'
  s.swift_version = '5.0'
  s.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"' }
  s.script_phase = {
    :name => 'Build television Mesh transport',
    :execution_position => :before_compile,
    :script => '"$PODS_TARGET_SRCROOT/build_mesh.sh"',
    :output_files => ['${BUILT_PRODUCTS_DIR}/libnipaplay_tvos_native.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${BUILT_PRODUCTS_DIR}/libnipaplay_tvos_native.a" -framework Security',
  }
end
