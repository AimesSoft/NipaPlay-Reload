import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/services/backup_service.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/auto_sync_service.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    BlurSnackBar.show(context, message);
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
    final String? selectedDirectory =
        await FilePicker.platform.getDirectoryPath();

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

  // ==================== 全量备份 ====================

  Future<void> _showFullBackupDialog() async {
    // 先收集计数信息
    final historyItems = await WatchHistoryManager.getAllHistory();
    final watchHistoryCount = historyItems.length;
    final episodeMatchCount = historyItems
        .where((i) => i.animeId != null && i.episodeId != null)
        .length;

    // 获取媒体库计数
    final prefs = await SharedPreferences.getInstance();
    int localLibraryCount =
        prefs.getStringList('nipaplay_scanned_folders')?.length ?? 0;
    int serverProfileCount = 0;
    try {
      await MultiAddressServerService.instance.loadProfiles();
      serverProfileCount = MultiAddressServerService.instance.profiles.length;
    } catch (_) {}
    int webdavCount = 0;
    try {
      await WebDAVService.instance.initialize();
      webdavCount = WebDAVService.instance.connections.length;
    } catch (_) {}
    int smbCount = 0;
    try {
      await SMBService.instance.initialize();
      smbCount = SMBService.instance.connections.length;
    } catch (_) {}
    bool hasDandanplayRemote = false;
    try {
      await DandanplayRemoteService.instance
          .loadSavedSettings(backgroundRefresh: true);
      hasDandanplayRemote =
          DandanplayRemoteService.instance.serverUrl != null &&
              DandanplayRemoteService.instance.serverUrl!.isNotEmpty;
    } catch (_) {}

    // 获取账户计数
    int accountCount = 0;
    final dandanplayLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    if (dandanplayLoggedIn) accountCount++;
    final bangumiLoggedIn = prefs.getBool('bangumi_logged_in') ?? false;
    if (bangumiLoggedIn) accountCount++;
    accountCount += serverProfileCount;

    if (!mounted) return;

    final result = await NipaplayWindow.show<Set<BackupCategory>>(
      context: context,
      child: _BackupSelectionDialog(
        localLibraryCount: localLibraryCount,
        serverProfileCount: serverProfileCount,
        webdavCount: webdavCount,
        smbCount: smbCount,
        hasDandanplayRemote: hasDandanplayRemote,
        watchHistoryCount: watchHistoryCount,
        episodeMatchCount: episodeMatchCount,
        accountCount: accountCount,
      ),
    );

    if (result == null || result.isEmpty) return;

    // 选择保存位置
    final String? selectedDirectory =
        await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) {
      _showMessage('未选择保存位置');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      String appVersion = '';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (_) {}

      final backupService = FullBackupService();
      final filePath = await backupService.exportBackup(
        directoryPath: selectedDirectory,
        categories: result,
        appVersion: appVersion,
      );

      if (filePath != null) {
        _showMessage('备份成功！文件保存至: $filePath');
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

  // ==================== 全量恢复 ====================

  Future<void> _showFullRestoreDialog() async {
    // 选择备份文件
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['npb'],
    );

    if (result == null || result.files.single.path == null) {
      _showMessage('未选择文件');
      return;
    }

    final filePath = result.files.single.path!;

    // 预览备份内容
    final backupService = FullBackupService();
    final preview = await backupService.previewBackup(filePath);

    if (preview == null) {
      _showMessage('无法读取备份文件', isError: true);
      return;
    }

    if (!mounted) return;

    // 显示预览和选择对话框
    final categories = await NipaplayWindow.show<Set<BackupCategory>>(
      context: context,
      child: _RestoreSelectionDialog(preview: preview),
    );

    if (categories == null || categories.isEmpty) return;
    if (!mounted) return;

    // 确认对话框
    final confirmed = await BlurDialog.show<bool>(
      context: context,
      title: '确认恢复',
      content: '恢复操作将合并备份数据到当前记录中。已有的本地数据不会被删除，仅更新或新增。是否继续？',
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认', style: TextStyle(color: Colors.white)),
        ),
      ],
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final restoreResult = await backupService.importBackup(
        filePath: filePath,
        categories: categories,
      );

      if (restoreResult.success) {
        // 刷新观看历史
        if (mounted) {
          final watchHistoryProvider =
              Provider.of<WatchHistoryProvider>(context, listen: false);
          watchHistoryProvider.clearInvalidPathCache();
          await watchHistoryProvider.loadHistory();
        }

        final parts = <String>[];
        if (restoreResult.preferencesResult != null) {
          final r = restoreResult.preferencesResult!;
          parts.add('设置${r.success ? "✓" : "✗"}');
        }
        if (restoreResult.mediaLibrariesResult != null) {
          final r = restoreResult.mediaLibrariesResult!;
          parts.add('媒体库${r.success ? "✓" : "✗"}');
        }
        if (restoreResult.watchHistoryResult != null) {
          final r = restoreResult.watchHistoryResult!;
          parts.add('历史${r.restoredCount}条${r.success ? "✓" : "✗"}');
        }
        if (restoreResult.episodeMatchesResult != null) {
          final r = restoreResult.episodeMatchesResult!;
          parts.add('匹配${r.restoredCount}条${r.success ? "✓" : "✗"}');
        }
        if (restoreResult.accountsResult != null) {
          final r = restoreResult.accountsResult!;
          parts.add('账户${r.success ? "✓" : "✗"}');
        }

        _showMessage('恢复完成: ${parts.join(" ")}，部分数据需要重启应用生效');
      } else {
        _showMessage('恢复失败: ${restoreResult.errorMessage ?? "未知错误"}',
            isError: true);
      }
    } catch (e) {
      _showMessage('恢复失败: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ==================== 旧版观看历史备份恢复（保留兼容） ====================

  Future<void> _backupHistory() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final String? selectedDirectory =
          await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        _showMessage('未选择保存位置');
        return;
      }

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
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['nph'],
      );

      if (result == null || result.files.single.path == null) {
        _showMessage('未选择文件');
        return;
      }

      final filePath = result.files.single.path!;

      if (!mounted) return;
      final confirmed = await BlurDialog.show<bool>(
        context: context,
        title: '确认恢复',
        content: '恢复操作将会合并备份文件中的观看进度（包括截图）到当前记录中，且只会恢复本地存在的媒体文件的进度。是否继续？',
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.white70)),
          ),
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认', style: TextStyle(color: Colors.white)),
          ),
        ],
      );

      if (confirmed != true) return;

      final backupService = BackupService();
      final restoredCount = await backupService.importWatchHistory(filePath);

      if (restoredCount > 0) {
        if (mounted) {
          final watchHistoryProvider =
              Provider.of<WatchHistoryProvider>(context, listen: false);
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
    return AdaptiveSettingsPage(
      title: context.l10n.backupAndRestore,
      children: [
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: '全量备份',
              subtitle: '选择性导出设置、媒体库、观看历史、剧集匹配和账户信息',
              enabled: !_isProcessing,
              onTap: _showFullBackupDialog,
              icon: Icons.cloud_upload,
            ),
            AdaptiveSettingsTile<void>.card(
              title: '全量恢复',
              subtitle: '从 .npb 备份文件选择性恢复数据',
              enabled: !_isProcessing,
              onTap: _showFullRestoreDialog,
              icon: Icons.cloud_download,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<bool>.toggle(
              title: '启用自动同步',
              subtitle: _autoSyncEnabled ? '观看进度会自动同步到本地路径或云端' : '启用后可实现多设备同步',
              enabled: !_isProcessing,
              value: _autoSyncEnabled,
              onChanged: _toggleAutoSync,
              icon: Icons.cloud_sync,
            ),
            if (_autoSyncEnabled && _autoSyncPath != null) ...[
              AdaptiveSettingsTile<void>.card(
                title: '同步路径',
                subtitle: _autoSyncPath!.length > 50
                    ? '...${_autoSyncPath!.substring(_autoSyncPath!.length - 50)}'
                    : _autoSyncPath!,
                enabled: !_isProcessing,
                onTap: _selectAutoSyncPath,
                icon: Icons.folder,
              ),
              AdaptiveSettingsTile<void>.card(
                title: '立即同步',
                subtitle: '手动执行一次同步',
                enabled: !_isProcessing,
                onTap: _manualSync,
                icon: Icons.sync,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: '备份观看进度',
              subtitle: '将观看进度导出为 .nph 文件',
              enabled: !_isProcessing,
              onTap: _backupHistory,
              icon: Icons.backup,
            ),
            AdaptiveSettingsTile<void>.card(
              title: '恢复观看进度',
              subtitle: '从 .nph 文件恢复观看进度',
              enabled: !_isProcessing,
              onTap: _restoreHistory,
              icon: Icons.restore,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: '说明',
              subtitle: '全量备份：可选择导出偏好设置、媒体库、观看历史、剧集匹配和账户信息\n'
                  '全量恢复：从 .npb 文件恢复，支持选择性恢复各类数据\n'
                  '自动同步：启用后观看进度会自动保存到指定路径\n'
                  '云同步：同步路径可以是 SMB/NFS 等网络位置\n'
                  '恢复规则：已有数据不会被删除，仅更新或新增\n'
                  '此功能仅在桌面端可用',
              icon: Icons.info_outline,
              onTap: () {},
            ),
          ],
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 16),
          AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsTile<void>.card(
                title: '处理中...',
                subtitle: '请等待当前备份或恢复任务完成',
                icon: Icons.hourglass_empty,
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ==================== 备份选择弹窗 ====================

class _BackupSelectionDialog extends StatefulWidget {
  final int localLibraryCount;
  final int serverProfileCount;
  final int webdavCount;
  final int smbCount;
  final bool hasDandanplayRemote;
  final int watchHistoryCount;
  final int episodeMatchCount;
  final int accountCount;

  const _BackupSelectionDialog({
    required this.localLibraryCount,
    required this.serverProfileCount,
    required this.webdavCount,
    required this.smbCount,
    required this.hasDandanplayRemote,
    required this.watchHistoryCount,
    required this.episodeMatchCount,
    required this.accountCount,
  });

  @override
  State<_BackupSelectionDialog> createState() => _BackupSelectionDialogState();
}

class _BackupSelectionDialogState extends State<_BackupSelectionDialog> {
  late Map<BackupCategory, bool> _selections;

  @override
  void initState() {
    super.initState();
    _selections = {
      BackupCategory.preferences: true,
      BackupCategory.mediaLibraries: true,
      BackupCategory.watchHistory: true,
      BackupCategory.episodeMatches: true,
      BackupCategory.accounts: true,
    };
  }

  bool get _isAllSelected => _selections.values.every((v) => v);

  void _toggleAll(bool value) {
    setState(() {
      for (final key in _selections.keys) {
        _selections[key] = value;
      }
    });
  }

  void _toggle(BackupCategory category, bool value) {
    setState(() {
      _selections[category] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppAccentColors.current;

    return NipaplayWindowScaffold(
      onClose: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择备份内容',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // 可滚动的选择区域
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 全选
                    _buildCheckboxTile(
                      title: '全选',
                      subtitle: '导出所有数据',
                      value: _isAllSelected,
                      onChanged: _toggleAll,
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                    const Divider(height: 24),
                    // 偏好设置
                    _buildCheckboxTile(
                      title: '偏好设置',
                      subtitle: '软件设置（语言、弹幕、播放器等）',
                      value: _selections[BackupCategory.preferences]!,
                      onChanged: (v) => _toggle(BackupCategory.preferences, v),
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 4),
                    // 媒体库
                    _buildCheckboxTile(
                      title: '添加的媒体库',
                      subtitle: _buildMediaLibrariesSubtitle(),
                      value: _selections[BackupCategory.mediaLibraries]!,
                      onChanged: (v) =>
                          _toggle(BackupCategory.mediaLibraries, v),
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 4),
                    // 观看历史
                    _buildCheckboxTile(
                      title: '观看历史',
                      subtitle: '${widget.watchHistoryCount} 条记录',
                      value: _selections[BackupCategory.watchHistory]!,
                      onChanged: (v) => _toggle(BackupCategory.watchHistory, v),
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 4),
                    // 剧集匹配
                    _buildCheckboxTile(
                      title: '剧集匹配',
                      subtitle: '${widget.episodeMatchCount} 条匹配',
                      value: _selections[BackupCategory.episodeMatches]!,
                      onChanged: (v) =>
                          _toggle(BackupCategory.episodeMatches, v),
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 4),
                    // 账户绑定
                    _buildCheckboxTile(
                      title: '账户绑定',
                      subtitle: '${widget.accountCount} 个账户',
                      value: _selections[BackupCategory.accounts]!,
                      onChanged: (v) => _toggle(BackupCategory.accounts, v),
                      accentColor: accentColor,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 底部按钮（固定在底部）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HoverScaleTextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      const Text('取消', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 16),
                HoverScaleTextButton(
                  onPressed: _selections.values.any((v) => v)
                      ? () {
                          final selected = _selections.entries
                              .where((e) => e.value)
                              .map((e) => e.key)
                              .toSet();
                          Navigator.of(context).pop(selected);
                        }
                      : null,
                  child:
                      const Text('确定', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accentColor,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                checkColor: Colors.white,
                side: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildMediaLibrariesSubtitle() {
    final parts = <String>[];
    if (widget.localLibraryCount > 0) {
      parts.add('${widget.localLibraryCount} 本地库');
    }
    if (widget.serverProfileCount > 0) {
      parts.add('${widget.serverProfileCount} 服务器');
    }
    if (widget.webdavCount > 0) {
      parts.add('${widget.webdavCount} WebDAV');
    }
    if (widget.smbCount > 0) {
      parts.add('${widget.smbCount} SMB');
    }
    if (widget.hasDandanplayRemote) {
      parts.add('DDP远程');
    }
    parts.add('共享服务');
    return parts.join(', ');
  }
}

// ==================== 恢复选择弹窗 ====================

class _RestoreSelectionDialog extends StatefulWidget {
  final BackupPreviewInfo preview;

  const _RestoreSelectionDialog({required this.preview});

  @override
  State<_RestoreSelectionDialog> createState() =>
      _RestoreSelectionDialogState();
}

class _RestoreSelectionDialogState extends State<_RestoreSelectionDialog> {
  late Map<BackupCategory, bool> _selections;

  @override
  void initState() {
    super.initState();
    _selections = {
      BackupCategory.preferences: widget.preview.hasPreferences,
      BackupCategory.mediaLibraries: widget.preview.hasMediaLibraries,
      BackupCategory.watchHistory: widget.preview.hasWatchHistory,
      BackupCategory.episodeMatches: widget.preview.hasEpisodeMatches,
      BackupCategory.accounts: widget.preview.hasAccounts,
    };
  }

  bool get _isAllSelected => _selections.values.every((v) => v);

  void _toggleAll(bool value) {
    setState(() {
      for (final key in _selections.keys) {
        _selections[key] = value;
      }
    });
  }

  void _toggle(BackupCategory category, bool value) {
    setState(() {
      _selections[category] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = AppAccentColors.current;

    final preview = widget.preview;
    final backupDate = preview.timestamp.isNotEmpty
        ? DateTime.tryParse(preview.timestamp)?.toLocal()
        : null;
    final dateStr = backupDate != null
        ? '${backupDate.year}-${backupDate.month.toString().padLeft(2, '0')}-${backupDate.day.toString().padLeft(2, '0')} ${backupDate.hour.toString().padLeft(2, '0')}:${backupDate.minute.toString().padLeft(2, '0')}'
        : '未知';

    return NipaplayWindowScaffold(
      onClose: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择恢复内容',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 备份信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '备份时间: $dateStr  版本: v${preview.appVersion}',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 可滚动的选择区域
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 全选
                    _buildCheckboxTile(
                      title: '全选',
                      subtitle: '恢复所有数据',
                      value: _isAllSelected,
                      onChanged: _toggleAll,
                      accentColor: accentColor,
                      colorScheme: colorScheme,
                    ),
                    const Divider(height: 24),
                    // 偏好设置
                    if (preview.hasPreferences)
                      _buildCheckboxTile(
                        title: '偏好设置',
                        subtitle: '软件设置（语言、弹幕、播放器等）',
                        value: _selections[BackupCategory.preferences]!,
                        onChanged: (v) =>
                            _toggle(BackupCategory.preferences, v),
                        accentColor: accentColor,
                        colorScheme: colorScheme,
                      ),
                    if (preview.hasPreferences) const SizedBox(height: 4),
                    // 媒体库
                    if (preview.hasMediaLibraries)
                      _buildCheckboxTile(
                        title: '添加的媒体库',
                        subtitle: _buildMediaLibrariesSubtitle(preview),
                        value: _selections[BackupCategory.mediaLibraries]!,
                        onChanged: (v) =>
                            _toggle(BackupCategory.mediaLibraries, v),
                        accentColor: accentColor,
                        colorScheme: colorScheme,
                      ),
                    if (preview.hasMediaLibraries) const SizedBox(height: 4),
                    // 观看历史
                    if (preview.hasWatchHistory)
                      _buildCheckboxTile(
                        title: '观看历史',
                        subtitle: '${preview.watchHistoryCount} 条记录',
                        value: _selections[BackupCategory.watchHistory]!,
                        onChanged: (v) =>
                            _toggle(BackupCategory.watchHistory, v),
                        accentColor: accentColor,
                        colorScheme: colorScheme,
                      ),
                    if (preview.hasWatchHistory) const SizedBox(height: 4),
                    // 剧集匹配
                    if (preview.hasEpisodeMatches)
                      _buildCheckboxTile(
                        title: '剧集匹配',
                        subtitle: '${preview.episodeMatchCount} 条匹配',
                        value: _selections[BackupCategory.episodeMatches]!,
                        onChanged: (v) =>
                            _toggle(BackupCategory.episodeMatches, v),
                        accentColor: accentColor,
                        colorScheme: colorScheme,
                      ),
                    if (preview.hasEpisodeMatches) const SizedBox(height: 4),
                    // 账户绑定
                    if (preview.hasAccounts)
                      _buildCheckboxTile(
                        title: '账户绑定',
                        subtitle: '已绑定的账户信息',
                        value: _selections[BackupCategory.accounts]!,
                        onChanged: (v) => _toggle(BackupCategory.accounts, v),
                        accentColor: accentColor,
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 底部按钮（固定在底部）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HoverScaleTextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      const Text('取消', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 16),
                HoverScaleTextButton(
                  onPressed: _selections.values.any((v) => v)
                      ? () {
                          final selected = _selections.entries
                              .where((e) => e.value)
                              .map((e) => e.key)
                              .toSet();
                          Navigator.of(context).pop(selected);
                        }
                      : null,
                  child:
                      const Text('确定', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accentColor,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                checkColor: Colors.white,
                side: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildMediaLibrariesSubtitle(BackupPreviewInfo preview) {
    final parts = <String>[];
    if (preview.localLibraryCount > 0) {
      parts.add('${preview.localLibraryCount} 本地库');
    }
    if (preview.serverProfileCount > 0) {
      parts.add('${preview.serverProfileCount} 服务器');
    }
    if (preview.webdavConnectionCount > 0) {
      parts.add('${preview.webdavConnectionCount} WebDAV');
    }
    if (preview.smbConnectionCount > 0) {
      parts.add('${preview.smbConnectionCount} SMB');
    }
    if (preview.hasDandanplayRemote) {
      parts.add('DDP远程');
    }
    if (preview.hasNipaplayShare) {
      parts.add('共享服务');
    }
    if (parts.isEmpty) parts.add('无连接');
    return parts.join(', ');
  }
}
