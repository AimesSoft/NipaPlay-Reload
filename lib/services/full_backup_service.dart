import 'dart:io';
import 'dart:convert';
export 'package:nipaplay/services/backup_category.dart';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/services/incremental_sync_native_codec.dart';
import 'package:nipaplay/services/backup_category.dart';
import 'package:crypto/crypto.dart';

/// 全量备份服务
///
/// 备份文件格式为 JSON，结构如下：
/// {
///   "version": 2,                    // 备份格式版本号
///   "timestamp": "2026-06-11T...",   // 备份创建时间
///   "appVersion": "1.4.9",           // 应用版本号
///   "preferences": { ... },          // 偏好设置（可选）
///   "mediaLibraries": { ... },       // 媒体库配置（可选）
///   "watchHistory": [ ... ],         // 观看历史（可选）
///   "episodeMatches": [ ... ],       // 剧集匹配数据（可选）
///   "accounts": { ... },             // 账户绑定数据（可选）
/// }
class FullBackupService {
  static const int _backupFormatVersion = 2;

  // ==================== 导出（信息收集） ====================

  /// 导出全量备份到文件
  ///
  /// [directoryPath] 保存目录路径
  /// [categories] 要导出的数据类别集合
  /// [appVersion] 当前应用版本号
  /// 返回保存的文件路径，如果失败返回 null
  Future<String?> exportBackup({
    required String directoryPath,
    required Set<BackupCategory> categories,
    String appVersion = '',
  }) async {
    final fileName = buildBackupFileName(categories);
    return exportBackupToFile(
      filePath: path.join(directoryPath, fileName),
      categories: categories,
      appVersion: appVersion,
    );
  }

  /// 导出全量备份到指定文件路径，供 iOS 系统保存面板使用。
  Future<String?> exportBackupToFile({
    required String filePath,
    required Set<BackupCategory> categories,
    String appVersion = '',
  }) async {
    try {
      final backupData = await collectBackupData(
        categories: categories,
        appVersion: appVersion,
      );

      // Rust 负责最终 JSON 编码、canonical 排序与校验；特殊平台会自动
      // 回退到后台 Dart isolate。编码前仍净化 Infinity/NaN。
      final sanitized =
          Map<String, dynamic>.from(_sanitizeForJson(backupData) as Map);
      final encoded = await IncrementalSyncNativeCodec.encodeMap(
        sanitized,
        pretty: true,
      );
      final file = File(filePath);
      await file.writeAsBytes(encoded.bytes);

      debugPrint('成功导出备份到: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('导出备份失败: $e');
      return null;
    }
  }

  String buildBackupFileName(
    Set<BackupCategory> categories, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final dateString =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final timeString =
        '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}';
    final categorySuffix = _buildCategorySuffix(categories);
    return 'nipaplay_backup_${categorySuffix}_${dateString}_$timeString.npb';
  }

  /// 仅收集备份数据（不写文件），供外部使用
  Future<Map<String, dynamic>> collectBackupData({
    required Set<BackupCategory> categories,
    String appVersion = '',
    bool includeWatchHistoryThumbnails = true,
  }) async {
    final backupData = <String, dynamic>{
      'version': _backupFormatVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'appVersion': appVersion,
    };

    List<WatchHistoryItem>? historyItems;
    if (categories.contains(BackupCategory.watchHistory) ||
        categories.contains(BackupCategory.episodeMatches)) {
      historyItems = await WatchHistoryDatabase.instance.getAllWatchHistory();
    }

    if (categories.contains(BackupCategory.preferences)) {
      backupData['preferences'] = await _collectPreferences();
    }
    if (categories.contains(BackupCategory.mediaLibraries)) {
      backupData['mediaLibraries'] = await _collectMediaLibraries();
    }
    if (categories.contains(BackupCategory.watchHistory)) {
      backupData['watchHistory'] = await _collectWatchHistory(
        historyItems!,
        includeThumbnails: includeWatchHistoryThumbnails,
      );
    }
    if (categories.contains(BackupCategory.episodeMatches)) {
      backupData['episodeMatches'] = _collectEpisodeMatches(historyItems!);
    }
    if (categories.contains(BackupCategory.accounts)) {
      backupData['accounts'] = await _collectAccounts();
    }

    return _sanitizeForJson(backupData) as Map<String, dynamic>;
  }

  // ---------- 偏好设置收集 ----------

  /// 收集偏好设置数据（仅软件设置，不含媒体库配置）
  ///
  /// 包含：
  /// - 软件设置（语言、弹幕、播放器、下载等）
  Future<Map<String, dynamic>> _collectPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};

    // 收集所有 SharedPreferences 中的设置项（排除媒体库和账户相关）
    final allKeys = prefs.getKeys();
    final settingsKeys = allKeys.where((key) =>
        !key.startsWith('incremental_sync_') && // 同步端点/凭证仅属于本机
        !key.startsWith('auto_sync_') && // 自动同步开关与旧路径仅属于本机
        !key.startsWith('dandanplay_') && // 账户相关单独处理
        !key.startsWith('server_profiles') && // 服务器配置属于媒体库
        key != 'video_positions' && // 播放位置属于观看历史
        key != 'watch_history_web_store' && // Web观看历史单独处理
        !key.startsWith('nipaplay_subfolder_hash_cache') && // 扫描缓存不需要备份
        !key.endsWith('_library_sort_settings') && // 排序设置属于媒体库
        key != 'custom_storage_path' && // 存储路径是设备相关的
        key != 'nipaplay_scanned_folders' && // 本地媒体库属于媒体库
        !key.startsWith('emby_selected_library_ids') && // 选中媒体库属于媒体库
        !key.startsWith('jellyfin_selected_library_ids') && // 选中媒体库属于媒体库
        key != 'webdav_connections' && // WebDAV连接属于媒体库
        key != 'smb_connections' && // SMB连接属于媒体库
        !key.startsWith('web_server_') && // Web服务器配置属于媒体库
        key != 'bangumi_access_token' && // Bangumi账户属于账户
        key != 'bangumi_user_info' && // Bangumi账户属于账户
        key != 'bangumi_logged_in'); // Bangumi账户属于账户

