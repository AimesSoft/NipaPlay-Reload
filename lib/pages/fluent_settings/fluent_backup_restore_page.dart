import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nipaplay/services/auto_sync_service.dart';
import 'package:nipaplay/services/backup_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';

class FluentBackupRestorePage extends StatefulWidget {
  const FluentBackupRestorePage({super.key});

  @override
  State<FluentBackupRestorePage> createState() => _FluentBackupRestorePageState();
}

class _FluentBackupRestorePageState extends State<FluentBackupRestorePage> {
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
    if (!mounted) return;
    setState(() {
      _autoSyncEnabled = enabled;
      _autoSyncPath = path;
    });
  }

  void _showMessage(String message, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    if (!mounted) return;
    FluentInfoBar.show(
      context,
      message,
      severity: severity,
    );
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      if (enabled && _autoSyncPath == null) {
        await _selectAutoSyncPath();
        return;
      }

      if (enabled) {
        await AutoSyncService.instance.enable(_autoSyncPath!);
        _showMessage('自动同步已启用', severity: InfoBarSeverity.success);
      } else {
        await AutoSyncService.instance.disable();
        _showMessage('自动同步已禁用');
      }

      await _loadAutoSyncSettings();
    } catch (e) {
      _showMessage('设置自动同步失败: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _selectAutoSyncPath() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (!mounted) return;

    if (selectedDirectory == null) {
      _showMessage('未选择同步路径');
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await AutoSyncService.instance.enable(selectedDirectory);
      _showMessage('自动同步已启用，路径: $selectedDirectory', severity: InfoBarSeverity.success);
      await _loadAutoSyncSettings();
    } catch (e) {
      _showMessage('设置同步路径失败: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _manualSync() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await AutoSyncService.instance.manualSync();
      _showMessage('手动同步完成', severity: InfoBarSeverity.success);
    } catch (e) {
      _showMessage('手动同步失败: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _backupHistory() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (!mounted) return;

      if (selectedDirectory == null) {
        _showMessage('未选择保存位置');
        return;
      }

      final backupService = BackupService();
      final result = await backupService.exportWatchHistory(selectedDirectory);

      if (result != null) {
        _showMessage('备份成功，文件保存至: $result', severity: InfoBarSeverity.success);
      } else {
        _showMessage('备份失败', severity: InfoBarSeverity.error);
      }
    } catch (e) {
      _showMessage('备份失败: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _restoreHistory() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['nph'],
      );
      if (!mounted) return;

      if (result == null || result.files.single.path == null) {
        _showMessage('未选择文件');
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return ContentDialog(
            title: const Text('确认恢复'),
            content: const Text(
              '恢复操作将合并备份中的观看进度（含截图）到当前记录，仅对本地存在的媒体生效。是否继续？',
            ),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }

      final filePath = result.files.single.path!;
      final backupService = BackupService();
      final restoredCount = await backupService.importWatchHistory(filePath);

      if (restoredCount > 0) {
        final watchHistoryProvider =
            Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.clearInvalidPathCache();
        await watchHistoryProvider.loadHistory();

        _showMessage('恢复成功，已恢复 $restoredCount 条观看记录',
            severity: InfoBarSeverity.success);
      } else {
        _showMessage('未找到可恢复的观看记录', severity: InfoBarSeverity.warning);
      }
    } catch (e) {
      _showMessage('恢复失败: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('备份与恢复'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动云同步',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('启用自动同步'),
                                const SizedBox(height: 4),
                                Text(
                                  _autoSyncEnabled
                                      ? '观看进度将自动同步到指定路径'
                                      : '启用后可同步到本地或网络路径',
                                  style: FluentTheme.of(context).typography.caption,
                                ),
                              ],
                            ),
                          ),
                          ToggleSwitch(
                            checked: _autoSyncEnabled,
                            onChanged: _isProcessing
                                ? null
                                : (value) {
                                    _toggleAutoSync(value);
                                  },
                          ),
                        ],
                      ),
                      if (_autoSyncEnabled && _autoSyncPath != null) ...[
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: '同步路径',
                          child: SelectableText(_autoSyncPath!),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            Button(
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      _selectAutoSyncPath();
                                    },
                              child: const Text('更改路径'),
                            ),
                            Button(
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      _manualSync();
                                    },
                              child: const Text('立即同步'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '手动备份与恢复',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _isProcessing
                                ? null
                                : () {
                                    _backupHistory();
                                  },
                            child: const Text('备份观看进度'),
                          ),
                          Button(
                            onPressed: _isProcessing
                                ? null
                                : () {
                                    _restoreHistory();
                                  },
                            child: const Text('恢复观看进度'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '说明',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 12),
                      Text('• 自动同步使用固定文件 nipaplay_auto_sync.nph 存储进度'),
                      SizedBox(height: 4),
                      Text('• 同步路径可指向本地磁盘或 SMB/NFS 等网络位置'),
                      SizedBox(height: 4),
                      Text('• 手动备份可导出 .nph 文件，方便单次备份'),
                      SizedBox(height: 4),
                      Text('• 恢复操作仅合并已存在媒体文件的进度，包含截图数据'),
                    ],
                  ),
                ),
              ),
              if (_isProcessing) ...[
                const SizedBox(height: 16),
                const ProgressRing(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
