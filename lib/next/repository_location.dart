abstract interface class RepositoryLocation {
  Future<void> get ready;
  String get path;
}
