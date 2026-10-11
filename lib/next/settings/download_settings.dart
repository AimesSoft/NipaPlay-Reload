import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';

import '../downloads/download_paths.dart';
import 'registry.dart';

abstract final class DownloadSettings {
  static DownloaderSettingsProvider? provider;

  static List<SettingEntry> entries() {
    SettingEntry toggle(
            String key,
            String storageKey,
            String title,
            String description,
            Future<void> Function(DownloaderSettingsProvider, bool) setter) =>
        SettingEntry(
          key: key,
          title: title,
          description: description,
          schema: const BooleanSchema(),
          defaultValue: true,
          storageKey: storageKey,
          reader: 'SettingsStorage.loadBool',
          writer: switch (key) {
            'download.enabled' => 'DownloaderSettingsProvider.setEnabled',
            'download.createFolderForTask' =>
              'DownloaderSettingsProvider.setCreateFolderForTask',
            _ => 'DownloaderSettingsProvider.setAutoScanCompletedTasks',
          },
          visible: () => globals.isDownloaderSupportedPlatform,
          decodeStorage: (value) => value ?? true,
          read: () => SettingsStorage.loadBool(storageKey, defaultValue: true),
          write: (value) async {
            final attached = provider;
            if (attached == null) {
              throw const Failure(FailureCode.unavailable,
                  'Downloader settings are not attached.');
            }
            await attached.loaded;
            await setter(attached, value as bool);
          },
        );
    return [
      toggle('download.enabled', SettingsKeys.downloaderEnabled, '启用下载器',
          '沿用 Classic 开关：关闭隐藏下载器 Tab，不暂停或删除已有任务。', (p, v) => p.setEnabled(v)),
      toggle(
          'download.createFolderForTask',
          SettingsKeys.downloaderCreateFolderForTask,
          '下载时创建同名文件夹',
          '用于新任务；download.add 可单次覆盖。',
          (p, v) => p.setCreateFolderForTask(v)),
      toggle(
          'download.autoScanCompletedTasks',
          SettingsKeys.downloaderAutoScanCompletedTasks,
          '完成后自动加入媒体库',
          '复用 Classic 扫描与扫描记录。未识别文件不会伪造作品或剧集身份。',
          (p, v) => p.setAutoScanCompletedTasks(v)),
      SettingEntry(
        key: 'download.directory',
        title: '默认下载目录',
        description:
            '新任务的绝对路径；空字符串恢复应用默认目录。操作系统目录授权使用 playback.authorize_directory。不会移动已有任务。',
        schema: const StringSchema(),
        defaultValue: '',
        scope: 'device',
        storageKey: SettingsKeys.torrentDownloadDirectory,
        reader:
            'SettingsStorage.loadString / StorageService.getDownloadsDirectory',
        writer: 'TorrentDownloadService.setDownloadDirectory',
        visible: () => globals.isDownloaderSupportedPlatform,
        decodeStorage: (value) => value ?? '',
        read: () async {
          final saved = await SettingsStorage.loadString(
              SettingsKeys.torrentDownloadDirectory);
          return saved.isEmpty
              ? (await StorageService.getDownloadsDirectory()).path
              : saved;
        },
        write: (value) async {
          var path = value as String;
          if (path.isEmpty) {
            path = (await StorageService.getDownloadsDirectory()).path;
          }
          validateDownloadDirectory(path);
          await TorrentDownloadService.instance.setDownloadDirectory(path);
        },
      ),
    ];
  }
}
