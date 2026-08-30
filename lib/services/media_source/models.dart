
// lib/services/media_source/models.dart

part of 'media_source_service.dart';


enum MediaSourceType {
  local,
  webDav,
}

abstract class MediaSource {

  int     id;
  String? name;
  final MediaSourceType type;

  MediaSource({
    required this.id,
    this.name,
    required this.type,
  });


  // 抽象方法
  // ------------------------------------------------------------------------ //

  Set<File> getAllFiles(); // 获取某个媒体源下所有文件 (递归)

  Set<FileSystemEntity> getAllEntities(Directory dir); // 获取某个路径下所有元素
  Directory getRoot(); // 获取媒体源的根目录 (LocalMediaSource) 或根路径 (WebDavMediaSource)
  MediaSourceType getType() => type; // 获取媒体源类型

  JsonData toJsonData(); //  获取媒体源的 JSON 表示
}

class LocalMediaSource extends MediaSource {

  final Directory rootDirectory;

  LocalMediaSource({
    required super.id,
    super.name,
    required this.rootDirectory,
  }) : super(type: MediaSourceType.local);

  @override
  MediaSourceType getType() => MediaSourceType.local;

  @override
  Set<FileSystemEntity> getAllEntities(Directory dir) {
    if (!dir.existsSync()) {
      throw ArgumentError.value(dir.path, 'dir', '目录不存在');
    }
    return dir.listSync().toSet();
  }

  @override
  Directory getRoot() {
    final rootDir = rootDirectory;
    if (!rootDir.existsSync()) {
      throw ArgumentError.value(rootDirectory.path, 'directory', '根目录不存在');
    }
    return rootDir;
  }

  @override
  JsonData toJsonData() {
    return {
      'id': id,
      'name': name,
      'type': getType().name,
      'directory': rootDirectory.path,
    };
  }

  @override
  Set<File> getAllFiles() {
    final rootDir = getRoot();
    final entities = getAllEntities(rootDir);
    final files = <File>{};
    for (final entity in entities) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        files.addAll(getAllFilesInDirectory(entity));
      }
    }
    return files;
  }

  static LocalMediaSource fromJsonData(JsonData json) {
    return LocalMediaSource(
      id: json['id'] as int,
      name: json['name'] as String?,
      rootDirectory: Directory(json['directory'] as String),
    );
  }

  Set<File> getAllFilesInDirectory(Directory dir) {
    final entities = getAllEntities(dir);
    final files = <File>{};
    for (final entity in entities) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        files.addAll(getAllFilesInDirectory(entity));
      }
    }
    return files;
  }

  static LocalMediaSource fromLocalMediaSourceInfo(LocalMediaSourceInfo info) {
    return LocalMediaSource(
      id: info.id,
      name: info.name,
      rootDirectory: info.directory,
    );
  }
}

class WebDavMediaSource extends MediaSource {

  final String url;
  final String username;
  final String password;

  WebDavMediaSource({
    required super.id,
    super.name,
    required this.url,
    required this.username,
    required this.password,
  }) : super(type: MediaSourceType.webDav);

  @override
  MediaSourceType getType() => MediaSourceType.webDav;

  @override
  Set<FileSystemEntity> getAllEntities(Directory dir) {
    throw UnimplementedError('WebDavMediaSource.getAllEntities() 未实现 <(*O*)>');
  }

  @override
  Directory getRoot() {
    throw UnimplementedError('WebDavMediaSource.getRoot() 未实现: $unimplementedErrorPhrase');
  }

  @override
  JsonData toJsonData() {
    return {
      'id': id,
      'name': name,
      'type': getType().name,
      'url': url,
      'username': username,
      'password': password,
    };
  }

  @override
  Set<File> getAllFiles() {
    throw UnimplementedError('WebDavMediaSource.getAllFiles() 未实现: $unimplementedErrorPhrase');
  }

  static MediaSource fromJsonData(JsonData json) {
    return WebDavMediaSource(
      id: json['id'] as int,
      name: json['name'] as String?,
      url: json['url'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

  static WebDavMediaSource fromWebDavMediaSourceInfo(WebDavMediaSourceInfo info) {
    return WebDavMediaSource(
      id: info.id,
      name: info.name,
      url: info.url,
      username: info.username ?? '',
      password: info.password ?? '',
    );
  }
}


abstract class MediaSourceInfo {

  final int id;
  final String? name;
  final MediaSourceType type;

  MediaSourceInfo({
    required this.id,
    this.name,
    required this.type,
  });

}

class LocalMediaSourceInfo extends MediaSourceInfo {

  final Directory directory;

  LocalMediaSourceInfo({
    required super.id,
    super.name,
    required this.directory,
  }) : super(type: MediaSourceType.local);

  @override
  String toString() {
    return 'LocalMediaSourceInfo(id: $id, name: $name, directory: $directory)';
  }
}

class WebDavMediaSourceInfo extends MediaSourceInfo {

  final String url;
  final String? username;
  final String? password;

  WebDavMediaSourceInfo({
    required super.id,
    super.name,
    required this.url,
    this.username,
    this.password,
  }) : super(type: MediaSourceType.webDav);

  @override
  String toString() {
    return 'WebDavMediaSourceInfo(id: $id, name: $name, url: $url, username: $username, password: $password)';
  }
}