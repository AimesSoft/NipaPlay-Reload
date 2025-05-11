import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'dart:async';
import 'dart:math';
// Import Provider if ScanService needs to directly refresh other providers,
// otherwise it will be refreshed by UI listening to this service.
// import 'package:provider/provider.dart';
// import 'package:nipaplay/providers/watch_history_provider.dart';


class ScanService with ChangeNotifier {
  static const String _scannedFoldersPrefsKey = 'nipaplay_scanned_folders';
  // _lastScannedDirectoryPickerPathKey will likely remain in UI as it's picker-specific

  List<String> _scannedFolders = [];
  List<String> get scannedFolders => List.unmodifiable(_scannedFolders);

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


  ScanService() {
    _loadScannedFolders();
  }

  Future<void> _loadScannedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _scannedFolders = prefs.getStringList(_scannedFoldersPrefsKey) ?? [];
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

  void _updateScanState({bool? scanning, double? progress, String? message, bool? completed}) {
    bool changed = false;
    if (scanning != null && _isScanning != scanning) {
      _isScanning = scanning;
      changed = true;
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
      // This will also be caught by 'changed' if scanning is set to false
    }

    if (changed || (completed != null && completed) ) { // Ensure listener notification on completion
      notifyListeners();
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
    if (_isScanning) {
      _updateScanMessage("已有扫描任务在进行中，请稍后开始全面刷新。");
      return;
    }

    if (_scannedFolders.isEmpty) {
      _updateScanMessage("没有已添加的媒体文件夹可供刷新。");
      _updateScanState(scanning: false, completed: true);
      return;
    }

    _updateScanState(scanning: true, progress: 0.0, message: "开始刷新所有媒体文件夹...");
    
    List<String> allFoldersToScan = List.from(_scannedFolders);
    double overallProgress = 0;
    int foldersProcessedCount = 0;

    for (String folderPath in allFoldersToScan) {
      if (!_isScanning && foldersProcessedCount > 0) {
          _updateScanState(scanning: false, message: "刷新已取消。", completed: true);
          return;
      }
      _updateScanState(message: "正在刷新: $folderPath (${foldersProcessedCount + 1}/${allFoldersToScan.length})");

      await startDirectoryScan(
        folderPath, 
        isPartOfBatch: true, 
        skipPreviouslyMatchedUnwatched: skipPreviouslyMatchedUnwatched
      );
      
      foldersProcessedCount++;
      overallProgress = foldersProcessedCount / allFoldersToScan.length;
      
      if (_isScanning) {
          _updateScanState(progress: overallProgress, message: "已刷新 $foldersProcessedCount / ${allFoldersToScan.length} 个文件夹。");
      }
    }

    if (_isScanning || foldersProcessedCount == allFoldersToScan.length) {
        _updateScanState(scanning: false, progress: 1.0, message: "所有媒体文件夹刷新完毕。", completed: true);
    }
  }

  Future<void> startDirectoryScan(
    String directoryPath, 
    {
      bool isPartOfBatch = false, 
      bool skipPreviouslyMatchedUnwatched = false
    }
  ) async {
    if (!isPartOfBatch && _isScanning) {
      _updateScanMessage("已有扫描任务在进行中，请稍后。");
      return;
    }

    if (!isPartOfBatch) {
      _updateScanState(scanning: true, progress: 0.0, message: "准备扫描: $directoryPath");
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

    if (!_isScanning) {
      //debugPrint("ScanService: Scan cancelled while listing files for $directoryPath.");
      _updateScanState(scanning: false, message: "扫描已取消: $directoryPath", completed: true);
      return;
    }

    if (videoFiles.isEmpty) {
      if (!isPartOfBatch) {
        _updateScanState(scanning: false, message: "在 $directoryPath 中没有找到 mp4 或 mkv 文件。", completed: true);
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

    String completionMessage = "";
    if (failedFiles.isNotEmpty) {
      completionMessage = "扫描 $directoryPath 完成。添加/更新 ${addedAnimeTitles.length} 部番剧。${failedFiles.length} 个文件处理失败。";
    } else {
      completionMessage = "扫描 $directoryPath 完成。添加/更新 ${addedAnimeTitles.length} 部番剧。";
    }
    if (skippedFilesCount > 0) {
      completionMessage += " 跳过了 $skippedFilesCount 个已匹配文件。";
    }
    
    if (!isPartOfBatch) {
        _updateScanState(scanning: false, progress: 1.0, message: completionMessage, completed: true);
    } else {
        // For batch, update message. Overall progress/completion is handled by rescanAllFolders.
        // _updateScanMessage(completionMessage); // This might be too noisy if many folders
        // The progress will be updated by rescanAllFolders.
        // _isScanning should remain true if it's a batch scan and not the last folder.
        // This means startDirectoryScan should NOT set _isScanning to false if isPartOfBatch is true,
        // UNLESS it's the very last folder of the batch, which rescanAllFolders will handle.
        // So, if isPartOfBatch, we don't call _updateScanState to set scanning to false here.
    }
  }

  Future<void> removeScannedFolder(String folderPath) async {
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
      
      _updateScanMessage("已从扫描列表移除文件夹: $folderPath");
      _updateScanState(scanning: false, completed: true); // Ensure isScanning is false, and signal completion for UI refresh

      //debugPrint("ScanService: Removed folder $folderPath from scanned list.");
    } else {
      //debugPrint("ScanService: Attempted to remove folder not in list: $folderPath");
      _updateScanMessage("文件夹 $folderPath 不在扫描列表中。");
    }
  }

} 