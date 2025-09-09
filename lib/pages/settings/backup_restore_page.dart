import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/services/backup_service.dart';
import 'package:nipaplay/services/auto_sync_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:file_picker/file_picker.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isProcessing = false;
  bool _autoSyncEnabled = false;
  String? _autoSyncPath;

  @override
  void initState() {
    super.initState();
    _loadAutoSyncSettings();
  }

  Future<void> _loadAutoSyncSettings() async {
    final enabled = await AutoSyncSettings.isEnabled();
    final path = await AutoSyncSettings.getSyncPath();
    
    setState(() {
      _autoSyncEnabled = enabled;
      _autoSyncPath = path;
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    // 使用项目的 BlurSnackBar
    BlurSnackBar.show(context, message);
    
    // 如果是错误消息，也可以考虑使用不同的颜色或样式
    // 这里暂时使用同样的样式，因为 BlurSnackBar 没有错误样式参数
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      if (enabled && _autoSyncPath == null) {
        // 需要先选择路径
        await _selectAutoSyncPath();
        return;
      }

      if (enabled) {
        await AutoSyncService.instance.enable(_autoSyncPath!);
        _showMessage('自动同步已启用');
      } else {
        await AutoSyncService.instance.disable();
        _showMessage('自动同步已禁用');
      }

      await _loadAutoSyncSettings();
    } catch (e) {
      _showMessage('设置自动同步失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _selectAutoSyncPath() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    
    if (selectedDirectory == null) {
      _showMessage('未选择同步路径');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await AutoSyncService.instance.enable(selectedDirectory);
      _showMessage('自动同步已启用，路径: $selectedDirectory');
      await _loadAutoSyncSettings();
    } catch (e) {
      _showMessage('设置同步路径失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _manualSync() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await AutoSyncService.instance.manualSync();
      _showMessage('手动同步完成');
    } catch (e) {
      _showMessage('手动同步失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _backupHistory() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // 选择保存位置
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory == null) {
        _showMessage('未选择保存位置');
        return;
      }

      // 执行备份
      final backupService = BackupService();
      final result = await backupService.exportWatchHistory(selectedDirectory);

      if (result != null) {
        _showMessage('备份成功！文件保存至: $result');
      } else {
        _showMessage('备份失败', isError: true);
      }
    } catch (e) {
      _showMessage('备份失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _restoreHistory() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // 选择备份文件
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['nph'],
      );

      if (result == null || result.files.single.path == null) {
        _showMessage('未选择文件');
        return;
      }

      final filePath = result.files.single.path!;
      
      // 确认对话框
      final confirmed = await BlurDialog.show<bool>(
        context: context,
        title: '确认恢复',
        content: '恢复操作将会合并备份文件中的观看进度（包括截图）到当前记录中，且只会恢复本地存在的媒体文件的进度。是否继续？',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认', style: TextStyle(color: Colors.white)),
          ),
        ],
      );

      if (confirmed != true) return;

      // 执行恢复
      final backupService = BackupService();
      final restoredCount = await backupService.importWatchHistory(filePath);

      if (restoredCount > 0) {
        // 刷新观看历史
        if (context.mounted) {
          final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
          // 清除缓存并重新加载
          watchHistoryProvider.clearInvalidPathCache();
          await watchHistoryProvider.loadHistory();
        }
        
        _showMessage('恢复成功！已恢复 $restoredCount 条观看记录');
      } else {
        _showMessage('未找到可恢复的观看记录', isError: true);
      }
    } catch (e) {
      _showMessage('恢复失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 自动同步设置卡片
          SettingsCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: const Text(
                    '自动云同步',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                SettingsItem.toggle(
                  title: '启用自动同步',
                  subtitle: _autoSyncEnabled 
                    ? '观看进度会自动同步到本地路径或云端' 
                    : '启用后可实现多设备同步',
                  enabled: !_isProcessing,
                  value: _autoSyncEnabled,
                  onChanged: _toggleAutoSync,
                  icon: Icons.cloud_sync,
                ),
                if (_autoSyncEnabled && _autoSyncPath != null) ...[
                  const SizedBox(height: 8),
                  SettingsItem.button(
                    title: '同步路径',
                    subtitle: _autoSyncPath!.length > 50 
                        ? '...${_autoSyncPath!.substring(_autoSyncPath!.length - 50)}'
                        : _autoSyncPath!,
                    enabled: !_isProcessing,
                    onTap: _selectAutoSyncPath,
                    icon: Icons.folder,
                  ),
                  const SizedBox(height: 8),
                  SettingsItem.button(
                    title: '立即同步',
                    subtitle: '手动执行一次同步',
                    enabled: !_isProcessing,
                    onTap: _manualSync,
                    icon: Icons.sync,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 手动备份恢复卡片
          SettingsCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: const Text(
                    '手动备份与恢复',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                SettingsItem.button(
                  title: '备份观看进度',
                  subtitle: '将观看进度导出为.nph文件',
                  enabled: !_isProcessing,
                  onTap: _backupHistory,
                  icon: Icons.backup,
                ),
                const SizedBox(height: 8),
                SettingsItem.button(
                  title: '恢复观看进度',
                  subtitle: '从.nph文件恢复观看进度',
                  enabled: !_isProcessing,
                  onTap: _restoreHistory,
                  icon: Icons.restore,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '说明',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  '• 自动同步：启用后观看进度会自动保存到指定路径',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 云同步：同步路径可以是SMB/NFS等网络位置',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 固定文件：自动同步使用固定文件名 nipaplay_auto_sync.nph',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 手动备份：支持自定义文件名的一次性备份',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 备份内容：包含集数信息、观看时间戳和截图',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 恢复规则：只恢复本地扫描到的媒体文件的观看进度',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 截图存储：恢复的截图保存在应用缓存目录',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                SizedBox(height: 8),
                Text(
                  '• 此功能仅在桌面端可用',
                  style: TextStyle(fontSize: 14, color: Colors.white70, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      '处理中...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}