import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../danmaku/sidecar.dart';
import '../subtitles/library.dart';
import 'classic_settings.dart';
import 'registry.dart';

final class SystemSettings {
  SystemSettings(this.sidecars, this.subtitles);
  final SidecarIndexer sidecars;
  final SubtitleLibrary subtitles;
  bool startupScanEnabled = true;
  bool libraryNotifyEnabled = true;
  Future<void> load() async {
    startupScanEnabled = await SettingsStorage.loadBool(
        'next_startup_scan_enabled',
        defaultValue: true);
    libraryNotifyEnabled = await SettingsStorage.loadBool(
        'next_library_notify_enabled',
        defaultValue: true);
    sidecars.enabled = await SettingsStorage.loadBool(
        'next_sidecar_index_enabled',
        defaultValue: true);
    subtitles.enabled = await SettingsStorage.loadBool(
        'next_subtitle_probe_enabled',
        defaultValue: true);
  }

  List<SettingEntry> entries() {
    const sections = [
      MediaLibrarySectionIds.local,
      MediaLibrarySectionIds.localManagement,
      MediaLibrarySectionIds.webdav,
      MediaLibrarySectionIds.webdavManagement,
      MediaLibrarySectionIds.smb,
      MediaLibrarySectionIds.smbManagement,
      MediaLibrarySectionIds.shared,
      MediaLibrarySectionIds.sharedManagement,
      MediaLibrarySectionIds.dandanplay,
      MediaLibrarySectionIds.jellyfin,
      MediaLibrarySectionIds.emby
    ];
    SettingEntry entry(
            String key,
            String title,
            String storage,
            Schema schema,
            Object? fallback,
            Future<Object?> Function() read,
            Future<void> Function(Object?) write,
            {String description = '',
            String apply = 'immediate',
            bool writable = true,
            Object? Function(Object?)? decode,
            List<String> additional = const []}) =>
        SettingEntry(
            key: key,
            title: title,
            description: description,
            schema: schema,
            defaultValue: fallback,
            storageKey: storage,
            reader: 'Classic/Next shared settings',
            writer: 'SystemSettings',
            read: read,
            write: write,
            decodeStorage: decode ?? (v) => v ?? fallback,
            apply: apply,
            writable: writable,
            additionalStorageKeys: additional);
    return [
      entry(
          'appearance.classicLibrarySection',
          'Classic 片库分类',
          SettingsKeys.mediaLibrarySelectedSection,
          const StringSchema(values: sections),
          MediaLibrarySectionIds.local,
          () => SettingsStorage.loadString(
              SettingsKeys.mediaLibrarySelectedSection,
              defaultValue: MediaLibrarySectionIds.local),
          (v) => SettingsStorage.saveString(
              SettingsKeys.mediaLibrarySelectedSection, v as String),
          apply: 'restart_app',
          description: 'Classic 页面创建时加载；不可用分类沿用 Classic 选择。实时导航用 ui.open。'),
      entry(
          'appearance.classicLibrarySectionOrder',
          'Classic 片库来源排序',
          SettingsKeys.mediaLibrarySectionOrder,
          const ArraySchema(StringSchema(values: sections)),
          const <String>[],
          () => SettingsStorage.loadStringList(
              SettingsKeys.mediaLibrarySectionOrder), (v) async {
        final ids = (v as List).cast<String>();
        if (ids.toSet().length != ids.length) {
          throw const Failure(
              FailureCode.invalidInput, 'Each section id can occur once.');
        }
        await SettingsStorage.saveStringList(
            SettingsKeys.mediaLibrarySectionOrder, ids);
      },
          apply: 'restart_app',
          description: 'Classic 来源区恢复时使用；新来源保留。当前已打开页面不自动重载。'),
      entry(
          'network.mediaServerUserAgent',
          '媒体服务器连接 User-Agent',
          SettingsKeys.mediaServerConnectionUserAgent,
          const StringSchema(maxLength: 512),
          '',
          MediaServerTransport.getStoredConnectionUserAgent, (v) async {
        await MediaServerTransport.saveConnectionUserAgent(v as String);
      }, description: 'Jellyfin/Emby 的 API、图片和播放同步 UA。空串恢复默认；新请求生效，不改变播放器 UA。'),
      entry(
          'network.dandanplayMode',
          '官方网关模式',
          'dandanplay_server_mode',
          const StringSchema(values: ['auto', 'hongKong', 'china', 'custom']),
          'auto',
          () async => (await NetworkSettings.getDandanplayServerMode()).name,
          (v) async {
        if (v == 'custom') {
          throw const Failure(FailureCode.invalidInput,
              'Selecting a custom credential destination requires the user in Classic network settings.');
        }
        await NetworkSettings.setDandanplayServerMode(
            DandanplayServerMode.values.byName(v as String));
      },
          decode: (v) => v == 'hongkong' ? 'hongKong' : v ?? 'auto',
          description:
              '可选择 auto/hongKong/china；custom 仅描述现有用户信任选择，不允许通过普通设置切换到第三方 origin。'),
      entry(
          'storage.clearDanmakuOnLaunch',
          '启动时清理 Classic 弹幕缓存',
          SettingsKeys.clearDanmakuCacheOnLaunch,
          const BooleanSchema(),
          false,
          () =>
              SettingsStorage.loadBool(SettingsKeys.clearDanmakuCacheOnLaunch),
          (v) async {
        await SettingsStorage.saveBool(
            SettingsKeys.clearDanmakuCacheOnLaunch, v as bool);
        if (v) {
          await DanmakuCacheManager.clearAllCache();
        }
      },
          description:
              '与 Classic 设置相同：启用时立即清理一次可重新取得的 Classic 缓存，并在启动时清理。Next 导入的唯一副本保留。'),
      for (final kind in ['startupScan', 'sidecarIndex', 'subtitleProbe'])
        entry(
            'library.${kind}Enabled',
            '$kind 自动行为',
            switch (kind) {
              'startupScan' => 'next_startup_scan_enabled',
              'sidecarIndex' => 'next_sidecar_index_enabled',
              _ => 'next_subtitle_probe_enabled'
            },
            const BooleanSchema(),
            true,
            () async => switch (kind) {
                  'startupScan' => startupScanEnabled,
                  'sidecarIndex' => sidecars.enabled,
                  _ => subtitles.enabled
                }, (v) async {
          await SettingsStorage.saveBool(
              switch (kind) {
                'startupScan' => 'next_startup_scan_enabled',
                'sidecarIndex' => 'next_sidecar_index_enabled',
                _ => 'next_subtitle_probe_enabled'
              },
              v as bool);
          switch (kind) {
            case 'startupScan':
              startupScanEnabled = v;
            case 'sidecarIndex':
              await sidecars.setEnabled(v);
            case 'subtitleProbe':
              await subtitles.setEnabled(v);
          }
        },
            description: kind == 'startupScan'
                ? 'Next 开启时的启动扫描；下一次启动生效。Next 关闭时沿用 Classic 行为。不取消正在执行的扫描。'
                : '独立控制 Next 的自动附件检查。关闭后当前文件排空，待处理队列保留；显式检查不受影响。开启后立即核对。'),
      entry(
          'library.notifyNipaEnabled',
          '新进片库时让 Nipa 在后台办好',
          'next_library_notify_enabled',
          const BooleanSchema(),
          true,
          () async => libraryNotifyEnabled,
          (v) async {
            await SettingsStorage.saveBool(
                'next_library_notify_enabled', v as bool);
            libraryNotifyEnabled = v;
          },
          description:
              '开启时，新进片库的文件（用户添加的文件夹、Classic 扫描、媒体来源同步）合成一批，交给一个后台帮手，结果记在动态里，不进主会话；用户不在旁边时片库也会办好。Nipa 自己的操作带进来的文件回到她发起的会话。'
              '关闭后不再发送，关闭期间进来的文件之后不补发。已发出的不撤回。'),
      entry(
          'danmaku.spoilerAiConfigured',
          '防剧透 AI 凭据是否已设置',
          '@runtime:spoilerConfigured',
          const BooleanSchema(),
          false,
          () async =>
              (await CredentialStore.instance.read(
                      await SharedPreferences.getInstance(),
                      SettingsKeys.spoilerAiApiKey))
                  ?.isNotEmpty ==
              true,
          (_) async {},
          writable: false,
          description:
              '只返回是否设置，不返回或写入秘密。spoiler_ai_use_custom_key 由现有实现固定为 true。'),
      entry(
          'appearance.animeDetailDisplayMode',
          'Classic 详情显示模式',
          'anime_detail_display_mode',
          const StringSchema(values: ['simple', 'vivid']),
          'simple',
          () => SettingsStorage.loadString('anime_detail_display_mode',
              defaultValue: 'simple'),
          (v) => SettingsStorage.saveString(
              'anime_detail_display_mode', v as String),
          apply: 'restart_app',
          description: 'Classic 显示偏好；重启后加载到主题，不改变 Next 详情。'),
      entry(
          'appearance.remoteAccessQrVisible',
          '显示 Classic 连接二维码',
          SettingsKeys.showRemoteAccessQrCode,
          const BooleanSchema(),
          false, () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(SettingsKeys.showRemoteAccessQrCode) ??
            prefs.getBool(SettingsKeys.labsShowRemoteAccessQrCode) ??
            false;
      },
          (v) => SettingsStorage.saveBool(
              SettingsKeys.showRemoteAccessQrCode, v as bool),
          apply: 'restart_app',
          additional: [SettingsKeys.labsShowRemoteAccessQrCode],
          description:
              '只保存显示偏好，重启后 provider 读取。不返回二维码或认证链接，不开启监听。旧 labs 键仅作为读取兼容。'),
      for (final name in ['autoScroll', 'showTimestamp'])
        entry(
            'diagnostics.logViewer${name[0].toUpperCase()}${name.substring(1)}',
            'Classic 日志查看偏好 $name',
            name == 'autoScroll'
                ? 'debug_log_auto_scroll'
                : 'debug_log_show_timestamp',
            const BooleanSchema(),
            // The log window's own defaults: debug_log_viewer_page.dart.
            name != 'autoScroll',
            () => SettingsStorage.loadBool(
                name == 'autoScroll'
                    ? 'debug_log_auto_scroll'
                    : 'debug_log_show_timestamp',
                defaultValue: name != 'autoScroll'),
            (v) => SettingsStorage.saveBool(
                name == 'autoScroll'
                    ? 'debug_log_auto_scroll'
                    : 'debug_log_show_timestamp',
                v as bool),
            apply: 'restart_app',
            description: 'Classic 日志窗口重新创建时加载，当前已打开窗口不重载。'),
      if (kDebugMode) ...[
        entry(
            'diagnostics.canvasDanmakuCollisionBoxes',
            'Canvas 弹幕碰撞框',
            SettingsKeys.showCanvasDanmakuCollisionBoxes,
            const BooleanSchema(),
            false,
            () async => ClassicSettings
                .current.developer.showCanvasDanmakuCollisionBoxes,
            (v) => ClassicSettings.current.developer
                .setShowCanvasDanmakuCollisionBoxes(v as bool)),
        entry(
            'diagnostics.canvasDanmakuTrackNumbers',
            'Canvas 弹幕轨道号',
            SettingsKeys.showCanvasDanmakuTrackNumbers,
            const BooleanSchema(),
            false,
            () async =>
                ClassicSettings.current.developer.showCanvasDanmakuTrackNumbers,
            (v) => ClassicSettings.current.developer
                .setShowCanvasDanmakuTrackNumbers(v as bool)),
        entry(
            'diagnostics.gpuDanmakuCollisionBoxes',
            'GPU 弹幕碰撞框',
            SettingsKeys.showGpuDanmakuCollisionBoxes,
            const BooleanSchema(),
            false,
            () async =>
                ClassicSettings.current.developer.showGPUDanmakuCollisionBoxes,
            (v) => ClassicSettings.current.developer
                .setShowGPUDanmakuCollisionBoxes(v as bool)),
        entry(
            'diagnostics.gpuDanmakuTrackNumbers',
            'GPU 弹幕轨道号',
            SettingsKeys.showGpuDanmakuTrackNumbers,
            const BooleanSchema(),
            false,
            () async =>
                ClassicSettings.current.developer.showGPUDanmakuTrackNumbers,
            (v) => ClassicSettings.current.developer
                .setShowGPUDanmakuTrackNumbers(v as bool)),
      ],
    ];
  }
}
