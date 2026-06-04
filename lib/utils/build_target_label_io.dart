import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'build_target_label_common.dart';

String getBuildTargetLabel() {
  final abi = ffi.Abi.current().toString().split('.').last;
  return buildTargetLabelFromParts(
    architecture: abi,
    platform: Platform.operatingSystem,
  );
}
