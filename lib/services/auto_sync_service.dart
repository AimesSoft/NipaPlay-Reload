import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/backup_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/models/watch_history_database.dart';

class AutoSyncService {
  static AutoSyncService? _instance;
  static AutoSyncService get instance => _instance ??= AutoSyncService._();
  
  AutoSyncService._();
  
  Timer? _syncTimer;
  bool _isInitialized = false;
  bool _isSyncing = false;
  
  final BackupService _backupService = BackupService();
  
  /// 初始化自动同步服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final enabled = await AutoSyncSettings.isEnabled();
      if (enabled) {
        await _startAutoSync();
        // 启动时自动从云端恢复
        await _restoreFromCloud();
      }
      
      _isInitialized = true;
      debugPrint('自动同步服务初始化完成，状态: ${enabled ? "启用" : "禁用"}');
    } catch (e) {
      debugPrint('自动同步服务初始化失败: $e');
    }
  }
  
  /// 启用自动同步
  Future<void> enable(String syncPath) async {
    try {
      // 保存设置
      await AutoSyncSettings.setEnabled(true);
      await AutoSyncSettings.setSyncPath(syncPath);
      
      // 启动自动同步
      await _startAutoSync();
      
      // 立即执行一次备份
      await _backupToCloud();
      
      debugPrint('自动同步已启用，路径: $syncPath');
    } catch (e) {
      debugPrint('启用自动同步失败: $e');
      rethrow;
    }
  }
  
  /// 禁用自动同步
  Future<void> disable() async {
    try {
      await AutoSyncSettings.setEnabled(false);
      _stopAutoSync();
      
      debugPrint('自动同步已禁用');
    } catch (e) {
      debugPrint('禁用自动同步失败: $e');
    }
  }
  
  /// 检查自动同步是否启用
  Future<bool> isEnabled() async {
    return await AutoSyncSettings.isEnabled();
  }
  
  /// 获取同步路径
  Future<String?> getSyncPath() async {
    return await AutoSyncSettings.getSyncPath();
  }
  
  /// 手动触发同步
  Future<void> manualSync() async {
    if (_isSyncing) {
      debugPrint('同步正在进行中，跳过手动同步');
      return;
    }
    
    final enabled = await AutoSyncSettings.isEnabled();
    if (!enabled) {
      debugPrint('自动同步未启用，跳过手动同步');
      return;
    }
    
    await _performSync();
  }
  
  /// 启动自动同步定时器
  Future<void> _startAutoSync() async {
    _stopAutoSync(); // 先停止现有的定时器
    
    // 每30秒检查一次是否需要同步
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isSyncing) {
        await _performSync();
      }
    });
    
    debugPrint('自动同步定时器已启动');
  }
  
  /// 停止自动同步定时器
  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('自动同步定时器已停止');
  }
  
  /// 执行同步操作
  Future<void> _performSync() async {
    if (_isSyncing) return;
    
    try {
      _isSyncing = true;
      
      // 先尝试从云端恢复（如果云端文件更新）
      await _restoreFromCloud();
      
      // 然后备份到云端
      await _backupToCloud();
      
    } catch (e) {
      debugPrint('自动同步失败: $e');
    } finally {
      _isSyncing = false;
    }
  }
  
  /// 备份到云端
  Future<void> _backupToCloud() async {
    try {
      final filePath = await AutoSyncSettings.getSyncFilePath();
      if (filePath == null) {
        debugPrint('同步文件路径未配置');
        return;
      }
      
      // 确保目录存在
      final file = File(filePath);
      final directory = file.parent;
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      
      // 获取所有观看历史
      final database = WatchHistoryDatabase.instance;
      final historyItems = await database.getAllWatchHistory();
      
      if (historyItems.isEmpty) {
        debugPrint('没有观看历史需要同步');
        return;
      }
      
      // 创建备份数据并写入固定文件
      final backupData = await _backupService.createBackupData(historyItems);
      await file.writeAsBytes(backupData);
      
      debugPrint('自动同步备份完成: $filePath (${historyItems.length}条记录)');
    } catch (e) {
      debugPrint('自动备份到云端失败: $e');
    }
  }
  
  /// 从云端恢复
  Future<void> _restoreFromCloud() async {
    try {
      final filePath = await AutoSyncSettings.getSyncFilePath();
      if (filePath == null) {
        debugPrint('同步文件路径未配置');
        return;
      }
      
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('云端同步文件不存在: $filePath');
        return;
      }
      
      // 检查文件修改时间，避免重复恢复
      final lastModified = file.lastModifiedSync();
      final now = DateTime.now();
      
      // 如果文件太老（超过1小时没更新），跳过恢复
      if (now.difference(lastModified).inHours > 1) {
        debugPrint('云端文件过旧，跳过恢复: $filePath');
        return;
      }
      
      // 执行静默恢复
      final restoredCount = await _backupService.importWatchHistorySilent(filePath);
      
      if (restoredCount > 0) {
        debugPrint('自动同步恢复完成: $filePath ($restoredCount条记录)');
      }
    } catch (e) {
      debugPrint('自动从云端恢复失败: $e');
    }
  }
  
  /// 销毁服务
  void dispose() {
    _stopAutoSync();
    _instance = null;
  }
}