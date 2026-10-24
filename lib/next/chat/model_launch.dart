import 'dart:io';

import 'dsh_runtime.dart';

/// A private launch snapshot. Credentials are environment values, never RPC
/// configuration, process arguments, or public host diagnostics.
final class ModelLaunch {
  const ModelLaunch(
      {required this.revision,
      this.home,
      this.environment = const {},
      this.model,
      this.provider,
      this.executable,
      this.prepare,
      this.route});
  final int revision;
  final Directory? home;
  final Map<String, String> environment;
  final String? model, provider;
  /// Absolute managed native binary, or an explicitly chosen advanced path.
  final String? executable;
  final Future<void> Function()? prepare;

  /// For DeepSeek Harness: the model route set up in NipaPlay, key included.
  final DshRoute? route;
}
