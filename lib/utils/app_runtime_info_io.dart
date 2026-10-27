import 'dart:ffi';
import 'dart:io';

Map<String, String> runtimeBuildInfo() => {
  'os': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'abi': Abi.current().toString(),
  'dart': Platform.version.split(' ').first,
};
