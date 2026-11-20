import 'dart:async';

import 'package:nipaplay/services/macos_process_environment.dart';

/// Every test file under test/ runs through this.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Tests run as the unsandboxed app does, on a Mac as on Linux CI: asking
  // the native host would be answered in real time, out of a widget test's
  // fake time, and stall the Classic requests it makes. A test of the
  // sandbox itself injects its own answer.
  MacOSProcessEnvironment.debugSandboxedOverride = false;
  await testMain();
}
