import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/emby_transcode_manager.dart';
import 'package:nipaplay/services/jellyfin_transcode_manager.dart';
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_preferences.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../danmaku/sidecar.dart';
import '../subtitles/library.dart';
import 'classic_settings.dart';
import 'effective.dart';
import 'registry.dart';
import 'setting_descriptions.dart';

final class SystemSettings {
  SystemSettings(this.sidecars, this.subtitles);
  final SidecarIndexer sidecars;
  final SubtitleLibrary subtitles;
  bool startupScanEnabled = true;
  JsonMap? startupScanStatus;
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
            String scope = 'user',
            bool Function()? visible,
            Object? Function()? dynamicDefault,
            List<SchemaViolation> Function(Object?)? validate,
            Object? Function(Object?)? decode,
            List<String> additional = const []}) =>
        SettingEntry(
            key: key,
            title: title,
            description: description.isEmpty
                ? systemSettingDescriptions[key] ?? ''
                : description,
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
            scope: scope,
            visible: visible,
            appliesTo: key == 'appearance.largeScreenLayout'
                ? const {
                    'platforms': ['desktop', 'tablet', 'television']
                  }
                : const <String, Object?>{},
            appliesNow: key == 'appearance.largeScreenLayout'
                ? () => globals.isDesktopOrTablet || globals.isTelevision
                : null,
            appliesReason: key == 'appearance.largeScreenLayout'
                ? () => globals.isDesktopOrTablet || globals.isTelevision
                    ? null
                    : '此设置只适用于桌面、平板或电视。'
                : null,
            dynamicDefaultValue: dynamicDefault,
            validateValue: validate,
            effective: EffectiveRules.resolve,
            additionalStorageKeys: additional);
    return [
      entry(
          'appearance.classicLibrarySection',
          'Classic 媒体库分类',
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
          'Classic 媒体库来源排序',
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
      entry('network.bangumiServerUrl', 'Bangumi API 服务器', 'bangumi_server_url',
          const StringSchema(maxLength: 512), '', () async {
        final server = await NetworkSettings.getBangumiServer();
        return NetworkSettings.isCustomBangumiServer(server) ? server : '';
      }, (v) async {
        final text = (v as String).trim();
        if (text.isEmpty) {
          await NetworkSettings.resetBangumiServer();
        } else {
          await NetworkSettings.setBangumiServer(text);
        }
      },
          validate: validateBangumiServer,
          description:
              '自定义 Bangumi API 服务器地址；空串使用官方服务器（${NetworkSettings.bangumiDefaultServer}）。只接受 http/https 地址，不带用户信息、query 或 fragment；缺少协议时按 https 补全，末尾斜杠去掉。Bangumi 登录令牌随请求发往该地址。换地址时清除旧地址的图片与详情缓存。读到的值为空表示官方服务器，请求实际使用的完整地址在 effective。'),
      entry(
          'network.mediaServerDeviceId',
          '媒体服务器设备 ID',
          'media_server_device_id_custom_v1',
          const StringSchema(maxLength: 128),
          '',
          () async =>
              await MediaServerDeviceIdService.instance.getCustomDeviceId() ??
              '', (v) async {
        final text = (v as String).trim();
        await MediaServerDeviceIdService.instance
            .setCustomDeviceId(text.isEmpty ? null : text);
      }, validate: (v) {
        final text = (v as String).trim();
        return text.isEmpty ||
                MediaServerDeviceIdService.isValidCustomDeviceId(text)
            ? []
            : [
                const SchemaViolation('/value',
                    'Use 1–128 characters without quotes or line breaks, or empty to use the generated ID.')
              ];
      },
          description:
              'Jellyfin/Emby 登录请求里的 DeviceId；服务器按它区分会话。空串使用自动生成的 ID（应用名-平台-随机 UUID）。读到的是自定义值，空串表示没有自定义；请求实际使用的 ID 在 effective。'),
      entry(
          'appearance.largeScreenLayout',
          '大屏幕布局',
          LargeScreenModePreferences.key,
          const BooleanSchema(),
          false,
          () => LargeScreenModePreferences.load(
              defaultValue: globals.isTelevision),
          (v) => LargeScreenModePreferences.save(v as bool),
          dynamicDefault: () => globals.isTelevision,
          apply: 'restart_app',
          visible: () => globals.isDesktopOrTablet || globals.isTelevision,
          description:
              '主窗口使用大屏幕布局。只保存偏好，主窗口创建时读取；在主窗口里切换时，Classic 还会同时让桌面窗口进入或退出全屏，此处不做。电视默认开启。'),
      entry(
          'appearance.classicLocalLibrarySort',
          'Classic 本地文件夹排序',
          'library_sort_option',
          const StringSchema(values: localLibrarySortOptions),
          'nameAscending', () async {
        final index = (await SharedPreferences.getInstance())
            .getInt('library_sort_option');
        return index != null &&
                index >= 0 &&
                index < localLibrarySortOptions.length
            ? localLibrarySortOptions[index]
            : 'nameAscending';
      },
          (v) => SettingsStorage.saveInt('library_sort_option',
              localLibrarySortOptions.indexOf(v as String)),
          apply: 'restart_app',
          description: 'Classic 本地媒体库文件夹视图的文件排序：文件名、修改时间或大小，升序或降序。页面创建时读取。'),
      for (final source in collectionSortSources)
        entry(
            'appearance.collectionSort.$source',
            'Classic $source 媒体库排序',
            'library_collection_sort_v1_$source',
            const StringSchema(values: collectionSortOptions),
            'comprehensive',
            () async =>
                (await SharedPreferences.getInstance())
                    .getString('library_collection_sort_v1_$source') ??
                'comprehensive',
            (v) => SettingsStorage.saveString(
                'library_collection_sort_v1_$source', v as String),
            decode: (v) =>
                collectionSortOptions.contains(v) ? v : 'comprehensive',
            apply: 'restart_app',
            description:
                'Classic $source 媒体库合集视图的排序：comprehensive 综合、recentlyAdded 最近添加、name 名称。页面创建时读取。'),
      for (final kind in unwatchedOnlyFilters.keys)
        entry(
            'appearance.unwatchedOnly.$kind',
            'Classic ${unwatchedOnlyFilters[kind]!.$2}只看未观看',
            unwatchedOnlyFilters[kind]!.$1,
            const BooleanSchema(),
            false,
            () => SettingsStorage.loadBool(unwatchedOnlyFilters[kind]!.$1),
            (v) => SettingsStorage.saveBool(
                unwatchedOnlyFilters[kind]!.$1, v as bool),
            apply: 'restart_app',
            description:
                'Classic ${unwatchedOnlyFilters[kind]!.$2}页面的“只看未观看”过滤开关。页面创建时读取。'),
      for (final server in ['jellyfin', 'emby']) ...[
        entry(
            'playback.${server}Transcoding',
            '${server == 'jellyfin' ? 'Jellyfin' : 'Emby'} 转码',
            '${server}_enable_transcoding',
            const BooleanSchema(),
            false,
            () => server == 'jellyfin'
                ? JellyfinTranscodeManager.instance.isTranscodingEnabled()
                : EmbyTranscodeManager.instance.isTranscodingEnabled(),
            (v) async {
          final ok = server == 'jellyfin'
              ? await (await _jellyfin()).setTranscodeEnabled(v as bool)
              : await (await _emby()).setTranscodeEnabled(v as bool);
          if (!ok) {
            throw const Failure(FailureCode.unavailable,
                'The transcoding preference could not be saved.');
          }
        },
            description:
                '${server == 'jellyfin' ? 'Jellyfin' : 'Emby'} 播放是否请求服务器转码。关闭时 Classic 同时把默认画质设为 original。新打开的视频使用；已在播放的视频用 playback.select_stream 切换。'),
        entry(
            'playback.${server}DefaultQuality',
            '${server == 'jellyfin' ? 'Jellyfin' : 'Emby'} 默认画质',
            '${server}_default_quality',
            StringSchema(
                values:
                    JellyfinVideoQuality.values.map((e) => e.name).toList()),
            JellyfinVideoQuality.bandwidth5m.name,
            () async => (server == 'jellyfin'
                    ? await JellyfinTranscodeManager.instance
                        .getDefaultVideoQuality()
                    : await EmbyTranscodeManager.instance
                        .getDefaultVideoQuality())
                .name, (v) async {
          final quality = JellyfinVideoQuality.values.byName(v as String);
          final bool ok;
          if (server == 'jellyfin') {
            final provider = await _jellyfin();
            ok = await provider.setDefaultVideoQuality(quality);
            // As Classic's quality menu does: a transcoded quality turns transcoding on.
            if (ok && quality != JellyfinVideoQuality.original) {
              await provider.setTranscodeEnabled(true);
            }
          } else {
            final provider = await _emby();
            ok = await provider.setDefaultVideoQuality(quality);
            if (ok && quality != JellyfinVideoQuality.original) {
              await provider.setTranscodeEnabled(true);
            }
          }
          if (!ok) {
            throw const Failure(FailureCode.unavailable,
                'The default quality could not be saved.');
          }
        },
            description:
                '${server == 'jellyfin' ? 'Jellyfin' : 'Emby'} 默认视频画质：auto 由服务器决定，bandwidth1m 至 bandwidth40m 为码率档，original 为原画（不转码）。选转码档时 Classic 同时打开转码。新打开的视频使用。'),
      ],
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
                ? '下次启动 Next 时，仅索引已授权本地目录中的文件；不执行 Classic 识别、元数据匹配或弹幕获取。不可用目录和远程来源会报告为跳过。Classic 启动扫描独立运行。'
                : '独立控制 Next 的自动附件检查。关闭后当前文件排空，待处理队列保留；显式检查不受影响。开启后立即核对。'),
      entry(
          'library.notifyNipaEnabled',
          '梨花带进媒体库的文件回报给她',
          'next_library_notify_enabled',
          const BooleanSchema(),
          true,
          () async => libraryNotifyEnabled, (v) async {
        await SettingsStorage.saveBool(
            'next_library_notify_enabled', v as bool);
        libraryNotifyEnabled = v;
      },
          description:
              '开启时，梨花自己的操作带进媒体库的文件合成一批，回到她发起的会话。GUI 添加文件夹另由“添加文件夹后交给梨花整理”控制；普通后台新增文件、Classic 扫描、媒体来源同步不回报。'
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

Future<JellyfinTranscodeProvider> _jellyfin() async {
  final provider = JellyfinTranscodeProvider();
  await provider.initialize();
  return provider;
}

Future<EmbyTranscodeProvider> _emby() async {
  final provider = EmbyTranscodeProvider();
  await provider.initialize();
  return provider;
}

/// Order of Classic's local library sort menu (stored as an index).
const localLibrarySortOptions = [
  'nameAscending',
  'nameDescending',
  'modifiedAscending',
  'modifiedDescending',
  'sizeAscending',
  'sizeDescending',
];
const collectionSortSources = ['local', 'webdav', 'smb'];
const collectionSortOptions = ['comprehensive', 'recentlyAdded', 'name'];

/// Filter name to (physical key, page title).
const unwatchedOnlyFilters = {
  'jellyfin': ('network_media_unwatched_only_jellyfin', 'Jellyfin 媒体库'),
  'emby': ('network_media_unwatched_only_emby', 'Emby 媒体库'),
  'shared': ('shared_library_unwatched_only', '共享媒体库'),
};

/// An http(s) address without credentials, query or fragment; a missing
/// scheme is read as https, as Classic's network settings do.
List<SchemaViolation> validateBangumiServer(Object? value) {
  final text = (value as String).trim();
  if (text.isEmpty) return [];
  final withScheme = text.startsWith('http://') || text.startsWith('https://')
      ? text
      : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      (!text.startsWith('http') && text.contains('://')) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return [
      const SchemaViolation('/value',
          'Use an http(s) address without credentials, query or fragment, or empty for the official server.')
    ];
  }
  var normalized = withScheme;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized == NetworkSettings.bangumiDefaultServer) {
    return [
      const SchemaViolation(
          '/value', 'Use an empty value for the official server.')
    ];
  }
  return [];
}
