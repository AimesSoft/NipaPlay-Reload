import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:crypto/crypto.dart';

class BackupService {
  // .nph 文件格式版本
  static const int _fileFormatVersion = 1;

  /// 将观看历史导出为 .nph 二进制文件
  /// 
  /// [directoryPath] 保存目录路径
  /// 返回保存的文件路径，如果失败返回 null
  Future<String?> exportWatchHistory(String directoryPath) async {
    try {
      // 从数据库获取所有观看历史
      final database = WatchHistoryDatabase.instance;
      final historyItems = await database.getAllWatchHistory();

      if (historyItems.isEmpty) {
        debugPrint('没有观看历史需要备份');
        return null;
      }

      // 创建备份数据结构
      final backupData = _createBackupData(historyItems);

      // 生成文件名（使用易读的日期时间格式）
      final now = DateTime.now();
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeString = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'nipaplay_history_${dateString}_$timeString.nph';
      final filePath = path.join(directoryPath, fileName);

      // 写入二进制文件
      final file = File(filePath);
      await file.writeAsBytes(backupData);

      debugPrint('成功导出 ${historyItems.length} 条观看记录到: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('导出观看历史失败: $e');
      return null;
    }
  }

  /// 从 .nph 二进制文件导入观看历史
  /// 
  /// [filePath] 备份文件路径
  /// 返回恢复的记录数量
  Future<int> importWatchHistory(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('备份文件不存在: $filePath');
        return 0;
      }

      // 读取二进制数据
      final bytes = await file.readAsBytes();
      
      // 解析备份数据
      final historyItems = await _parseBackupData(bytes);
      
      if (historyItems.isEmpty) {
        debugPrint('备份文件中没有有效的观看记录');
        return 0;
      }

      // 获取本地数据库以检查文件是否存在
      final database = WatchHistoryDatabase.instance;
      
      int restoredCount = 0;
      
      for (final item in historyItems) {
        try {
          // 检查文件是否存在于本地
          if (await _isFileExists(item)) {
            // 检查是否已有记录（用于决定是否覆盖截图）
            final existingItem = await database.getHistoryByFilePath(item.filePath);
            
            // 决定最终的截图路径：优先使用备份中的截图，如果没有则保留现有截图
            final finalThumbnailPath = item.thumbnailPath ?? existingItem?.thumbnailPath;
            
            // 直接强制更新数据库，绕过所有缓存逻辑
            final db = await database.database;
            await db.update(
              'watch_history',
              {
                'watch_progress': item.watchProgress,
                'last_position': item.lastPosition,
                'duration': item.duration,
                'last_watch_time': item.lastWatchTime.toIso8601String(),
                // 使用最终决定的截图路径
                'thumbnail_path': finalThumbnailPath,
              },
              where: 'file_path = ?',
              whereArgs: [item.filePath],
            );
            
            // 关键：同时更新 SharedPreferences 中的播放位置
            await _updateSharedPreferencesPosition(item.filePath, item.lastPosition);
            restoredCount++;
            debugPrint('恢复观看记录: ${item.animeName} - ${item.episodeTitle ?? "未知集数"} '
                       '进度: ${item.watchProgress.toStringAsFixed(2)} 位置: ${item.lastPosition}ms');
          } else {
            debugPrint('跳过不存在的文件: ${item.animeName} - ${item.episodeTitle ?? "未知集数"}');
          }
        } catch (e) {
          debugPrint('恢复单条记录失败: ${item.animeName}, 错误: $e');
          continue;
        }
      }

      debugPrint('成功恢复 $restoredCount 条观看记录');
      return restoredCount;
    } catch (e) {
      debugPrint('导入观看历史失败: $e');
      return 0;
    }
  }

  /// 创建备份数据的二进制格式
  /// 
  /// 文件格式：
  /// - 4字节：文件格式版本号 (little-endian)
  /// - 4字节：记录数量 (little-endian)
  /// - 对于每条记录：
  ///   - 4字节：记录长度 (little-endian)
  ///   - 变长：JSON数据（UTF-8编码）
  Uint8List _createBackupData(List<WatchHistoryItem> historyItems) {
    final buffer = BytesBuilder();
    
    // 写入文件格式版本
    final versionBytes = ByteData(4);
    versionBytes.setInt32(0, _fileFormatVersion, Endian.little);
    buffer.add(versionBytes.buffer.asUint8List());
    
    // 写入记录数量
    final countBytes = ByteData(4);
    countBytes.setInt32(0, historyItems.length, Endian.little);
    buffer.add(countBytes.buffer.asUint8List());
    
    // 写入每条记录
    for (final item in historyItems) {
      // 读取截图文件（如果存在）
      String? thumbnailBase64;
      if (item.thumbnailPath != null) {
        try {
          final thumbnailFile = File(item.thumbnailPath!);
          if (thumbnailFile.existsSync()) {
            final thumbnailBytes = thumbnailFile.readAsBytesSync();
            thumbnailBase64 = base64Encode(thumbnailBytes);
          }
        } catch (e) {
          debugPrint('读取截图文件失败: ${item.thumbnailPath}, 错误: $e');
        }
      }
      
      // 创建包含截图的备份数据
      final recordData = {
        'filePath': item.filePath,
        'animeName': item.animeName,
        'episodeTitle': item.episodeTitle,
        'episodeId': item.episodeId,
        'animeId': item.animeId,
        'watchProgress': item.watchProgress,
        'lastPosition': item.lastPosition,
        'duration': item.duration,
        'lastWatchTime': item.lastWatchTime.toIso8601String(),
        'isFromScan': item.isFromScan,
        'thumbnailBase64': thumbnailBase64, // 包含截图的base64数据
      };
      
      // 转换为JSON并编码为UTF-8
      final jsonString = json.encode(recordData);
      final utf8Bytes = utf8.encode(jsonString);
      
      // 写入记录长度
      final lengthBytes = ByteData(4);
      lengthBytes.setInt32(0, utf8Bytes.length, Endian.little);
      buffer.add(lengthBytes.buffer.asUint8List());
      
      // 写入记录数据
      buffer.add(utf8Bytes);
    }
    
    return buffer.toBytes();
  }

  /// 解析备份数据的二进制格式
  Future<List<WatchHistoryItem>> _parseBackupData(Uint8List bytes) async {
    try {
      final data = ByteData.sublistView(bytes);
      int offset = 0;
      
      // 读取文件格式版本
      final version = data.getInt32(offset, Endian.little);
      offset += 4;
      
      if (version != _fileFormatVersion) {
        debugPrint('不支持的文件格式版本: $version');
        return [];
      }
      
      // 读取记录数量
      final count = data.getInt32(offset, Endian.little);
      offset += 4;
      
      final historyItems = <WatchHistoryItem>[];
      
      // 读取每条记录
      for (int i = 0; i < count; i++) {
        try {
          // 读取记录长度
          final length = data.getInt32(offset, Endian.little);
          offset += 4;
          
          // 读取记录数据
          final recordBytes = bytes.sublist(offset, offset + length);
          offset += length;
          
          // 解码JSON
          final jsonString = utf8.decode(recordBytes);
          final recordData = json.decode(jsonString) as Map<String, dynamic>;
          
          // 创建WatchHistoryItem对象
          final item = WatchHistoryItem(
            filePath: recordData['filePath'],
            animeName: recordData['animeName'],
            episodeTitle: recordData['episodeTitle'],
            episodeId: recordData['episodeId'],
            animeId: recordData['animeId'],
            watchProgress: (recordData['watchProgress'] ?? 0.0).toDouble(),
            lastPosition: recordData['lastPosition'] ?? 0,
            duration: recordData['duration'] ?? 0,
            lastWatchTime: DateTime.parse(recordData['lastWatchTime']),
            isFromScan: recordData['isFromScan'] ?? false,
            // 临时设为null，稍后会处理截图恢复
            thumbnailPath: null,
          );
          
          // 处理截图恢复
          String? restoredThumbnailPath;
          final thumbnailBase64 = recordData['thumbnailBase64'];
          if (thumbnailBase64 != null && thumbnailBase64 is String && thumbnailBase64.isNotEmpty) {
            restoredThumbnailPath = await _restoreThumbnail(item.filePath, thumbnailBase64);
          }
          
          // 更新截图路径
          final finalItem = item.copyWith(thumbnailPath: restoredThumbnailPath);
          
          historyItems.add(finalItem);
        } catch (e) {
          debugPrint('解析第${i + 1}条记录失败: $e');
          continue;
        }
      }
      
      return historyItems;
    } catch (e) {
      debugPrint('解析备份文件失败: $e');
      return [];
    }
  }

  /// 恢复截图文件
  /// [filePath] 视频文件路径
  /// [thumbnailBase64] 截图的base64编码数据
  /// 返回恢复后的截图文件路径
  Future<String?> _restoreThumbnail(String filePath, String thumbnailBase64) async {
    try {
      // 解码base64数据
      final thumbnailBytes = base64Decode(thumbnailBase64);
      
      // 使用应用的存储目录，避免权限问题
      final appDir = await StorageService.getAppStorageDirectory();
      final thumbnailsDir = Directory(path.join(appDir.path, 'thumbnails'));
      
      // 确保目录存在
      if (!thumbnailsDir.existsSync()) {
        await thumbnailsDir.create(recursive: true);
      }
      
      // 生成基于文件路径的唯一文件名，避免冲突
      final pathHash = sha256.convert(utf8.encode(filePath)).toString().substring(0, 16);
      final videoName = path.basenameWithoutExtension(filePath);
      final thumbnailFileName = '${videoName}_${pathHash}_thumbnail.jpg';
      final thumbnailPath = path.join(thumbnailsDir.path, thumbnailFileName);
      
      // 写入截图文件
      final thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes(thumbnailBytes);
      
      debugPrint('恢复截图: $thumbnailPath');
      return thumbnailPath;
    } catch (e) {
      debugPrint('恢复截图失败: $e');
      return null;
    }
  }

  /// 更新 SharedPreferences 中的播放位置
  /// 这是播放器读取播放位置的主要来源
  Future<void> _updateSharedPreferencesPosition(String filePath, int position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String videoPositionsKey = 'video_positions';
      
      // 读取现有的播放位置数据
      final positions = prefs.getString(videoPositionsKey) ?? '{}';
      final Map<String, dynamic> positionMap = Map<String, dynamic>.from(json.decode(positions));
      
      // 更新指定文件的播放位置
      positionMap[filePath] = position;
      
      // 保存回 SharedPreferences
      await prefs.setString(videoPositionsKey, json.encode(positionMap));
      
      debugPrint('已更新 SharedPreferences 播放位置: $filePath -> ${position}ms');
    } catch (e) {
      debugPrint('更新 SharedPreferences 播放位置失败: $e');
    }
  }

  /// 检查文件是否存在
  Future<bool> _isFileExists(WatchHistoryItem item) async {
    try {
      // 检查文件路径是否存在
      final file = File(item.filePath);
      if (await file.exists()) {
        return true;
      }

      // 对于远程协议，认为文件存在
      if (item.filePath.startsWith('jellyfin://') || 
          item.filePath.startsWith('emby://') || 
          item.filePath.startsWith('http://') || 
          item.filePath.startsWith('https://')) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('检查文件存在性失败: ${item.filePath}, 错误: $e');
      return false;
    }
  }
}