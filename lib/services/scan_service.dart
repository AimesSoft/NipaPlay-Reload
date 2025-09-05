import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/ios_container_path_fixer.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
// Import Provider if ScanService needs to directly refresh other providers,
// otherwise it will be refreshed by UI listening to this service.
// import 'package:provider/provider.dart';
// import 'package:nipaplay/providers/watch_history_provider.dart';

/// 文件夹变化信息
class FolderChangeInfo {
  final String folderPath;
  final String changeType; // 'modified', 'new', 'deleted'
  final List<String> changedFiles;
  final List<String> newFiles;
  final List<String> deletedFiles;
  final DateTime detectedAt;

  FolderChangeInfo({
    required this.folderPath,
    required this.changeType,
    this.changedFiles = const [],
    this.newFiles = const [],
    this.deletedFiles = const [],
    required this.detectedAt,
  });

  String get displayName => p.basename(folderPath);
  
  String get changeDescription {
    if (changeType == 'new') {
      return '新文件夹';
    } else if (changeType == 'deleted') {
      return '文件夹已删除';
    } else {
      List<String> changes = [];
      if (newFiles.isNotEmpty) {
        changes.add('新增${newFiles.length}个文件');
      }
      if (deletedFiles.isNotEmpty) {
        changes.add('删除${deletedFiles.length}个文件');
      }
      if (changedFiles.isNotEmpty) {
        changes.add('修改${changedFiles.length}个文件');
      }
      return changes.isEmpty ? '内容有变化' : changes.join('，');
    }
  }
}

class ScanService with ChangeNotifier {
  static const String _scannedFoldersPrefsKey = 'nipaplay_scanned_folders';
  static const String _folderHashCachePrefsKey = 'nipaplay_folder_hash_cache';
  static const String _subFolderHashCachePrefsKey = 'nipaplay_subfolder_hash_cache';
  // _lastScannedDirectoryPickerPathKey will likely remain in UI as it's picker-specific

  List<String> _scannedFolders = [];
  List<String> get scannedFolders => List.unmodifiable(_scannedFolders);

  // 文件夹hash缓存，用于判断文件夹是否有变化
  Map<String, String> _folderHashCache = {};
  
  // 子文件夹hash缓存，用于精确定位变化
  Map<String, Map<String, String>> _subFolderHashCache = {};
  
  // 启动时检测到的变化信息
  final List<FolderChangeInfo> _detectedChanges = [];
  List<FolderChangeInfo> get detectedChanges => List.unmodifiable(_detectedChanges);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  double _scanProgress = 0.0;
  double get scanProgress => _scanProgress;

  String _scanMessage = "";
  String get scanMessage => _scanMessage;

  // To allow UI to react to scan completion for specific actions like refreshing MediaLibraryPage
  bool _scanJustCompleted = false;
  bool get scanJustCompleted => _scanJustCompleted;
  void acknowledgeScanCompleted() { // UI calls this after reacting
    if (_scanJustCompleted) {
      _scanJustCompleted = false;
      // notifyListeners(); // Optional: if UI needs to rebuild based on this acknowledgement
    }
  }

  // 扫描是否刚结束的标志，用于检查扫描结果
  bool _justFinishedScanning = false;
  bool get justFinishedScanning => _justFinishedScanning;
  
  // 重置刚完成扫描的标志
  void resetJustFinishedScanning() {
    _justFinishedScanning = false;
  }
  
  // 扫描找到的文件数量
  int _totalFilesFound = 0;
  int get totalFilesFound => _totalFilesFound;

  ScanService() {
    _loadScannedFolders();
    _loadFolderHashCache();
    _loadSubFolderHashCache();
    // 启动时自动检测变化
    _performStartupChangeDetection();
  }

  Future<void> _loadScannedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> rawFolders = prefs.getStringList(_scannedFoldersPrefsKey) ?? [];
      
      // iOS平台：使用工具类修复容器路径变化并清理失效路径
      if (Platform.isIOS && rawFolders.isNotEmpty) {
        List<String> validFolders = [];
        int fixedCount = 0;
        int removedCount = 0;
        
        for (String folder in rawFolders) {
          final validPath = await iOSContainerPathFixer.validateAndFixDirectoryPath(folder);
          if (validPath != null) {
            validFolders.add(validPath);
            if (validPath != folder) {
              fixedCount++;
              debugPrint('ScanService: 修复扫描文件夹路径: $folder -> $validPath');
            }
          } else {
            // 路径无法修复且不存在，自动清理失效路径
            removedCount++;
            debugPrint('ScanService: 清理失效扫描文件夹路径: $folder');
          }
        }
        
        _scannedFolders = validFolders;
        
        // 如果有路径变化或清理了失效路径，保存更新后的路径列表
        if (fixedCount > 0 || removedCount > 0) {
          await prefs.setStringList(_scannedFoldersPrefsKey, validFolders);
          if (fixedCount > 0) {
            debugPrint('ScanService: 已修复 $fixedCount 个文件夹路径');
          }
          if (removedCount > 0) {
            debugPrint('ScanService: 已清理 $removedCount 个失效文件夹路径');
          }
        }
      } else {
        _scannedFolders = rawFolders;
      }
      
