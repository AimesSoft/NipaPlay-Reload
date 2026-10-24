/// An installation of a downloaded runtime (Codex, DeepSeek Harness) failed in
/// a way [message] says in words for the person.
final class RuntimeInstallException implements Exception {
  const RuntimeInstallException(this.message);
  final String message;
}
