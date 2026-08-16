import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/backup_file_type_groups.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isProcessing = false;
  bool _autoSyncEnabled = false;
  String _syncServerUrl = '';
  String _syncUsername = '';
  String _syncPassword = '';
  String _syncRemotePath = AutoSyncSettings.defaultRemotePath;
  int _syncIntervalMinutes = AutoSyncSettings.defaultIntervalMinutes;
  Set<BackupCategory> _syncCategories = BackupCategory.values.toSet();
  bool _syncOnRecordChange = false;
  DateTime? _lastSyncAt;
  String? _lastSyncError;

  bool get _useIosDocumentExporter => !kIsWeb && Platform.isIOS;
  bool get _hasSyncConfiguration =>
      _syncServerUrl.trim().isNotEmpty &&
      _syncRemotePath.trim().isNotEmpty &&
      _syncCategories.isNotEmpty;
  bool get _canManualSync =>
      _autoSyncEnabled && _hasSyncConfiguration && !_isProcessing;

  Future<String> _createIosBackupExportPath(String fileName) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      path.join(temporaryDirectory.path, 'nipaplay_backup_exports'),
    );
    await exportDirectory.create(recursive: true);
    return path.join(exportDirectory.path, fileName);
  }

  @override
  void initState() {
    super.initState();
    _loadAutoSyncSettings();
  }

  Future<void> _loadAutoSyncSettings() async {
    final values = await Future.wait<dynamic>([
      AutoSyncSettings.isEnabled(),
      AutoSyncSettings.getServerUrl(),
      AutoSyncSettings.getUsername(),
      AutoSyncSettings.getPassword(),
      AutoSyncSettings.getRemotePath(),
      AutoSyncSettings.getIntervalMinutes(),
      AutoSyncSettings.getCategories(),
      AutoSyncSettings.getLastSyncAt(),
      AutoSyncSettings.getLastSyncError(),
      AutoSyncSettings.getSyncOnRecordChange(),
    ]);
    if (!mounted) return;
    setState(() {
      _autoSyncEnabled = values[0] as bool;
      _syncServerUrl = values[1] as String;
      _syncUsername = values[2] as String;
      _syncPassword = values[3] as String;
      _syncRemotePath = values[4] as String;
      _syncIntervalMinutes = values[5] as int;
      _syncCategories = values[6] as Set<BackupCategory>;
      _lastSyncAt = values[7] as DateTime?;
      _lastSyncError = values[8] as String?;
      _syncOnRecordChange = values[9] as bool;
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    if (enabled && _syncServerUrl.trim().isEmpty) {
      await _showSyncSettingsDialog(enableAfterSave: true);
      return;
    }
    setState(() {
      _isProcessing = true;
    });

    try {
      if (enabled) {
        await AutoSyncService.instance.enable();
        _showMessage('多端增量同步已启用');
      } else {
        await AutoSyncService.instance.disable();
        _showMessage('多端增量同步已禁用');
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

  Future<void> _showSyncSettingsDialog({bool enableAfterSave = false}) async {
    final result = await NipaplayWindow.show<_SyncSettingsValue>(
      context: context,
      child: _SyncSettingsDialog(
        initialValue: _SyncSettingsValue(
          serverUrl: _syncServerUrl,
          username: _syncUsername,
          password: _syncPassword,
          remotePath: _syncRemotePath,
          intervalMinutes: _syncIntervalMinutes,
          categories: _syncCategories,
          syncOnRecordChange: _syncOnRecordChange,
        ),
      ),
    );
    if (result == null) return;

    setState(() => _isProcessing = true);
    try {
      await AutoSyncSettings.saveWebDavConfiguration(
        serverUrl: result.serverUrl,
        username: result.username,
        password: result.password,
        remotePath: result.remotePath,
        intervalMinutes: result.intervalMinutes,
        categories: result.categories,
        syncOnRecordChange: result.syncOnRecordChange,
      );
      if (enableAfterSave) {
        await AutoSyncService.instance.enable();
        _showMessage('WebDAV 配置已保存并启用同步');
      } else {
        await AutoSyncService.instance.reloadSchedule();
        _showMessage('WebDAV 同步设置已保存');
      }
      await _loadAutoSyncSettings();
    } catch (e) {
      _showMessage('保存同步设置失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _manualSync() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await AutoSyncService.instance.manualSync();
      _showMessage(
        result.createdRepository
            ? '同步仓库已创建，基准快照上传完成'
            : '同步完成：下载 ${result.downloadedPatches} 个补丁，上传 ${result.uploadedOperations} 项变更',
      );
      if (mounted && result.restoredOperations > 0) {
        final watchHistoryProvider =
            Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.clearInvalidPathCache();
        await watchHistoryProvider.loadHistory();
      }
      await _loadAutoSyncSettings();
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

    final backupService = FullBackupService();
    String? selectedDirectory;
    String? selectedFilePath;
    try {
      if (_useIosDocumentExporter) {
        selectedFilePath = await _createIosBackupExportPath(
          backupService.buildBackupFileName(result),
        );
      } else {
        selectedDirectory = await getDirectoryPath(
          confirmButtonText: '选择保存位置',
        );
      }
    } catch (error) {
      _showMessage('备份失败: $error', isError: true);
      return;
    }

    if (selectedDirectory == null && selectedFilePath == null) {
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

      final filePath = selectedFilePath != null
          ? await backupService.exportBackupToFile(
              filePath: selectedFilePath,
              categories: result,
              appVersion: appVersion,
            )
          : await backupService.exportBackup(
              directoryPath: selectedDirectory!,
              categories: result,
              appVersion: appVersion,
            );

      if (filePath != null) {
        if (_useIosDocumentExporter) {
          await SystemShareService.exportFile(filePath);
          _showMessage('备份已生成，请在系统文件选择器中选择保存位置');
        } else {
          _showMessage('备份成功！文件保存至: $filePath');
        }
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
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: [
          buildBackupFileTypeGroup(
            label: 'NipaPlay 完整备份',
            extension: 'npb',
          ),
        ],
      );
    } catch (e) {
      _showMessage('无法打开系统文件选择器: $e', isError: true);
      return;
    }

    if (file == null) {
      _showMessage('未选择文件');
      return;
    }

    if (!hasBackupFileExtension(file.path, 'npb')) {
      _showMessage('请选择 .npb 格式的完整备份文件', isError: true);
      return;
    }

    final filePath = file.path;

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
          child: const Text('取消'),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认'),
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
      final backupService = BackupService();
      String? selectedDirectory;
      String? selectedFilePath;
      if (_useIosDocumentExporter) {
        selectedFilePath = await _createIosBackupExportPath(
          backupService.buildWatchHistoryBackupFileName(),
        );
      } else {
        selectedDirectory = await getDirectoryPath(
          confirmButtonText: '选择保存位置',
        );
      }

      if (selectedDirectory == null && selectedFilePath == null) {
        _showMessage('未选择保存位置');
        return;
      }

      final result = selectedFilePath != null
          ? await backupService.exportWatchHistoryToFile(selectedFilePath)
          : await backupService.exportWatchHistory(selectedDirectory!);

      if (result != null) {
        if (_useIosDocumentExporter) {
          await SystemShareService.exportFile(result);
          _showMessage('备份已生成，请在系统文件选择器中选择保存位置');
        } else {
          _showMessage('备份成功！文件保存至: $result');
        }
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
      final XFile? file = await openFile(
        acceptedTypeGroups: [
          buildBackupFileTypeGroup(
            label: 'NipaPlay 历史备份',
            extension: 'nph',
          ),
        ],
      );

      if (file == null) {
        _showMessage('未选择文件');
        return;
      }

      if (!hasBackupFileExtension(file.path, 'nph')) {
        _showMessage('请选择 .nph 格式的观看记录备份文件', isError: true);
        return;
      }

      final filePath = file.path;

      if (!mounted) return;
      final confirmed = await BlurDialog.show<bool>(
        context: context,
        title: '确认恢复',
        content: '恢复操作将会合并备份文件中的观看进度（包括截图）到当前记录中，且只会恢复本地存在的媒体文件的进度。是否继续？',
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
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
              title: '启用多端增量同步',
              subtitle: _autoSyncEnabled
                  ? '每 $_syncIntervalMinutes 分钟拉取索引并同步变更'
                  : '通过 WebDAV 在多个设备间同步所选数据',
              enabled: !_isProcessing,
              value: _autoSyncEnabled,
              onChanged: _toggleAutoSync,
              icon: Icons.cloud_sync,
            ),
            AdaptiveSettingsTile<void>.card(
              title: 'WebDAV 与同步内容',
              subtitle: _syncServerUrl.isEmpty
                  ? '配置服务器、远端目录、同步周期和数据类型'
                  : '${Uri.tryParse(_syncServerUrl)?.host ?? _syncServerUrl}$_syncRemotePath · ${_syncCategories.length} 类数据',
              enabled: !_isProcessing,
              onTap: _showSyncSettingsDialog,
              icon: Icons.cloud_outlined,
            ),
            AdaptiveSettingsTile<void>.card(
              title: '立即同步',
              subtitle: _buildSyncStatusSubtitle(),
              enabled: _canManualSync,
              onTap: _manualSync,
              icon: Icons.sync,
            ),
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
                  '增量同步：使用类 Git 原理进行数据同步，通过比较文件差异来实现，。\n'
                  '冲突规则：观看历史保留最近观看记录，其余数据保留本轮明确修改\n'
                  'Web 端暂不支持本地增量索引',
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

  String _buildSyncStatusSubtitle() {
    if (!_hasSyncConfiguration) return '请先配置 WebDAV 服务器和同步内容';
    if (!_autoSyncEnabled) return '开启多端增量同步后可手动同步';
    if (_lastSyncError != null && _lastSyncError!.isNotEmpty) {
      return '上次同步失败：$_lastSyncError';
    }
    if (_lastSyncAt == null) return '尚未完成首次同步';
    final value = _lastSyncAt!.toLocal();
    final formatted =
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '上次同步：$formatted';
  }
}

class _SyncSettingsValue {
  const _SyncSettingsValue({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.intervalMinutes,
    required this.categories,
    required this.syncOnRecordChange,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final int intervalMinutes;
  final Set<BackupCategory> categories;
  final bool syncOnRecordChange;
}

class _SyncSettingsDialog extends StatefulWidget {
  const _SyncSettingsDialog({required this.initialValue});

  final _SyncSettingsValue initialValue;

  @override
  State<_SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<_SyncSettingsDialog> {
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remotePathController;
  late Set<BackupCategory> _categories;
  late int _intervalMinutes;
  late bool _syncOnRecordChange;
  bool _obscurePassword = true;
  bool _testing = false;
  String? _testMessage;

  static const _intervalOptions = [5, 15, 30, 60, 180, 360];

  @override
  void initState() {
    super.initState();
    _serverController =
        TextEditingController(text: widget.initialValue.serverUrl);
    _usernameController =
        TextEditingController(text: widget.initialValue.username);
    _passwordController =
        TextEditingController(text: widget.initialValue.password);
    _remotePathController =
        TextEditingController(text: widget.initialValue.remotePath);
    _categories = Set<BackupCategory>.from(widget.initialValue.categories);
    _syncOnRecordChange = widget.initialValue.syncOnRecordChange;
    _intervalMinutes =
        _intervalOptions.contains(widget.initialValue.intervalMinutes)
            ? widget.initialValue.intervalMinutes
            : AutoSyncSettings.defaultIntervalMinutes;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    super.dispose();
  }

  String? _validationError() {
    final uri = Uri.tryParse(_serverController.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      return '请输入有效的 HTTP/HTTPS WebDAV 地址';
    }
    if (_remotePathController.text.trim().isEmpty) return '请输入远端同步目录';
    if (_categories.isEmpty) return '请至少选择一种同步数据';
    return null;
  }

  Future<void> _testConnection() async {
    final validationError = _validationError();
    if (validationError != null) {
      setState(() => _testMessage = validationError);
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      await AutoSyncService.instance.testConnection(
        serverUrl: _serverController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        remotePath: _normalizedRemotePath,
      );
      if (mounted) {
        setState(() => _testMessage = null);
        BlurSnackBar.show(context, '连接成功，远端目录可访问');
      }
    } catch (error) {
      if (mounted) setState(() => _testMessage = '连接失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String get _normalizedRemotePath {
    var value = _remotePathController.text.trim().replaceAll('\\', '/');
    if (!value.startsWith('/')) value = '/$value';
    while (value.contains('//')) {
      value = value.replaceAll('//', '/');
    }
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  void _submit() {
    final validationError = _validationError();
    if (validationError != null) {
      setState(() => _testMessage = validationError);
      return;
    }
    Navigator.of(context).pop(_SyncSettingsValue(
      serverUrl: _serverController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      remotePath: _normalizedRemotePath,
      intervalMinutes: _intervalMinutes,
      categories: _categories,
      syncOnRecordChange: _syncOnRecordChange,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NipaplayWindowScaffold(
      onClose: () => Navigator.of(context).pop(),
      child: SizedBox(
        width: 600,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WebDAV 多端同步',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: _serverController,
                        decoration: InputDecoration(
                          labelText: 'WebDAV 服务器地址',
                          hintText: 'https://dav.example.com/',
                          hintStyle: TextStyle(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.35),
                          ),
                          prefixIcon: const Icon(Icons.cloud_outlined),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: '用户名',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: '密码',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _remotePathController,
                              decoration: const InputDecoration(
                                labelText: '远端同步目录',
                                hintText: '/NipaPlay/sync',
                                prefixIcon: Icon(Icons.folder_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: _intervalMinutes,
                            items: _intervalOptions
                                .map((minutes) => DropdownMenuItem(
                                      value: minutes,
                                      child: Text(minutes < 60
                                          ? '$minutes 分钟'
                                          : '${minutes ~/ 60} 小时'),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _intervalMinutes = value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('记录变化时就同步'),
                        subtitle: const Text(
                          '建议只在自有 WebDAV 服务器时开启，防止快速占用服务商限额。',
                        ),
                        value: _syncOnRecordChange,
                        onChanged: (value) {
                          setState(() => _syncOnRecordChange = value);
                        },
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '同步的数据类型',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...BackupCategory.values.map((category) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_categoryTitle(category)),
                          subtitle: Text(_categorySubtitle(category)),
                          value: _categories.contains(category),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _categories.add(category);
                              } else {
                                _categories.remove(category);
                              }
                            });
                          },
                        );
                      }),
                      if (_testMessage != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _testMessage!,
                            style: TextStyle(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HoverScaleTextButton(
                    onPressed: _testing ? null : _testConnection,
                    child: Text(_testing ? '测试中...' : '测试连接'),
                  ),
                  const Spacer(),
                  HoverScaleTextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 16),
                  HoverScaleTextButton(
                    onPressed: _testing ? null : _submit,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryTitle(BackupCategory category) => switch (category) {
        BackupCategory.preferences => '偏好设置',
        BackupCategory.mediaLibraries => '添加的媒体库',
        BackupCategory.watchHistory => '观看历史',
        BackupCategory.episodeMatches => '剧集匹配',
        BackupCategory.accounts => '账户绑定',
      };

  String _categorySubtitle(BackupCategory category) => switch (category) {
        BackupCategory.preferences => '语言、弹幕、播放器等软件设置',
        BackupCategory.mediaLibraries => '在线、WebDAV、SMB 与共享服务（不含本地媒体库）',
        BackupCategory.watchHistory => '观看进度与历史记录',
        BackupCategory.episodeMatches => '文件和动画剧集的匹配关系',
        BackupCategory.accounts => '包含访问令牌，请仅同步到可信 WebDAV',
      };
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
                  child: const Text('取消'),
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
                  child: const Text('确定'),
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
                  child: const Text('取消'),
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
                  child: const Text('确定'),
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
