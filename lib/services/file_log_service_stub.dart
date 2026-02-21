class FileLogService {
  static final FileLogService _instance = FileLogService._internal();
  factory FileLogService() => _instance;
  FileLogService._internal();

  Future<void> initialize() async {}

  Future<void> start() async {}

  Future<void> stop() async {}

  Future<bool> openLogDirectory() async => false;

  Future<String?> getLogDirectoryPath() async => null;

  bool get isRunning => false;
}
