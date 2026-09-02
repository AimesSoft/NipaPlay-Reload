
// lib/services/media_source/media_source_service.dart
// 管理媒体源


import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nipaplay/models/database/asset_path_record.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';
import 'package:nipaplay/utils/phrase.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/storage_service.dart';

part 'models.dart';


class MediaSourceService {

  static Set<MediaSource> _mediaSources = {};


  /// 初始化从配置文件加载媒体源数据
  static Future<void> initialize() async {
    final appDir = await StorageService.getAppStorageDirectory();
    final configFile = File('${appDir.path}/media_sources.json');
    if (await configFile.exists()) {
      final jsonString = await configFile.readAsString();
      final jsonMap = jsonDecode(jsonString) as JsonData;
      _mediaSources = jsonMap.values.map((json) {
        final type = json['type'] as String;
        return switch (type) {
          'local' => LocalMediaSource.fromJsonData(json),
          'webDav' => WebDavMediaSource.fromJsonData(json),
          _ => throw ArgumentError.value(type, 'type', '未知的媒体源类型'),
        };
      }).toSet();
    }

    debugPrint(color('已从配置文件加载媒体源数据: ${configFile.path}', ColorCode.green));
  }


  /// 获取媒体源拷贝
  /// 返回媒体源的拷贝, 避免外部修改原始数据
  static Set<MediaSourceInfo> getMediaSources() {
    Set<MediaSourceInfo> copy = {};
    for (final source in _mediaSources) {
      if (source is LocalMediaSource) {
        copy.add(LocalMediaSourceInfo(
          id: source.id,
          name: source.name,
          directory: source.rootDirectory,
        ));
      } else if (source is WebDavMediaSource) {
        copy.add(WebDavMediaSourceInfo(
          id: source.id,
          name: source.name,
          url: source.url,
          username: source.username,
          password: source.password,
        ));
      } else {
        throw ArgumentError.value(source, 'source', '未知的媒体源类型');
      }
    }
    return copy;
  }

  static Directory getMediaSourceRootDirectory(int sourceId) {

    final mediaSource = _mediaSources.firstWhere(
      (source) => source.id == sourceId,
      orElse: () => throw ArgumentError.value(sourceId, 'id', '未找到指定 ID 的媒体源'),
    );

    if (mediaSource is LocalMediaSource) {
      return mediaSource.rootDirectory;
    } else if (mediaSource is WebDavMediaSource) {
      throw UnimplementedError(unimplementedErrorPhrase);
    } else {
      throw ArgumentError.value(mediaSource, 'mediaSource', '未知的媒体源类型');
    }
  }


  /// 对比数据库中的媒体源文件与实际文件系统中的文件,
  /// 删除数据库中已不存在的文件记录, 并登记新文件到数据库 (不计算 Hash)
  /// 最好随时同步
  static Future<void> synchronizeMediaSourceFilesWithDatabase(int sourceId) async {

    // 计时器
    final stopwatch = Stopwatch()..start();

    debugPrint(color('开始同步媒体源 ID=$sourceId 的文件与数据库记录', ColorCode.blue));

    final mediaSource = _mediaSources.firstWhere(
      (source) => source.id == sourceId,
      orElse: () => throw ArgumentError.value(sourceId, 'id', '未找到指定 ID 的媒体源'),
    );

    if (mediaSource is LocalMediaSource) {

      final rootDir = mediaSource.getRoot();
      final allFiles = mediaSource.getAllFiles();
      Set<AssetPathInSource> filePaths = {};
      for (final entity in allFiles) {
        // fileDirectory 是文件相对 MediaSource.rootDirectory 的路径
        final String fileDirectory = entity.parent.path.replaceFirst(rootDir.path, '').replaceFirst(RegExp(r'^[/\\]'), '');
        final String fileNameNoExtension = p.basenameWithoutExtension(entity.path);
        final String fileExtension = p.extension(entity.path).replaceFirst('.', '');

        final assetPath = AssetPathInSource(
          path: fileDirectory,
          nameNoExt: fileNameNoExtension,
          ext: fileExtension,
        );
        filePaths.add(assetPath);
      }

      debugPrint('预计插入或更新 ${filePaths.length} 条媒体源 ID=$sourceId 的文件路径记录');
      await DatabaseService.synchronizeAssetPathRecords(sourceId, filePaths);

    } else if (mediaSource is WebDavMediaSource) {
      throw UnimplementedError(unimplementedErrorPhrase);
    }

    stopwatch.stop();
    debugPrint(color('已完成同步媒体源 ID=$sourceId 的文件与数据库记录, 耗时: ${stopwatch.elapsed}', ColorCode.green));

  }

