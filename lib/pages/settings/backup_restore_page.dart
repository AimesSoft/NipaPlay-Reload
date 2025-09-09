import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/services/backup_service.dart';
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

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    // 使用项目的 BlurSnackBar
    BlurSnackBar.show(context, message);
    
    // 如果是错误消息，也可以考虑使用不同的颜色或样式
    // 这里暂时使用同样的样式，因为 BlurSnackBar 没有错误样式参数
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
          SettingsCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: const Text(
                    '备份与恢复',
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
                  '• 备份文件格式：.nph (NipaPlay History)',
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