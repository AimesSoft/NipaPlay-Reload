import 'dart:io' as io;

// lib/utils/mock_path_provider.dart

// 这是一个模拟实现，用于在Web平台上提供与 `path_provider` 相同的 API。
// 在Web上，没有实际的临时目录概念，因此我们返回一个模拟的 `Directory` 对象。

// 模拟的 `Directory` 类
class Directory implements io.Directory {
  @override
  final String path;
  Directory(this.path);

  @override
  Future<bool> exists() async => false;
  @override
  Future<io.Directory> create({bool recursive = false}) async => this;
  @override
  Future<io.FileSystemEntity> delete({bool recursive = false}) async => this;
  @override
  Stream<io.FileSystemEntity> list({bool recursive = false, bool followLinks = true}) {
    return Stream.fromIterable([]);
  }
  
  // 实现 io.Directory 的其他抽象方法
  @override
  io.Directory get absolute => this;
  @override
  Future<io.Directory> createTemp([String? prefix]) async => this;
  @override
  bool existsSync() => false;
  @override
  bool get isAbsolute => true;
  @override
  io.Directory get parent => this;
  @override
  Future<io.Directory> rename(String newPath) async => Directory(newPath);
  @override
  io.Directory renameSync(String newPath) => Directory(newPath);
  @override
  Future<String> resolveSymbolicLinks() async => path;
  @override
  String resolveSymbolicLinksSync() => path;
  @override
  Uri get uri => Uri.parse(path);

  @override
  void createSync({bool recursive = false}) {}
  @override
  io.Directory createTempSync([String? prefix]) => this;
  @override
  void deleteSync({bool recursive = false}) {}
  @override
  List<io.FileSystemEntity> listSync({bool recursive = false, bool followLinks = true}) => [];
  
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // 为任何其他未实现的方法提供一个默认行为
    return super.noSuchMethod(invocation);
  }
}

// 模拟的 `FileSystemEntity` 类
abstract class FileSystemEntity implements io.FileSystemEntity {
}


// 模拟的 `getTemporaryDirectory` 函数
Future<Directory> getTemporaryDirectory() async {
  return Directory('temp');
}

// 模拟的 `getApplicationDocumentsDirectory` 函数
Future<Directory> getApplicationDocumentsDirectory() async {
  return Directory('documents');
}

// 模拟的 `getExternalStorageDirectories` 函数
Future<List<Directory>?> getExternalStorageDirectories() async {
  return [];
} 