  /// 1. 获取指定媒体源下所有 asset_pre16mib_md5 字段为 null 的视频资产路径记录
  /// 2. 根据这些记录, 计算该路径文件的前 16MiB 的 MD5 哈希值, 并更新数据库
  static Future<void> updateAssetPathRecordsHash(int sourceId) async {

    // 计时器
    final stopwatch = Stopwatch()..start();

    debugPrint(color('开始更新媒体源 ID=$sourceId 的所有文件路径记录的前 16MiB MD5 哈希值', ColorCode.blue));

    final recordsNoHash = await DatabaseService.getAssetPathRecordsNoHash(sourceId);
    debugPrint('预计更新 ${recordsNoHash.length} 条媒体源 ID=$sourceId 的文件路径记录的前 16MiB MD5 哈希值');

    int count = 0;
    final rootDir = getMediaSourceRootDirectory(sourceId);
    for (final record in recordsNoHash) {
      final filePath = p.join(rootDir.path, record.path, '${record.nameNoExt}.${record.ext}');
      if (await File(filePath).exists()) {
        final hash = await computeFileHeadMd5Bytes(filePath);

        final pathInSource = AssetPathInSource(
          path: record.path,
          nameNoExt: record.nameNoExt,
          ext: record.ext,
        );
        final assetPath = AssetPath(
          mediaSourceId: sourceId,
          pathInSource: pathInSource,
        );
        final asset = DbPathAssetRecord(
          assetPath: assetPath,
          hashPre16MiBMd5: hash,
        );

        await DatabaseService.upsertAssetPathRecord(asset);
        count++;
        if (count % 100 == 0 || count == recordsNoHash.length) {
          debugPrint(color('已更新媒体源 ID=$sourceId 的文件路径记录的前 16MiB MD5 哈希值: $count / ${recordsNoHash.length}', ColorCode.blue));
        }
      } else {
        debugPrint(color('文件不存在, 无法计算前 16MiB MD5 哈希值: $filePath', ColorCode.red));
      }
    }

    stopwatch.stop();
    debugPrint(color('已完成更新媒体源 ID=$sourceId 的所有文件路径记录的前 16MiB MD5 哈希值, 共更新 $count 条记录, 耗时: ${stopwatch.elapsed}', ColorCode.green));
  }

  /// 将指定媒体源下所有文件登记到数据库
  /// 将来可以多线程优化效率
  static Future<void> registerMediaSourceFilesToDatabase(int id) async {

    // 计时器
    final stopwatch = Stopwatch()..start();

    debugPrint(color('开始登记媒体源 ID=$id 的所有文件到数据库', ColorCode.blue));

    final mediaSource = _mediaSources.firstWhere(
      (source) => source.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', '未找到指定 ID 的媒体源'),
    );

    if (mediaSource is LocalMediaSource) {
      final rootDir = mediaSource.getRoot();
      final allFiles = mediaSource.getAllFiles();
      int count = 0;
      int total = allFiles.length;
      for (final entity in allFiles) {

        // fileDirectory 是文件相对 MediaSource.rootDirectory 的路径
        final String fileDirectory = entity.parent.path.replaceFirst(rootDir.path, '').replaceFirst(RegExp(r'^[/\\]'), '');
        final String fileNameNoExtension = p.basenameWithoutExtension(entity.path);
        final String fileExtension = p.extension(entity.path).replaceFirst('.', '');
        final int    fileSize = await entity.length();
        final Uint8List filePre16MiBMd5Hash = await computeFileHeadMd5Bytes(entity.path);

        final pathInSource = AssetPathInSource(
          path: fileDirectory,
          nameNoExt: fileNameNoExtension,
          ext: fileExtension,
        );
        final assetPath = AssetPath(
          mediaSourceId: id,
          pathInSource: pathInSource,
        );
        final assetRecord = DbAssetRecord(
          hashPre16MiBMd5: filePre16MiBMd5Hash,
          size: fileSize,
          codec: fileExtension,
          hashSha256: null,
        );
        final pathRecord = DbPathAssetRecord(
          assetPath: assetPath,
          hashPre16MiBMd5: filePre16MiBMd5Hash,
        );

        DatabaseService.upsertAssetRecord(assetRecord);
        DatabaseService.upsertAssetPathRecord(pathRecord);

        // 刷新进度
        count++;
        if (count % 100 == 0 || count == total) {
          debugPrint(color('已登记媒体源 ID=$id 的文件: $count / $total', ColorCode.blue));
        }
      }
    } else if (mediaSource is WebDavMediaSource) {
      throw UnimplementedError(unimplementedErrorPhrase);
    }

    stopwatch.stop();
    debugPrint(color('已完成登记媒体源 ID=$id 的所有文件到数据库, 耗时: ${stopwatch.elapsed}', ColorCode.green));
  }