    final settingsMap = <String, dynamic>{};
    for (final key in settingsKeys) {
      final value = prefs.get(key);
      if (value != null) {
        settingsMap[key] = value;
      }
    }
    result['settings'] = settingsMap;

    return result;
  }

  // ---------- 媒体库配置收集 ----------

  /// 收集媒体库配置数据
  ///
  /// 包含：
  /// - 本地媒体库路径
  /// - 在线媒体库（Emby/Jellyfin）服务器配置和选中的媒体库
  /// - WebDAV 连接配置
  /// - SMB 连接配置
  /// - 弹弹play远程服务配置
  /// - Nipaplay 媒体库共享配置
  Future<Map<String, dynamic>> _collectMediaLibraries() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};

    // 1. 收集本地媒体库路径
    final scannedFolders = prefs.getStringList('nipaplay_scanned_folders');
    result['localMediaLibraries'] = scannedFolders ?? [];

    // 2. 收集在线媒体库服务器配置
    final serverProfiles = await _collectServerProfiles();
    result['serverProfiles'] = serverProfiles;

    // 3. 收集 Emby 选中的媒体库
    final embySelectedLibs = prefs.getStringList('emby_selected_library_ids');
    if (embySelectedLibs != null) {
      result['embySelectedLibraryIds'] = embySelectedLibs;
    }

    // 4. 收集 Jellyfin 选中的媒体库
    final jellyfinSelectedLibs =
        prefs.getStringList('jellyfin_selected_library_ids');
    if (jellyfinSelectedLibs != null) {
      result['jellyfinSelectedLibraryIds'] = jellyfinSelectedLibs;
    }

    // 5. 收集排序设置
    final embySortSettings = prefs.getString('emby_library_sort_settings');
    if (embySortSettings != null) {
      result['embyLibrarySortSettings'] = embySortSettings;
    }
    final jellyfinSortSettings =
        prefs.getString('jellyfin_library_sort_settings');
    if (jellyfinSortSettings != null) {
      result['jellyfinLibrarySortSettings'] = jellyfinSortSettings;
    }

    // 6. 收集 WebDAV 连接配置
    try {
      final webdavService = WebDAVService.instance;
      await webdavService.initialize();
      final webdavConnections = webdavService.connections;
      result['webdavConnections'] =
          webdavConnections.map((c) => c.toJson()).toList();
    } catch (e) {
      debugPrint('收集WebDAV连接配置失败: $e');
    }

    // 7. 收集 SMB 连接配置
    try {
      final smbService = SMBService.instance;
      await smbService.initialize();
      final smbConnections = smbService.connections;
      result['smbConnections'] = smbConnections.map((c) => c.toJson()).toList();
    } catch (e) {
      debugPrint('收集SMB连接配置失败: $e');
    }

    // 8. 收集弹弹play远程服务配置
    try {
      final remoteService = DandanplayRemoteService.instance;
      await remoteService.loadSavedSettings(backgroundRefresh: true);
      if (remoteService.serverUrl != null &&
          remoteService.serverUrl!.isNotEmpty) {
        result['dandanplayRemote'] = {
          'baseUrl': prefs.getString('dandanplay_remote_base_url'),
          'apiToken': prefs.getString('dandanplay_remote_api_token'),
          'tokenRequired':
              prefs.getBool('dandanplay_remote_token_required') ?? false,
        };
      } else {
        result['dandanplayRemote'] = null;
      }
    } catch (e) {
      debugPrint('收集弹弹play远程服务配置失败: $e');
    }

    // 9. 收集 Nipaplay 媒体库共享（Web服务器）配置
    final webServerAutoStart = prefs.getBool('web_server_auto_start') ??
        prefs.getBool('web_server_enabled') ??
        false;
    final webServerPort = prefs.getInt('web_server_port');
    final webServerIpv6Enabled =
        prefs.getBool('web_server_ipv6_enabled') ?? false;
    result['nipaplayShare'] = {
      'autoStart': webServerAutoStart,
      'port': webServerPort ?? 1180,
      'ipv6Enabled': webServerIpv6Enabled,
    };

    return result;
  }

  /// 收集服务器配置列表
  Future<List<Map<String, dynamic>>> _collectServerProfiles() async {
    try {
      await MultiAddressServerService.instance.loadProfiles();
      final profiles = MultiAddressServerService.instance.profiles;
      return profiles.map((p) => p.toJson()).toList();
    } catch (e) {
      debugPrint('收集服务器配置失败: $e');
      return [];
    }
  }

  // ---------- 观看历史收集 ----------

  /// 收集观看历史数据
  ///
  /// [includeThumbnails] 是否包含截图的 base64 数据
  Future<List<Map<String, dynamic>>> _collectWatchHistory(
    List<WatchHistoryItem> historyItems, {
    bool includeThumbnails = true,
  }) async {
    try {
      final resultList = <Map<String, dynamic>>[];
      // Limit concurrent file reads so large thumbnail collections do not
      // block the UI isolate or exhaust file descriptors.
      const readConcurrency = 8;
      for (var offset = 0;
          offset < historyItems.length;
          offset += readConcurrency) {
        final end = (offset + readConcurrency).clamp(0, historyItems.length);
        resultList.addAll(await Future.wait(
          historyItems
              .sublist(offset, end)
              .map((item) => _collectWatchHistoryItem(
                    item,
                    includeThumbnail: includeThumbnails,
                  )),
        ));
      }

      return resultList;
    } catch (e) {
      debugPrint('收集观看历史失败: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> _collectWatchHistoryItem(
    WatchHistoryItem item, {
    required bool includeThumbnail,
  }) async {
    final recordData = <String, dynamic>{
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
      'videoHash': item.videoHash,
    };
    if (includeThumbnail && item.thumbnailPath != null) {
      try {
        final thumbnailFile = File(item.thumbnailPath!);
        if (await thumbnailFile.exists()) {
          recordData['thumbnailBase64'] =
              base64Encode(await thumbnailFile.readAsBytes());
        }
      } catch (e) {
        debugPrint('读取截图文件失败: ${item.thumbnailPath}, 错误: $e');
      }
    }
    return recordData;
  }

  // ---------- 剧集匹配数据收集 ----------

  /// 收集已匹配的剧集数据
  ///
  /// 从观看历史中提取所有已匹配（有 animeId 和 episodeId）的记录
  List<Map<String, dynamic>> _collectEpisodeMatches(
      List<WatchHistoryItem> historyItems) {
    try {
      // 只收集已匹配的记录（animeId 和 episodeId 都不为空）
      final matchedItems = historyItems
          .where((item) => item.animeId != null && item.episodeId != null)
          .map((item) => {
                'filePath': item.filePath,
                'animeName': item.animeName,
                'episodeTitle': item.episodeTitle,
                'episodeId': item.episodeId,
                'animeId': item.animeId,
                'videoHash': item.videoHash,
                'isFromScan': item.isFromScan,
              })
          .toList();

      return matchedItems.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('收集剧集匹配数据失败: $e');
      return [];
    }
  }

  // ---------- 账户绑定数据收集 ----------

  /// 收集账户绑定数据
  ///
  /// 包含：
  /// - 弹弹play 账户信息
  /// - Bangumi 独立账户信息（令牌登录）
  /// - 弹弹play 内绑定的 Bangumi 信息
  /// - Emby/Jellyfin 服务器账户（accessToken、userId）
  Future<Map<String, dynamic>> _collectAccounts() async {
    final result = <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();

    // 1. 弹弹play 账户
    final dandanplayAccount = <String, dynamic>{};
    final dandanplayLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    dandanplayAccount['isLoggedIn'] = dandanplayLoggedIn;
    if (dandanplayLoggedIn) {
      dandanplayAccount['token'] = prefs.getString('dandanplay_token');
      dandanplayAccount['username'] = prefs.getString('dandanplay_username');
      dandanplayAccount['screenName'] =
          prefs.getString('dandanplay_screenname');
      dandanplayAccount['lastTokenRenewTime'] =
          prefs.getInt('last_token_renew_time');

      // 弹弹play 内绑定的 Bangumi 信息
      final linkedBangumiRaw =
          prefs.getString('dandanplay_linked_bangumi_account');
      if (linkedBangumiRaw != null) {
        try {
          dandanplayAccount['linkedBangumiAccount'] =
              json.decode(linkedBangumiRaw);
        } catch (_) {}
      }
      dandanplayAccount['loginTimestamp'] =
          prefs.getInt('dandanplay_login_timestamp');
    }
    result['dandanplay'] = dandanplayAccount;

    // 2. Bangumi 独立账户（通过令牌直接登录 Bangumi）
    final bangumiAccount = <String, dynamic>{};
    final bangumiLoggedIn = prefs.getBool('bangumi_logged_in') ?? false;
    bangumiAccount['isLoggedIn'] = bangumiLoggedIn;
    if (bangumiLoggedIn) {
      bangumiAccount['accessToken'] = prefs.getString('bangumi_access_token');
      final bangumiUserInfoRaw = prefs.getString('bangumi_user_info');
      if (bangumiUserInfoRaw != null) {
        try {
          bangumiAccount['userInfo'] = json.decode(bangumiUserInfoRaw);
        } catch (_) {}
      }
    }
    result['bangumi'] = bangumiAccount;

    // 3. Emby/Jellyfin 服务器账户（从 ServerProfile 中提取认证信息）
    try {
      await MultiAddressServerService.instance.loadProfiles();
      final profiles = MultiAddressServerService.instance.profiles;
      final serverAccounts = profiles
          .map((p) => {
                'id': p.id,
                'serverName': p.serverName,
                'serverType': p.serverType,
                'username': p.username,
                'accessToken': p.accessToken,
                'userId': p.userId,
                'serverId': p.serverId,
                'addresses': p.addresses.map((a) => a.toJson()).toList(),
              })
          .toList();
      result['serverAccounts'] = serverAccounts;
    } catch (e) {
      debugPrint('收集服务器账户信息失败: $e');
      result['serverAccounts'] = [];
    }

    return result;
  }

  // ==================== 导入（信息解析恢复） ====================

  /// 导入备份的恢复结果
  Future<BackupRestoreResult> importBackup({
    required String filePath,
    required Set<BackupCategory> categories,
  }) async {
    final result = BackupRestoreResult();

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('备份文件不存在: $filePath');
        return result;
      }

      final restorePlan =
          await IncrementalSyncNativeCodec.prepareFullBackupRestore(
        bytes: await file.readAsBytes(),
        categories: categories,
      );

      if (restorePlan.version > _backupFormatVersion) {
        debugPrint('不支持的备份格式版本: ${restorePlan.version}');
        return result;
      }

      if (restorePlan.preferencesJson.isNotEmpty) {
        result.preferencesResult = await _restorePreferences(
          await IncrementalSyncNativeCodec.decodeJsonMap(
              restorePlan.preferencesJson),
        );
      }
      if (restorePlan.mediaLibrariesJson.isNotEmpty) {
        result.mediaLibrariesResult = await _restoreMediaLibraries(
          await IncrementalSyncNativeCodec.decodeJsonMap(
              restorePlan.mediaLibrariesJson),
        );
      }
      if (restorePlan.watchHistoryBatches.isNotEmpty ||
          restorePlan.invalidWatchHistoryCount > 0) {
        final aggregate = CategoryRestoreResult()
          ..success = true
          ..skippedCount = restorePlan.invalidWatchHistoryCount;
        for (final batch in restorePlan.watchHistoryBatches) {
          _mergeCategoryResult(
            aggregate,
            await _restoreWatchHistory(
              await IncrementalSyncNativeCodec.decodeJsonList(batch),
            ),
          );
        }
        result.watchHistoryResult = aggregate;
      }
      if (restorePlan.episodeMatchBatches.isNotEmpty ||
          restorePlan.invalidEpisodeMatchCount > 0) {
        final aggregate = CategoryRestoreResult()
          ..success = true
          ..skippedCount = restorePlan.invalidEpisodeMatchCount;
        for (final batch in restorePlan.episodeMatchBatches) {
          _mergeCategoryResult(
            aggregate,
            await _restoreEpisodeMatches(
              await IncrementalSyncNativeCodec.decodeJsonList(batch),
            ),
          );
        }
        result.episodeMatchesResult = aggregate;
      }
      if (restorePlan.accountsJson.isNotEmpty) {
        result.accountsResult = await _restoreAccounts(
          await IncrementalSyncNativeCodec.decodeJsonMap(
              restorePlan.accountsJson),
        );
      }

      result.success = true;
      debugPrint('备份恢复完成');
    } catch (e) {
      debugPrint('导入备份失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  void _mergeCategoryResult(
    CategoryRestoreResult target,
    CategoryRestoreResult batch,
  ) {
    target.restoredCount += batch.restoredCount;
    target.skippedCount += batch.skippedCount;
    if (!batch.success) {
      target.success = false;
      target.errorMessage ??= batch.errorMessage;
    }
  }

  /// 从备份数据解析（不读文件），直接恢复
  Future<BackupRestoreResult> restoreFromData({
    required Map<String, dynamic> backupData,
    required Set<BackupCategory> categories,
  }) async {
    final result = BackupRestoreResult();

    try {
      final version = backupData['version'] as int? ?? 0;
      if (version > _backupFormatVersion) {
        debugPrint('不支持的备份格式版本: $version');
        return result;
      }

      if (categories.contains(BackupCategory.preferences) &&
          backupData.containsKey('preferences')) {
        result.preferencesResult = await _restorePreferences(
            backupData['preferences'] as Map<String, dynamic>);
      }
      if (categories.contains(BackupCategory.mediaLibraries) &&
          backupData.containsKey('mediaLibraries')) {
        result.mediaLibrariesResult = await _restoreMediaLibraries(
            backupData['mediaLibraries'] as Map<String, dynamic>);
      }
      if (categories.contains(BackupCategory.watchHistory) &&
          backupData.containsKey('watchHistory')) {
        result.watchHistoryResult = await _restoreWatchHistory(
            backupData['watchHistory'] as List<dynamic>);
      }
      if (categories.contains(BackupCategory.episodeMatches) &&
          backupData.containsKey('episodeMatches')) {
        result.episodeMatchesResult = await _restoreEpisodeMatches(
            backupData['episodeMatches'] as List<dynamic>);
      }
      if (categories.contains(BackupCategory.accounts) &&
          backupData.containsKey('accounts')) {
        result.accountsResult = await _restoreAccounts(
            backupData['accounts'] as Map<String, dynamic>);
      }

      result.success = true;
    } catch (e) {
      debugPrint('从数据恢复备份失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ---------- 偏好设置恢复 ----------

  Future<CategoryRestoreResult> _restorePreferences(
      Map<String, dynamic> preferencesData) async {
    final result = CategoryRestoreResult();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 恢复软件设置
      final settings = preferencesData['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        int restoredCount = 0;
        for (final entry in settings.entries) {
          try {
            final key = entry.key;
            final value = entry.value;
            if (value is bool) {
              await prefs.setBool(key, value);
            } else if (value is int) {
              await prefs.setInt(key, value);
            } else if (value is double) {
              await prefs.setDouble(key, value);
            } else if (value is String) {
              await prefs.setString(key, value);
            } else if (value is List) {
              await prefs.setStringList(
                  key, value.map((e) => e.toString()).toList());
            }
            restoredCount++;
          } catch (e) {
            debugPrint('恢复设置项 ${entry.key} 失败: $e');
          }
        }
        result.restoredCount = restoredCount;
        debugPrint('恢复了 $restoredCount 项偏好设置');
      }

      result.success = true;
    } catch (e) {
      debugPrint('恢复偏好设置失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ---------- 媒体库配置恢复 ----------

  Future<CategoryRestoreResult> _restoreMediaLibraries(
      Map<String, dynamic> mediaLibrariesData) async {
    final result = CategoryRestoreResult();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 恢复本地媒体库路径
      final localLibs =
          mediaLibrariesData['localMediaLibraries'] as List<dynamic>?;
      if (localLibs != null) {
        final folderList = localLibs.cast<String>().toList();
        await prefs.setStringList('nipaplay_scanned_folders', folderList);
        result.localLibraryCount = folderList.length;
        debugPrint('恢复了 ${folderList.length} 个本地媒体库路径');
      }

      // 2. 恢复在线媒体库服务器配置
      final serverProfilesData =
          mediaLibrariesData['serverProfiles'] as List<dynamic>?;
      if (serverProfilesData != null) {
        final profiles = serverProfilesData
            .map((p) => ServerProfile.fromJson(p as Map<String, dynamic>))
            .toList();

        // 合并而非替换：保留本地已有的、添加备份中新增的
        await MultiAddressServerService.instance.loadProfiles();
        final existingProfiles = MultiAddressServerService.instance.profiles;

        // 保存合并后的配置
        final mergedProfiles = <ServerProfile>[...existingProfiles];
        for (final profile in profiles) {
          final existingIndex =
              mergedProfiles.indexWhere((p) => p.id == profile.id);
          if (existingIndex == -1) {
            mergedProfiles.add(profile);
          } else {
            // 已存在则更新（备份覆盖本地）
            mergedProfiles[existingIndex] = profile;
          }
        }

        final prefsInstance = await SharedPreferences.getInstance();
        final profilesJson =
            json.encode(mergedProfiles.map((p) => p.toJson()).toList());
        await prefsInstance.setString('server_profiles', profilesJson);

        result.serverProfileCount = profiles.length;
        debugPrint('恢复了 ${profiles.length} 个服务器配置');
      }

      // 3. 恢复选中的媒体库
      final embySelectedLibs =
          mediaLibrariesData['embySelectedLibraryIds'] as List<dynamic>?;
      if (embySelectedLibs != null) {
        await prefs.setStringList('emby_selected_library_ids',
            embySelectedLibs.cast<String>().toList());
      }

      final jellyfinSelectedLibs =
          mediaLibrariesData['jellyfinSelectedLibraryIds'] as List<dynamic>?;
      if (jellyfinSelectedLibs != null) {
        await prefs.setStringList('jellyfin_selected_library_ids',
            jellyfinSelectedLibs.cast<String>().toList());
      }

      // 4. 恢复排序设置
      final embySortSettings =
          mediaLibrariesData['embyLibrarySortSettings'] as String?;
      if (embySortSettings != null) {
        await prefs.setString('emby_library_sort_settings', embySortSettings);
      }

      final jellyfinSortSettings =
          mediaLibrariesData['jellyfinLibrarySortSettings'] as String?;
      if (jellyfinSortSettings != null) {
        await prefs.setString(
            'jellyfin_library_sort_settings', jellyfinSortSettings);
      }

      // 5. 恢复 WebDAV 连接配置（合并：按 name 匹配，已存在则更新，不存在则新增）
      final webdavConnectionsData =
          mediaLibrariesData['webdavConnections'] as List<dynamic>?;
      if (webdavConnectionsData != null && webdavConnectionsData.isNotEmpty) {
        try {
          final webdavService = WebDAVService.instance;
          await webdavService.initialize();
          final existingConnections = webdavService.connections;
          final existingNames = existingConnections.map((c) => c.name).toSet();

          for (final connData in webdavConnectionsData) {
            try {
              final connection =
                  WebDAVConnection.fromJson(connData as Map<String, dynamic>);
              if (existingNames.contains(connection.name)) {
                await webdavService.removeConnection(connection.name);
              }
              await webdavService.addConnection(connection);
            } catch (e) {
              debugPrint('恢复单条WebDAV连接失败: $e');
            }
          }
          debugPrint('恢复了 ${webdavConnectionsData.length} 个WebDAV连接');
        } catch (e) {
          debugPrint('恢复WebDAV连接配置失败: $e');
        }
      }

      // 6. 恢复 SMB 连接配置（合并：按 name 匹配）
      final smbConnectionsData =
          mediaLibrariesData['smbConnections'] as List<dynamic>?;
      if (smbConnectionsData != null && smbConnectionsData.isNotEmpty) {
        try {
          final smbService = SMBService.instance;
          await smbService.initialize();
          final existingConnections = smbService.connections;
          final existingNames = existingConnections.map((c) => c.name).toSet();

          for (final connData in smbConnectionsData) {
            try {
              final connection =
                  SMBConnection.fromJson(connData as Map<String, dynamic>);
              if (existingNames.contains(connection.name)) {
                await smbService.updateConnection(connection.name, connection);
              } else {
                await smbService.addConnection(connection);
              }
            } catch (e) {
              debugPrint('恢复单条SMB连接失败: $e');
            }
          }
          debugPrint('恢复了 ${smbConnectionsData.length} 个SMB连接');
        } catch (e) {
          debugPrint('恢复SMB连接配置失败: $e');
        }
      }

      // 7. 恢复弹弹play远程服务配置
      final dandanplayRemoteData =
          mediaLibrariesData['dandanplayRemote'] as Map<String, dynamic>?;
      if (dandanplayRemoteData != null) {
        try {
          final baseUrl = dandanplayRemoteData['baseUrl'] as String?;
          if (baseUrl != null && baseUrl.isNotEmpty) {
            final apiToken = dandanplayRemoteData['apiToken'] as String?;
            // 使用 connect 方法恢复连接（会验证并持久化）
            await DandanplayRemoteService.instance
                .connect(baseUrl, token: apiToken);
            debugPrint('恢复了弹弹play远程服务配置');
          }
        } catch (e) {
          // 如果连接验证失败，仍然保存配置到 SharedPreferences
          debugPrint('弹弹play远程服务连接验证失败，仍保存配置: $e');
          try {
            final baseUrl = dandanplayRemoteData['baseUrl'] as String?;
            if (baseUrl != null) {
              await prefs.setString('dandanplay_remote_base_url', baseUrl);
            }
            final apiToken = dandanplayRemoteData['apiToken'] as String?;
            if (apiToken != null) {
              await prefs.setString('dandanplay_remote_api_token', apiToken);
            }
            final tokenRequired =
                dandanplayRemoteData['tokenRequired'] as bool? ?? false;
            await prefs.setBool(
                'dandanplay_remote_token_required', tokenRequired);
          } catch (_) {}
        }
      }

      // 8. 恢复 Nipaplay 媒体库共享（Web服务器）配置
      final nipaplayShareData =
          mediaLibrariesData['nipaplayShare'] as Map<String, dynamic>?;
      if (nipaplayShareData != null) {
        final autoStart = nipaplayShareData['autoStart'] as bool? ?? false;
        final port = nipaplayShareData['port'] as int? ?? 1180;
        final ipv6Enabled = nipaplayShareData['ipv6Enabled'] as bool? ?? false;

        await prefs.setBool('web_server_auto_start', autoStart);
        await prefs.setInt('web_server_port', port);
        await prefs.setBool('web_server_ipv6_enabled', ipv6Enabled);
        debugPrint('恢复了Nipaplay媒体库共享配置');
      }

      result.success = true;
    } catch (e) {
      debugPrint('恢复媒体库配置失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ---------- 观看历史恢复 ----------

  Future<CategoryRestoreResult> _restoreWatchHistory(
      List<dynamic> watchHistoryData) async {
    final result = CategoryRestoreResult();

    try {
      final database = WatchHistoryDatabase.instance;
      final items = <WatchHistoryItem>[];

      for (final itemData in watchHistoryData) {
        try {
          final recordData = Map<String, dynamic>.from(itemData as Map);

          final item = WatchHistoryItem(
            filePath: recordData['filePath'] as String,
            animeName: recordData['animeName'] as String,
            episodeTitle: recordData['episodeTitle'] as String?,
            episodeId: (recordData['episodeId'] as num?)?.toInt(),
            animeId: (recordData['animeId'] as num?)?.toInt(),
            watchProgress: (recordData['watchProgress'] ?? 0.0).toDouble(),
            lastPosition: (recordData['lastPosition'] as num?)?.toInt() ?? 0,
            duration: (recordData['duration'] as num?)?.toInt() ?? 0,
            lastWatchTime:
                DateTime.parse(recordData['lastWatchTime'] as String),
            isFromScan: recordData['isFromScan'] as bool? ?? false,
            videoHash: recordData['videoHash'] as String?,
          );

          // 恢复截图
          String? restoredThumbnailPath;
          final thumbnailBase64 = recordData['thumbnailBase64'] as String?;
          if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
            restoredThumbnailPath =
                await _restoreThumbnail(item.filePath, thumbnailBase64);
          }

          items.add(item.copyWith(thumbnailPath: restoredThumbnailPath));
        } catch (e) {
          debugPrint('恢复单条观看历史失败: $e');
          result.skippedCount++;
          continue;
        }
      }

      final merged = await database.mergeWatchHistoryBatch(items);
      await _updateSharedPreferencesPositions(merged.restoredPositions);

      result.restoredCount = merged.restoredCount;
      result.skippedCount += merged.skippedCount;
      result.success = true;
      debugPrint(
          '观看历史恢复完成: 恢复 ${result.restoredCount} 条，跳过 ${result.skippedCount} 条');
    } catch (e) {
      debugPrint('恢复观看历史失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ---------- 剧集匹配数据恢复 ----------

  Future<CategoryRestoreResult> _restoreEpisodeMatches(
      List<dynamic> episodeMatchesData) async {
    final result = CategoryRestoreResult();

    try {
      final database = WatchHistoryDatabase.instance;
      final matches = <EpisodeMatchRestoreItem>[];

      for (final matchData in episodeMatchesData) {
        try {
          final recordData = Map<String, dynamic>.from(matchData as Map);
          final filePath = recordData['filePath'] as String;
          final animeId = (recordData['animeId'] as num?)?.toInt();
          final episodeId = (recordData['episodeId'] as num?)?.toInt();

          if (animeId == null || episodeId == null) {
            result.skippedCount++;
            continue;
          }
          matches.add(EpisodeMatchRestoreItem(
            filePath: filePath,
            animeId: animeId,
            episodeId: episodeId,
            animeName: recordData['animeName'] as String?,
            episodeTitle: recordData['episodeTitle'] as String?,
            videoHash: recordData['videoHash'] as String?,
          ));
        } catch (e) {
          debugPrint('恢复单条剧集匹配失败: $e');
          result.skippedCount++;
          continue;
        }
      }

      final merged = await database.mergeEpisodeMatchBatch(matches);

      result.restoredCount = merged.restoredCount;
      result.skippedCount += merged.skippedCount;
      result.success = true;
      debugPrint(
          '剧集匹配恢复完成: 恢复 ${result.restoredCount} 条，跳过 ${result.skippedCount} 条');
    } catch (e) {
      debugPrint('恢复剧集匹配数据失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ---------- 账户绑定数据恢复 ----------

  Future<CategoryRestoreResult> _restoreAccounts(
      Map<String, dynamic> accountsData) async {
    final result = CategoryRestoreResult();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 恢复弹弹play 账户
      final dandanplayData =
          accountsData['dandanplay'] as Map<String, dynamic>?;
      if (dandanplayData != null) {
        final isLoggedIn = dandanplayData['isLoggedIn'] as bool? ?? false;
        if (isLoggedIn) {
          final token = dandanplayData['token'] as String?;
          if (token != null) {
            await prefs.setString('dandanplay_token', token);
          }
          final username = dandanplayData['username'] as String?;
          if (username != null) {
            await prefs.setString('dandanplay_username', username);
          }
          final screenName = dandanplayData['screenName'] as String?;
          if (screenName != null) {
            await prefs.setString('dandanplay_screenname', screenName);
          }
          await prefs.setBool('dandanplay_logged_in', true);

          final lastRenewTime = dandanplayData['lastTokenRenewTime'] as int?;
          if (lastRenewTime != null) {
            await prefs.setInt('last_token_renew_time', lastRenewTime);
          }

          // 弹弹play 内绑定的 Bangumi 信息
          final linkedBangumi =
              dandanplayData['linkedBangumiAccount'] as Map<String, dynamic>?;
          if (linkedBangumi != null) {
            await prefs.setString(
              'dandanplay_linked_bangumi_account',
              json.encode(linkedBangumi),
            );
          }

          final loginTimestamp = dandanplayData['loginTimestamp'] as int?;
          if (loginTimestamp != null) {
            await prefs.setInt('dandanplay_login_timestamp', loginTimestamp);
          }

          result.dandanplayRestored = true;
          debugPrint('恢复了弹弹play账户信息');
        }
      }

      // 2. 恢复 Bangumi 独立账户
      final bangumiData = accountsData['bangumi'] as Map<String, dynamic>?;
      if (bangumiData != null) {
        final bangumiLoggedIn = bangumiData['isLoggedIn'] as bool? ?? false;
        if (bangumiLoggedIn) {
          final accessToken = bangumiData['accessToken'] as String?;
          if (accessToken != null) {
            await prefs.setString('bangumi_access_token', accessToken);
          }
          final userInfo = bangumiData['userInfo'] as Map<String, dynamic>?;
          if (userInfo != null) {
            await prefs.setString('bangumi_user_info', json.encode(userInfo));
          }
          await prefs.setBool('bangumi_logged_in', true);

          result.bangumiRestored = true;
          debugPrint('恢复了Bangumi独立账户信息');
        }
      }

      // 3. 恢复 Emby/Jellyfin 服务器账户
      final serverAccountsData =
          accountsData['serverAccounts'] as List<dynamic>?;
      if (serverAccountsData != null && serverAccountsData.isNotEmpty) {
        // 合并到现有的服务器配置中
        await MultiAddressServerService.instance.loadProfiles();
        final existingProfiles = MultiAddressServerService.instance.profiles;
        final mergedProfiles = <ServerProfile>[...existingProfiles];

        for (final accountData in serverAccountsData) {
          try {
            final data = accountData as Map<String, dynamic>;
            final profile = ServerProfile.fromJson(data);

            final existingIndex =
                mergedProfiles.indexWhere((p) => p.id == profile.id);
            if (existingIndex == -1) {
              mergedProfiles.add(profile);
            } else {
              // 更新认证信息（accessToken、userId），保留本地连接状态
              final existing = mergedProfiles[existingIndex];
              mergedProfiles[existingIndex] = existing.copyWith(
                accessToken: profile.accessToken ?? existing.accessToken,
                userId: profile.userId ?? existing.userId,
              );
            }
          } catch (e) {
            debugPrint('恢复服务器账户失败: $e');
          }
        }

        final prefsInstance = await SharedPreferences.getInstance();
        final profilesJson =
            json.encode(mergedProfiles.map((p) => p.toJson()).toList());
        await prefsInstance.setString('server_profiles', profilesJson);

        result.serverAccountCount = serverAccountsData.length;
        debugPrint('恢复了 ${serverAccountsData.length} 个服务器账户');
      }

      result.success = true;
    } catch (e) {
      debugPrint('恢复账户绑定数据失败: $e');
      result.success = false;
      result.errorMessage = e.toString();
    }

    return result;
  }

  // ==================== 辅助方法 ====================

  /// 递归净化备份数据中的非法 double（Infinity/NaN）
  ///
  /// JSON 标准不支持 Infinity/NaN，遇到会抛
  /// "Converting object to an encoding object failed: Infinity"。
  /// 观看历史的 watchProgress 在播放器 duration=0 时可能被算成
  /// Infinity/NaN 落库（iOS 流媒体 duration 延迟就绪时易发），
  /// 源头已加除零保护，这里在编码前再做兜底，保证备份永不因此失败，
  /// 同时也能净化历史遗留的脏数据。
  static dynamic _sanitizeForJson(dynamic value) {
    if (value is double) {
      return value.isInfinite || value.isNaN ? 0.0 : value;
    }
    if (value is Map) {
      // JSON 对象的键只能是字符串。这里显式生成 Map<String, dynamic>，
      // 避免在 `value is Map` 类型提升后，Map.map 推断出
      // Map<dynamic, dynamic>，导致 collectBackupData 返回时强转失败。
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeForJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_sanitizeForJson).toList();
    }
    return value;
  }

  /// 恢复截图文件
  Future<String?> _restoreThumbnail(
      String filePath, String thumbnailBase64) async {
    try {
      final thumbnailBytes = base64Decode(thumbnailBase64);
      final appDir = await StorageService.getAppStorageDirectory();
      final thumbnailsDir = Directory(path.join(appDir.path, 'thumbnails'));

      if (!thumbnailsDir.existsSync()) {
        await thumbnailsDir.create(recursive: true);
      }

      final pathHash =
          sha256.convert(utf8.encode(filePath)).toString().substring(0, 16);
      final videoName = path.basenameWithoutExtension(filePath);
      final thumbnailFileName = '${videoName}_${pathHash}_thumbnail.jpg';
      final thumbnailPath = path.join(thumbnailsDir.path, thumbnailFileName);

      final thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes(thumbnailBytes);

      return thumbnailPath;
    } catch (e) {
      debugPrint('恢复截图失败: $e');
      return null;
    }
  }

  /// Batch-updates SharedPreferences playback positions once per restore
  /// batch instead of decoding and writing the whole map for every row.
  Future<void> _updateSharedPreferencesPositions(
      Map<String, int> updates) async {
    if (updates.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      const String videoPositionsKey = 'video_positions';

      final positions = prefs.getString(videoPositionsKey) ?? '{}';
      final Map<String, dynamic> positionMap =
          Map<String, dynamic>.from(json.decode(positions));

      positionMap.addAll(updates);

      await prefs.setString(videoPositionsKey, json.encode(positionMap));
    } catch (e) {
      debugPrint('更新 SharedPreferences 播放位置失败: $e');
    }
  }

  /// 构建类别后缀字符串
  String _buildCategorySuffix(Set<BackupCategory> categories) {
    if (categories.length == BackupCategory.values.length) {
      return 'full';
    }
    final parts = <String>[];
    if (categories.contains(BackupCategory.preferences)) parts.add('pref');
    if (categories.contains(BackupCategory.mediaLibraries)) parts.add('lib');
    if (categories.contains(BackupCategory.watchHistory)) parts.add('hist');
    if (categories.contains(BackupCategory.episodeMatches)) parts.add('match');
    if (categories.contains(BackupCategory.accounts)) parts.add('acct');
    return parts.join('_');
  }

  /// 读取备份文件信息（不执行恢复），用于预览
  Future<BackupPreviewInfo?> previewBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final backupData = await IncrementalSyncNativeCodec.decodeJsonMap(
        await file.readAsBytes(),
      );

      return BackupPreviewInfo(
        version: backupData['version'] as int? ?? 0,
        timestamp: backupData['timestamp'] as String? ?? '',
        appVersion: backupData['appVersion'] as String? ?? '',
        hasPreferences: backupData.containsKey('preferences'),
        hasMediaLibraries: backupData.containsKey('mediaLibraries'),
        hasWatchHistory: backupData.containsKey('watchHistory'),
        hasEpisodeMatches: backupData.containsKey('episodeMatches'),
        hasAccounts: backupData.containsKey('accounts'),
        watchHistoryCount:
            (backupData['watchHistory'] as List<dynamic>?)?.length ?? 0,
        episodeMatchCount:
            (backupData['episodeMatches'] as List<dynamic>?)?.length ?? 0,
        serverProfileCount:
            (backupData['mediaLibraries']?['serverProfiles'] as List<dynamic>?)
                    ?.length ??
                0,
        localLibraryCount: (backupData['mediaLibraries']?['localMediaLibraries']
                    as List<dynamic>?)
                ?.length ??
            0,
        webdavConnectionCount: (backupData['mediaLibraries']
                    ?['webdavConnections'] as List<dynamic>?)
                ?.length ??
            0,
        smbConnectionCount:
            (backupData['mediaLibraries']?['smbConnections'] as List<dynamic>?)
                    ?.length ??
                0,
        hasDandanplayRemote:
            backupData['mediaLibraries']?['dandanplayRemote'] != null,
        hasNipaplayShare:
            backupData['mediaLibraries']?['nipaplayShare'] != null,
      );
    } catch (e) {
      debugPrint('预览备份文件失败: $e');
      return null;
    }
  }
}

/// 备份恢复总结果
class BackupRestoreResult {
  bool success = false;
  String? errorMessage;

  CategoryRestoreResult? preferencesResult;
  CategoryRestoreResult? mediaLibrariesResult;
  CategoryRestoreResult? watchHistoryResult;
  CategoryRestoreResult? episodeMatchesResult;
  CategoryRestoreResult? accountsResult;

  /// 获取恢复的总记录数
  int get totalRestoredCount {
    return (preferencesResult?.restoredCount ?? 0) +
        (watchHistoryResult?.restoredCount ?? 0) +
        (episodeMatchesResult?.restoredCount ?? 0) +
        (accountsResult?.restoredCount ?? 0);
  }

  /// 获取跳过的总记录数
  int get totalSkippedCount {
    return (watchHistoryResult?.skippedCount ?? 0) +
        (episodeMatchesResult?.skippedCount ?? 0);
  }
}

/// 单个类别的恢复结果
class CategoryRestoreResult {
  bool success = false;
  String? errorMessage;
  int restoredCount = 0;
  int skippedCount = 0;

  // 偏好设置特有
  int localLibraryCount = 0;
  int serverProfileCount = 0;

  // 账户特有
  bool dandanplayRestored = false;
  bool bangumiRestored = false;
  int serverAccountCount = 0;
}

/// 备份预览信息
class BackupPreviewInfo {
  final int version;
  final String timestamp;
  final String appVersion;
  final bool hasPreferences;
  final bool hasMediaLibraries;
  final bool hasWatchHistory;
  final bool hasEpisodeMatches;
  final bool hasAccounts;
  final int watchHistoryCount;
  final int episodeMatchCount;
  final int serverProfileCount;
  final int localLibraryCount;
  final int webdavConnectionCount;
  final int smbConnectionCount;
  final bool hasDandanplayRemote;
  final bool hasNipaplayShare;

  BackupPreviewInfo({
    required this.version,
    required this.timestamp,
    required this.appVersion,
    required this.hasPreferences,
    required this.hasMediaLibraries,
    required this.hasWatchHistory,
    required this.hasEpisodeMatches,
    required this.hasAccounts,
    required this.watchHistoryCount,
    required this.episodeMatchCount,
    required this.serverProfileCount,
    required this.localLibraryCount,
    this.webdavConnectionCount = 0,
    this.smbConnectionCount = 0,
    this.hasDandanplayRemote = false,
    this.hasNipaplayShare = false,
  });
}
