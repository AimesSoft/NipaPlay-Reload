import 'dart:io';

/// A private launch snapshot. Credentials are environment values, never RPC
/// configuration, process arguments, or public host diagnostics.
final class ModelLaunch {
  const ModelLaunch(
      {required this.revision,
      this.home,
      this.environment = const {},
      this.model,
      this.provider,
      this.prepare});
  final int revision;
  final Directory? home;
  final Map<String, String> environment;
  final String? model, provider;
  final Future<void> Function()? prepare;
}
