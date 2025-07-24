// A stub for the 'dart:io' Platform class.
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => 'web';
}

// A stub for the 'dart:io' File class.
class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  // any other methods used... the errors don't show more.
}

// A stub for the 'dart:io' Directory class.
class Directory {
  final String path;
  Directory(this.path);

  bool existsSync() => false;
  void createSync({bool recursive = false}) {
    // no-op on web
  }
} 