      notifyListeners();
    } catch (e) {
      //debugPrint("ScanService: Error loading scanned folders: $e");
      _updateScanMessage("加载已扫描文件夹列表失败: $e");
    }
  }

  Future<void> _saveScannedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_scannedFoldersPrefsKey, _scannedFolders);
      //debugPrint("ScanService: Scanned folders saved.");
    } catch (e) {
      //debugPrint("ScanService: Error saving scanned folders: $e");
      // UI should show this message if it's critical
    }
  }

  /// 加载文件夹hash缓存
  Future<void> _loadFolderHashCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_folderHashCachePrefsKey);
      if (cacheJson != null) {
        final Map<String, dynamic> cacheMap = json.decode(cacheJson);
        _folderHashCache = cacheMap.map((key, value) => MapEntry(key, value.toString()));
      }
      debugPrint("文件夹hash缓存已加载，包含 ${_folderHashCache.length} 个条目");
    } catch (e) {
      debugPrint("加载文件夹hash缓存失败: $e");
      _folderHashCache = {};
    }
  }

  /// 保存文件夹hash缓存
  Future<void> _saveFolderHashCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_folderHashCache);
      await prefs.setString(_folderHashCachePrefsKey, cacheJson);
      debugPrint("文件夹hash缓存已保存，包含 ${_folderHashCache.length} 个条目");
    } catch (e) {
      debugPrint("保存文件夹hash缓存失败: $e");
    }
  }

  /// 加载子文件夹hash缓存
  Future<void> _loadSubFolderHashCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_subFolderHashCachePrefsKey);
      if (cacheJson != null) {
        final Map<String, dynamic> cacheMap = json.decode(cacheJson);
        _subFolderHashCache = cacheMap.map((key, value) {
          if (value is Map<String, dynamic>) {
            return MapEntry(key, value.map((k, v) => MapEntry(k, v.toString())));
          }
          return MapEntry(key, <String, String>{});
        });
      }
      debugPrint("子文件夹hash缓存已加载，包含 ${_subFolderHashCache.length} 个主文件夹");
    } catch (e) {
      debugPrint("加载子文件夹hash缓存失败: $e");
      _subFolderHashCache = {};
    }
  }

  /// 保存子文件夹hash缓存
  Future<void> _saveSubFolderHashCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_subFolderHashCache);
      await prefs.setString(_subFolderHashCachePrefsKey, cacheJson);
      debugPrint("子文件夹hash缓存已保存，包含 ${_subFolderHashCache.length} 个主文件夹");
    } catch (e) {
      debugPrint("保存子文件夹hash缓存失败: $e");
    }
  }

  /// 计算文件夹的hash值
  /// 基于文件夹内所有视频文件的路径、大小和修改时间
  Future<String> _calculateFolderHash(String folderPath) async {
    if (kIsWeb) return ''; // Web平台无法访问本地文件系统
    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        return '';
      }

      List<String> fileInfoList = [];
      
      await for (var entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          String extension = p.extension(entity.path).toLowerCase();
          if (extension == '.mp4' || extension == '.mkv') {
            try {
              final stat = await entity.stat();
              // 组合文件路径、大小和修改时间作为hash输入
              final fileInfo = '${entity.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
              fileInfoList.add(fileInfo);
            } catch (e) {
              // 如果无法获取文件信息，使用文件路径作为备用
              fileInfoList.add(entity.path);
            }
          }
        }
      }

      // 排序确保hash的一致性
      fileInfoList.sort();
      
      // 计算整个列表的hash
      final combinedInfo = fileInfoList.join('\n');
      final bytes = utf8.encode(combinedInfo);
      final hash = sha256.convert(bytes).toString();
      
      debugPrint("文件夹 $folderPath 的hash计算完成: $hash (包含 ${fileInfoList.length} 个视频文件)");
      return hash;
    } catch (e) {
      debugPrint("计算文件夹hash失败 $folderPath: $e");
      return '';
    }
  }

  /// 检查文件夹是否有变化
  Future<bool> _hasFolderChanged(String folderPath) async {
    if (kIsWeb) return false; // 在Web上，假设没有变化
    final currentHash = await _calculateFolderHash(folderPath);
    final cachedHash = _folderHashCache[folderPath];
    
    if (cachedHash == null) {
      debugPrint("文件夹 $folderPath 没有缓存的hash，视为有变化");
      return true;
    }
    
    final hasChanged = currentHash != cachedHash;
    debugPrint("文件夹 $folderPath hash比较: ${hasChanged ? '有变化' : '无变化'} (当前: ${currentHash.substring(0, 8)}..., 缓存: ${cachedHash.substring(0, 8)}...)");
    return hasChanged;
  }

  /// 更新文件夹hash缓存
  Future<void> _updateFolderHash(String folderPath) async {
    if (kIsWeb) return;
    final currentHash = await _calculateFolderHash(folderPath);
    if (currentHash.isNotEmpty) {
      _folderHashCache[folderPath] = currentHash;
      await _saveFolderHashCache();
      debugPrint("已更新文件夹 $folderPath 的hash缓存");
    }
    
    // 同时更新子文件夹hash缓存
    final subFolderHashes = await _calculateSubFolderHashes(folderPath);
    _subFolderHashCache[folderPath] = subFolderHashes;
    await _saveSubFolderHashCache();
    debugPrint("已更新文件夹 $folderPath 的子文件夹hash缓存，包含 ${subFolderHashes.length} 个文件");
  }

  /// 清理不存在文件夹的hash缓存
  Future<void> _cleanupFolderHashCache() async {
    if (kIsWeb) return;
    final keysToRemove = <String>[];
    
    for (final folderPath in _folderHashCache.keys) {
      if (!_scannedFolders.contains(folderPath) || !await Directory(folderPath).exists()) {
        keysToRemove.add(folderPath);
      }
    }
    
    for (final key in keysToRemove) {
      _folderHashCache.remove(key);
      _subFolderHashCache.remove(key); // 同时清理子文件夹缓存
    }
    
    if (keysToRemove.isNotEmpty) {
      await _saveFolderHashCache();
      await _saveSubFolderHashCache();
      debugPrint("已清理 ${keysToRemove.length} 个无效的文件夹hash缓存");
    }
  }

  /// 清理所有文件夹hash缓存，强制下次扫描时重新检查所有文件夹
  Future<void> clearAllFolderHashCache() async {
    _folderHashCache.clear();
    _subFolderHashCache.clear();
    await _saveFolderHashCache();
    await _saveSubFolderHashCache();
    debugPrint("已清理所有文件夹hash缓存");
    _updateScanMessage("已清理智能扫描缓存，下次扫描将检查所有文件夹。");
  }

  /// 启动时执行变化检测
  Future<void> _performStartupChangeDetection() async {
    if (kIsWeb) return;
    if (_scannedFolders.isEmpty) {
      return;
    }

    debugPrint("开始启动时变化检测，检查 ${_scannedFolders.length} 个文件夹");
    _detectedChanges.clear();

    for (final folderPath in _scannedFolders) {
      try {
        final changes = await _detectDetailedFolderChanges(folderPath);
        if (changes != null) {
          _detectedChanges.add(changes);
        }
      } catch (e) {
        debugPrint("检测文件夹 $folderPath 变化时出错: $e");
      }
    }

    if (_detectedChanges.isNotEmpty) {
      debugPrint("启动时检测到 ${_detectedChanges.length} 个文件夹有变化");
      notifyListeners(); // 通知UI有变化检测结果
    } else {
      debugPrint("启动时检测完成，所有文件夹都没有变化");
    }
  }

  /// 详细检测文件夹变化，包括子文件夹级别的变化
  Future<FolderChangeInfo?> _detectDetailedFolderChanges(String folderPath) async {
    if (kIsWeb) return null;
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      // 文件夹已删除
      return FolderChangeInfo(
        folderPath: folderPath,
        changeType: 'deleted',
        detectedAt: DateTime.now(),
      );
    }

    // 检查主文件夹是否有变化
    final hasMainFolderChanged = await _hasFolderChanged(folderPath);
    if (!hasMainFolderChanged) {
      return null; // 没有变化
    }

    // 如果主文件夹有变化，进行详细分析
    final currentSubFolderHashes = await _calculateSubFolderHashes(folderPath);
    final cachedSubFolderHashes = _subFolderHashCache[folderPath] ?? {};

    List<String> newFiles = [];
    List<String> deletedFiles = [];
    List<String> changedFiles = [];

    // 检查新增和修改的子文件夹/文件
    for (final entry in currentSubFolderHashes.entries) {
      final subPath = entry.key;
      final currentHash = entry.value;
      final cachedHash = cachedSubFolderHashes[subPath];

      if (cachedHash == null) {
        newFiles.add(subPath);
      } else if (cachedHash != currentHash) {
        changedFiles.add(subPath);
      }
    }

    // 检查删除的子文件夹/文件
    for (final cachedPath in cachedSubFolderHashes.keys) {
      if (!currentSubFolderHashes.containsKey(cachedPath)) {
        deletedFiles.add(cachedPath);
      }
    }

    // 更新子文件夹hash缓存
    _subFolderHashCache[folderPath] = currentSubFolderHashes;
    await _saveSubFolderHashCache();

    if (newFiles.isEmpty && deletedFiles.isEmpty && changedFiles.isEmpty) {
      return null; // 虽然主文件夹hash变了，但可能是其他原因，没有实际的文件变化
    }

    return FolderChangeInfo(
      folderPath: folderPath,
      changeType: 'modified',
      newFiles: newFiles,
      deletedFiles: deletedFiles,
      changedFiles: changedFiles,
      detectedAt: DateTime.now(),
    );
  }

  /// 计算文件夹内所有子文件夹和视频文件的hash
  Future<Map<String, String>> _calculateSubFolderHashes(String folderPath) async {
    if (kIsWeb) return {};
    final Map<String, String> subHashes = {};
    final directory = Directory(folderPath);

    if (!await directory.exists()) {
      return subHashes;
    }

    try {
      await for (var entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          String extension = p.extension(entity.path).toLowerCase();
          if (extension == '.mp4' || extension == '.mkv') {
            try {
              final stat = await entity.stat();
              final relativePath = p.relative(entity.path, from: folderPath);
              final fileInfo = '${stat.size}|${stat.modified.millisecondsSinceEpoch}';
              final bytes = utf8.encode(fileInfo);
              final hash = sha256.convert(bytes).toString().substring(0, 16); // 使用短hash节省空间
              subHashes[relativePath] = hash;
            } catch (e) {
              // 如果无法获取文件信息，使用文件路径作为备用
              final relativePath = p.relative(entity.path, from: folderPath);
              subHashes[relativePath] = 'error';
            }
          }
        }
      }
    } catch (e) {
      debugPrint("计算子文件夹hash失败 $folderPath: $e");
    }

    return subHashes;
  }

  /// 获取变化检测结果的摘要
  String getChangeDetectionSummary() {
    if (_detectedChanges.isEmpty) {
      return "没有检测到文件夹变化";
    }
    
    int modifiedCount = _detectedChanges.where((c) => c.changeType == 'modified').length;
    int newCount = _detectedChanges.where((c) => c.changeType == 'new').length;
    int deletedCount = _detectedChanges.where((c) => c.changeType == 'deleted').length;
    
    List<String> parts = [];
    if (modifiedCount > 0) parts.add("$modifiedCount 个文件夹有变化");
    if (newCount > 0) parts.add("$newCount 个新文件夹");
    if (deletedCount > 0) parts.add("$deletedCount 个文件夹被删除");
    
    return "检测到：${parts.join('，')}";
  }

  /// 清除变化检测结果
  void clearDetectedChanges() {
    _detectedChanges.clear();
    notifyListeners();
    debugPrint("已清理检测到的文件夹变化");
  }

  void _updateScanState({bool? scanning, double? progress, String? message, bool? completed}) {
    bool changed = false;
    if (scanning != null && _isScanning != scanning) {
      _isScanning = scanning;
      changed = true;
      debugPrint("扫描状态变更: isScanning=$_isScanning");
    }
    if (progress != null && _scanProgress != progress) {
      _scanProgress = progress;
      changed = true;
    }
    if (message != null && _scanMessage != message) {
      _scanMessage = message;
      changed = true;
    }
    if (completed != null && completed && !_scanJustCompleted) {
      _scanJustCompleted = true;
      changed = true; // 确保完成事件被标记为"changed"
      debugPrint("扫描完成标志已设置: _scanJustCompleted=$_scanJustCompleted");
      // This will also be caught by 'changed' if scanning is set to false
    }

    if (changed || (completed != null && completed) ) { // Ensure listener notification on completion
      debugPrint("准备通知监听器状态变化: isScanning=$_isScanning, justFinishedScanning=$_justFinishedScanning, totalFilesFound=$_totalFilesFound");
      notifyListeners();
      debugPrint("已通知监听器状态变化");
    }
  }
  
  void _updateScanMessage(String message) {
    if (_scanMessage != message) {
      _scanMessage = message;
      notifyListeners();
    }
  }

  // Public method to allow UI or other services to update the scan message
  void updateScanMessage(String message) {
    _updateScanMessage(message);
  }

  Future<void> rescanAllFolders({bool skipPreviouslyMatchedUnwatched = true}) async {
    if (kIsWeb) {
      _updateScanMessage("Web版不支持扫描本地媒体库。");
      _updateScanState(scanning: false, completed: true);
      return;
    }
    if (_isScanning) {
      _updateScanMessage("已有扫描任务在进行中，请稍后开始全面刷新。");
      return;
    }

    if (_scannedFolders.isEmpty) {
      _updateScanMessage("没有已添加的媒体文件夹可供刷新。");
      _updateScanState(scanning: false, completed: true);
      return;
    }

    _updateScanState(scanning: true, progress: 0.0, message: "开始智能刷新所有媒体文件夹...");
    
    // 先清理无效的hash缓存
    await _cleanupFolderHashCache();
    
    List<String> allFoldersToScan = List.from(_scannedFolders);
    List<String> foldersNeedingScan = [];
    
    // 第一阶段：检查哪些文件夹需要扫描
    _updateScanState(message: "正在检查文件夹变化...");
    
    for (int i = 0; i < allFoldersToScan.length; i++) {
      if (!_isScanning) {
        _updateScanState(scanning: false, message: "刷新已取消。", completed: true);
        return;
      }
      
      final folderPath = allFoldersToScan[i];
      _updateScanState(
        progress: (i + 1) / allFoldersToScan.length * 0.3, // 前30%用于检查
        message: "检查文件夹变化: ${p.basename(folderPath)} (${i + 1}/${allFoldersToScan.length})"
      );
      
      final hasChanged = await _hasFolderChanged(folderPath);
      if (hasChanged) {
        foldersNeedingScan.add(folderPath);
      }
    }
    
    if (foldersNeedingScan.isEmpty) {
      _updateScanState(
        scanning: false, 
        progress: 1.0, 
        message: "智能刷新完成：所有文件夹都没有变化，无需重新扫描。", 
        completed: true
      );
      return;
    }
    
    // 第二阶段：扫描有变化的文件夹
    _updateScanState(
      message: "发现 ${foldersNeedingScan.length} 个文件夹有变化，开始扫描..."
    );
    
    int foldersProcessedCount = 0;

    for (String folderPath in foldersNeedingScan) {
      if (!_isScanning) {
          _updateScanState(scanning: false, message: "刷新已取消。", completed: true);
          return;
      }
      
      final overallProgress = 0.3 + (foldersProcessedCount / foldersNeedingScan.length) * 0.7; // 后70%用于扫描
      _updateScanState(
        progress: overallProgress,
        message: "正在刷新有变化的文件夹: ${p.basename(folderPath)} (${foldersProcessedCount + 1}/${foldersNeedingScan.length})"
      );

      await startDirectoryScan(
        folderPath, 
        isPartOfBatch: true, 
        skipPreviouslyMatchedUnwatched: skipPreviouslyMatchedUnwatched
      );
      
      // 扫描完成后更新该文件夹的hash
      await _updateFolderHash(folderPath);
      
      foldersProcessedCount++;
    }

    if (_isScanning || foldersProcessedCount == foldersNeedingScan.length) {
        // 批量扫描完成，设置标志
        _justFinishedScanning = true;
        final skippedCount = allFoldersToScan.length - foldersNeedingScan.length;
        String completionMessage = "智能刷新完成：扫描了 ${foldersNeedingScan.length} 个有变化的文件夹";
        if (skippedCount > 0) {
          completionMessage += "，跳过了 $skippedCount 个无变化的文件夹";
        }
        completionMessage += "。";
        
        _updateScanState(scanning: false, progress: 1.0, message: completionMessage, completed: true);
    }
  }

  Future<void> startDirectoryScan(
    String directoryPath, 
    {
      bool isPartOfBatch = false, 
      bool skipPreviouslyMatchedUnwatched = false
    }
  ) async {
    if (kIsWeb) {
      _updateScanMessage("Web版不支持扫描本地媒体库。");
      if (!isPartOfBatch) {
        _updateScanState(scanning: false, completed: true);
      }
      return;
    }
    if (!isPartOfBatch && _isScanning) {
      _updateScanMessage("已有扫描任务在进行中，请稍后。");
      return;
    }

    if (!isPartOfBatch) {
      _updateScanState(scanning: true, progress: 0.0, message: "准备智能扫描: $directoryPath");
      
      // 对于单个文件夹扫描，先检查是否有变化
      _updateScanState(message: "检查文件夹是否有变化...");
      final hasChanged = await _hasFolderChanged(directoryPath);
      
      if (!hasChanged) {
        _updateScanState(
          scanning: false, 
          progress: 1.0, 
          message: "智能扫描完成：文件夹 ${p.basename(directoryPath)} 没有变化，无需重新扫描。", 
          completed: true
        );
        return;
      } else {
        _updateScanState(message: "检测到文件夹有变化，开始扫描...");
      }
    } else {
       _updateScanState(message: "开始扫描子文件夹: ${p.basename(directoryPath)} (${skipPreviouslyMatchedUnwatched ? "跳过已匹配" : "全面扫描"})");
    }

    bool newFolderAddedToPrefs = false;
    if (!_scannedFolders.contains(directoryPath)) {
      _scannedFolders = List.from(_scannedFolders)..add(directoryPath);
      newFolderAddedToPrefs = true;
      // No need to notifyListeners here for just adding to list, will be notified by _updateScanState or at end
    }

    if (newFolderAddedToPrefs) {
      await _saveScannedFolders(); // Save if it's a genuinely new folder for persistence
      // If _saveScannedFolders itself calls notifyListeners, this might be redundant
      // but _scannedFolders list itself has changed, so a notify for that is good.
      notifyListeners(); // For the list change itself if UI displays it before scan starts
    }
    
    final directory = Directory(directoryPath);
    List<File> videoFiles = [];
    try {
      if (await directory.exists()) {
        await for (var entity in directory.list(recursive: true, followLinks: false)) {
          if (!_isScanning) break; // Check service's scanning flag
          if (entity is File) {
            String extension = p.extension(entity.path).toLowerCase();
            if (extension == '.mp4' || extension == '.mkv') {
              videoFiles.add(entity);
            }
          }
        }
      }
    } catch (e) {
      //debugPrint("ScanService: Error listing files in $directoryPath: $e");
      _updateScanState(scanning: false, message: "列出 $directoryPath中的文件失败: $e", completed: true);
      return;
    }

    if (!_isScanning && !isPartOfBatch) { // If scan was cancelled externally and not part of batch
      _updateScanState(scanning: false, message: "扫描已取消: $directoryPath", completed: true);
      return;
    }
    // If part of a batch and cancelled, rescanAllFolders handles the main message.

    if (videoFiles.isEmpty) {
      if (!isPartOfBatch) {
        // 更新找到的文件总数为0
        _totalFilesFound = 0;
        
        // 设置刚完成扫描的标志，用于UI检查
        _justFinishedScanning = true;
        
        _updateScanState(scanning: false, message: "在 $directoryPath 中没有找到 mp4 或 mkv 文件。", completed: true);
        
        debugPrint("扫描结束，没有找到文件，已设置 _justFinishedScanning=$_justFinishedScanning, _totalFilesFound=$_totalFilesFound");
      } else {
        // For batch, just update message, overall completion handled by rescanAllFolders
        _updateScanMessage("在 ${p.basename(directoryPath)} 中无视频文件。"); 
        // We need to ensure _isScanning remains true if other folders are pending in batch.
        // The caller (rescanAllFolders) will eventually set scanning to false.
      }
      return;
    }

    int filesProcessed = 0;
    Set<String> addedAnimeTitles = {};
    List<String> failedFiles = [];
    int skippedFilesCount = 0;

    for (File videoFile in videoFiles) {
      if (!_isScanning) break;

      if (skipPreviouslyMatchedUnwatched) {
        WatchHistoryItem? existingItem = await WatchHistoryManager.getHistoryItem(videoFile.path);
        if (existingItem != null &&
            existingItem.animeId != null &&
            existingItem.episodeId != null &&
            existingItem.watchProgress <= 0.01) {
          
          filesProcessed++;
          skippedFilesCount++;
          _updateScanState(
            progress: filesProcessed / videoFiles.length,
            message: "已跳过 (已匹配): ${p.basename(videoFile.path)} ($filesProcessed/${videoFiles.length})"
          );
          continue;
        }
      }

      filesProcessed++;
      _updateScanState(
          progress: filesProcessed / videoFiles.length,
          message: "正在处理: ${p.basename(videoFile.path)} ($filesProcessed/${videoFiles.length})"
      );

      try {
        final videoInfo = await DandanplayService.getVideoInfo(videoFile.path)
            .timeout(const Duration(seconds: 20), onTimeout: () {
          //debugPrint("ScanService: 获取 '${p.basename(videoFile.path)}' 的视频信息超时。");
          throw TimeoutException('获取视频信息超时 (${p.basename(videoFile.path)})');
        });

        if (videoInfo['isMatched'] == true && videoInfo['matches'] != null && (videoInfo['matches'] as List).isNotEmpty) {
          final match = videoInfo['matches'][0];
          final animeIdFromMatch = match['animeId'] as int?;
          final episodeIdFromMatch = match['episodeId'] as int?;
          final animeTitleFromMatch = (match['animeTitle'] as String?)?.isNotEmpty == true
              ? match['animeTitle'] as String
              : p.basenameWithoutExtension(videoFile.path);
          final episodeTitleFromMatch = match['episodeTitle'] as String?;

          WatchHistoryItem? existingItem = await WatchHistoryManager.getHistoryItem(videoFile.path);
          final int durationFromMatch = (videoInfo['duration'] is int)
              ? videoInfo['duration'] as int
              : (existingItem?.duration ?? 0);

          if (animeIdFromMatch != null && episodeIdFromMatch != null) {
            WatchHistoryItem itemToSave;
            if (existingItem != null) {
              if (existingItem.watchProgress > 0.01 && !existingItem.isFromScan) {
                // Preserve user's watch progress if it exists and not from a previous scan
                // Manually reconstruct WatchHistoryItem instead of using copyWith
                itemToSave = WatchHistoryItem(
                  filePath: existingItem.filePath, // Keep original file path
                  animeName: animeTitleFromMatch, // Update
                  episodeTitle: episodeTitleFromMatch, // Update
                  episodeId: episodeIdFromMatch, // Update
                  animeId: animeIdFromMatch, // Update
                  watchProgress: existingItem.watchProgress, // Preserve
                  lastPosition: existingItem.lastPosition, // Preserve
                  duration: durationFromMatch, // Update from scan
                  lastWatchTime: DateTime.now(), // Update to now
                  thumbnailPath: existingItem.thumbnailPath, // Preserve
                  isFromScan: false // Preserve original isFromScan status
                );
              } else {
                // Update existing scanned item or overwrite placeholder if progress was 0
                itemToSave = WatchHistoryItem(
                    filePath: videoFile.path,
                    animeName: animeTitleFromMatch,
                    episodeTitle: episodeTitleFromMatch,
                    episodeId: episodeIdFromMatch,
                    animeId: animeIdFromMatch,
                    watchProgress: existingItem.watchProgress, // Keep progress if it was a re-scan
                    lastPosition: existingItem.lastPosition, // Keep position if re-scan
                    duration: durationFromMatch,
                    lastWatchTime: DateTime.now(),
                    thumbnailPath: existingItem.thumbnailPath, // Preserve thumbnail
                    isFromScan: true);
              }
            } else {
              // New item from scan
              itemToSave = WatchHistoryItem(
                  filePath: videoFile.path,
                  animeName: animeTitleFromMatch,
                  episodeTitle: episodeTitleFromMatch,
                  episodeId: episodeIdFromMatch,
                  animeId: animeIdFromMatch,
                  watchProgress: 0.0,
                  lastPosition: 0,
                  duration: durationFromMatch,
                  lastWatchTime: DateTime.now(),
                  thumbnailPath: null,
                  isFromScan: true);
            }
            await WatchHistoryManager.addOrUpdateHistory(itemToSave);
            addedAnimeTitles.add(animeTitleFromMatch);
          } else {
            failedFiles.add("${p.basename(videoFile.path)} (缺少ID)");
          }
        } else {
          failedFiles.add("${p.basename(videoFile.path)} (未匹配)");
        }
      } on TimeoutException {
        failedFiles.add("${p.basename(videoFile.path)} (超时)");
      } catch (e) {
        failedFiles.add("${p.basename(videoFile.path)} (错误: ${e.toString().substring(0, min(e.toString().length, 30))})");
        //debugPrint("ScanService: Error processing file ${videoFile.path}: $e");
      }
    }

    if (!_isScanning && !isPartOfBatch) { // If scan was cancelled externally and not part of batch
      _updateScanState(scanning: false, message: "扫描已取消: $directoryPath", completed: true);
      return;
    }
    // If part of a batch and cancelled, rescanAllFolders handles the main message.

    if (!isPartOfBatch && _isScanning) {
      if (filesProcessed > 0) {
        // 更新找到的文件总数
        _totalFilesFound = videoFiles.length;
        
        String completionMessage = "";
        if (failedFiles.isNotEmpty) {
          completionMessage = "扫描 $directoryPath 完成。添加/更新 ${addedAnimeTitles.length} 部番剧。${failedFiles.length} 个文件处理失败。";
        } else {
          completionMessage = "扫描 $directoryPath 完成。添加/更新 ${addedAnimeTitles.length} 部番剧。";
        }
        if (skippedFilesCount > 0) {
          completionMessage += " 跳过了 $skippedFilesCount 个已匹配文件。";
        }
        
        // 设置刚完成扫描的标志，用于UI检查
        _justFinishedScanning = true;
        
        // 更新文件夹hash缓存
        await _updateFolderHash(directoryPath);
        
        _updateScanState(scanning: false, progress: 1.0, message: completionMessage, completed: true);
      } else {
        // 更新找到的文件总数为0
        _totalFilesFound = 0;
        
        // 设置刚完成扫描的标志，用于UI检查
        _justFinishedScanning = true;
        
        // 即使没有找到文件，也要更新hash缓存（可能是文件被删除了）
        await _updateFolderHash(directoryPath);
        
        _updateScanState(scanning: false, progress: 1.0, message: "扫描 $directoryPath 完成，未找到视频文件。", completed: true);
      }
    } else if (isPartOfBatch) {
      // 在批量扫描中更新总文件数
      _totalFilesFound += videoFiles.length;
      
      // For batch, update message. Overall progress/completion is handled by rescanAllFolders.
      // _updateScanMessage(completionMessage); // This might be too noisy if many folders
      // The progress will be updated by rescanAllFolders.
      // _isScanning should remain true if it's a batch scan and not the last folder.
      // This means startDirectoryScan should NOT set _isScanning to false if isPartOfBatch is true,
      // UNLESS it's the very last folder of the batch, which rescanAllFolders will handle.
      // So, if isPartOfBatch, we don't call _updateScanState to set scanning to false here.
      // Note: Hash update for batch scan is handled in rescanAllFolders method
    }
  }

  Future<void> removeScannedFolder(String folderPath) async {
    if (kIsWeb) {
      _updateScanMessage("Web版不支持扫描本地媒体库。");
      return;
    }
    if (_scannedFolders.contains(folderPath)) {
      // First, perform the cleanup of associated media records
      try {
        List<WatchHistoryItem> itemsToRemove = await WatchHistoryManager.getItemsByPathPrefix(folderPath);
        if (itemsToRemove.isNotEmpty) {
            Set<int> affectedAnimeIds = itemsToRemove
                .where((item) => item.animeId != null)
                .map((item) => item.animeId!)
                .toSet();

            await WatchHistoryManager.removeItemsByPathPrefix(folderPath);
            //debugPrint("ScanService: Removed ${itemsToRemove.length} items from WatchHistoryManager for path: $folderPath");

            for (int animeId in affectedAnimeIds) {
                List<WatchHistoryItem> remainingItemsForAnime = await WatchHistoryManager.getAllItemsForAnime(animeId);
                if (remainingItemsForAnime.isEmpty) {
                //debugPrint("ScanService: Anime ID: $animeId is now orphaned (no remaining episodes) after removing $folderPath.");
                // TODO: Optionally, add logic here to notify other parts of the app or clean up anime-level data if needed
                }
            }
        } else {
            //debugPrint("ScanService: No WatchHistoryItems found for path prefix $folderPath to remove.");
        }
      } catch (e) {
        //debugPrint("ScanService: Error cleaning watch history for $folderPath: $e");
        // Decide if we should still proceed with removing the folder from the list
        // For now, we will, but flag the error in the message.
        _updateScanMessage("移除 $folderPath 时清理历史记录失败: $e");
        // Potentially return or throw to prevent folder removal from list if history cleanup is critical
      }

      // Then, remove the folder from the list and save
      _scannedFolders = List.from(_scannedFolders)..remove(folderPath);
      await _saveScannedFolders();
      
      // 同时移除对应的hash缓存
      if (_folderHashCache.containsKey(folderPath)) {
        _folderHashCache.remove(folderPath);
        await _saveFolderHashCache();
        debugPrint("已清理文件夹 $folderPath 的hash缓存");
      }
      
      if (_subFolderHashCache.containsKey(folderPath)) {
        _subFolderHashCache.remove(folderPath);
        await _saveSubFolderHashCache();
        debugPrint("已清理文件夹 $folderPath 的子文件夹hash缓存");
      }
      
      _updateScanMessage("已从扫描列表移除文件夹: $folderPath");
      _updateScanState(scanning: false, completed: true); // Ensure isScanning is false, and signal completion for UI refresh

      //debugPrint("ScanService: Removed folder $folderPath from scanned list.");
    } else {
      //debugPrint("ScanService: Attempted to remove folder not in list: $folderPath");
      _updateScanMessage("文件夹 $folderPath 不在扫描列表中。");
    }
  }

} 