  /// 添加新的媒体源
  static void addMediaSource(MediaSourceInfo source) {

    if (_mediaSources.any((s) => s.id == source.id)) {
      throw ArgumentError.value(source.id, 'id', '已存在相同 ID 的媒体源');
    }

    // 判断媒体源类型并创建对应的 MediaSource 对象
    final mediaSource = switch (source) {
      LocalMediaSourceInfo local => LocalMediaSource.fromLocalMediaSourceInfo(local),
      WebDavMediaSourceInfo webDav => WebDavMediaSource.fromWebDavMediaSourceInfo(webDav),
      _ => throw ArgumentError.value(source, 'source', '未知的媒体源类型'),
    };

    _mediaSources.add(mediaSource);
  }

  /// 更新已有的媒体源
  /// 如果媒体源不存在, 则抛出异常
  static void updateMediaSource(MediaSourceInfo source) {
    final existingSource = _mediaSources.firstWhere(
      (s) => s.id == source.id,
      orElse: () => throw ArgumentError.value(source.id, 'id', '未找到指定 ID 的媒体源'),
    );

    // 判断媒体源类型并创建对应的 MediaSource 对象
    final updatedSource = switch (source) {
      LocalMediaSourceInfo local => LocalMediaSource.fromLocalMediaSourceInfo(local),
      WebDavMediaSourceInfo webDav => WebDavMediaSource.fromWebDavMediaSourceInfo(webDav),
      _ => throw ArgumentError.value(source, 'source', '未知的媒体源类型'),
    };

    _mediaSources.remove(existingSource);
    _mediaSources.add(updatedSource);
  }

  /// 删除指定 ID 的媒体源
  static void removeMediaSource(int id) {
    _mediaSources.removeWhere((source) => source.id == id);
  }

  /// 把媒体源数据写到配置文件:
  /// <应用数据目录>/media_sources.json
  static Future<void> saveAllMediaSourcesToConfigFile() async {

    final appDir = await StorageService.getAppStorageDirectory();
    final configFile = File('${appDir.path}/media_sources.json');
    JsonData jsonMap = {};
    for (final source in _mediaSources) {
      final sourceJson = source.toJsonData();
      jsonMap[source.id.toString()] = sourceJson;
    }
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );

    debugPrint(color('已保存所有媒体源数据到配置文件: ${configFile.path}', ColorCode.green));
  }

  /// 保存指定 ID 的媒体源数据到配置文件
  static Future<void> saveMediaSourcesToConfigFile(int id) async {

    // 找到指定 ID 的媒体源
    final mediaSource = _mediaSources.firstWhere(
      (source) => source.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', '未找到指定 ID 的媒体源'),
    );

    // 获取 <应用数据目录>/media_sources.json JSON 对象
    final appDir = await StorageService.getAppStorageDirectory();
    final configFile = File('${appDir.path}/media_sources.json');
    JsonData jsonMap = {};
    if (await configFile.exists()) {
      final jsonString = await configFile.readAsString();
      jsonMap = jsonDecode(jsonString) as JsonData;
    }

    // 更新指定 ID 的媒体源数据
    jsonMap[id.toString()] = {
      'id': mediaSource.id,
      'name': mediaSource.name,
      'type': mediaSource.getType().name,
      if (mediaSource is LocalMediaSource) 'directory': mediaSource.rootDirectory,
      if (mediaSource is WebDavMediaSource) ...{
        'url': mediaSource.url,
        'username': mediaSource.username,
        'password': mediaSource.password,
      },
    };

    // 将更新后的 JSON 对象写回配置文件
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }
}