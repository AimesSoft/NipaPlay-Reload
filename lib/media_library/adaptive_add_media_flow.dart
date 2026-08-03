import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_smb_connection_dialog.dart'
    as cupertino_smb;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_webdav_connection_dialog.dart'
    as cupertino_webdav;
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart'
    as desktop_smb;
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart'
    as desktop_webdav;

class AdaptiveAddMediaResult {
  const AdaptiveAddMediaResult({
    this.sectionId,
    this.connectionsChanged = false,
  });

  final String? sectionId;
  final bool connectionsChanged;
}

/// Shows the same add-media picker and connection flow from every entry point.
Future<AdaptiveAddMediaResult?> showAdaptiveAddMediaFlow(
  BuildContext context,
) async {
  final selection = await showAdaptiveMediaSourcePicker(context);
  if (!context.mounted || selection == null) return null;

  switch (selection) {
    case 'local_folder':
      return _addLocalFolder(context);
    case 'webdav':
      return _addWebDav(context);
    case 'smb':
      return _addSmb(context);
    case 'jellyfin':
      return _configureNetworkServer(context, MediaServerType.jellyfin);
    case 'emby':
      return _configureNetworkServer(context, MediaServerType.emby);
    case 'dandanplay':
      return _configureDandanplay(context);
    case 'nipaplay':
      return _addSharedHost(context);
  }
  return null;
}

Future<AdaptiveAddMediaResult?> _addLocalFolder(
  BuildContext context,
) async {
  if (kIsWeb) return null;
  final scanService = context.read<ScanService>();
  if (scanService.isScanning) {
    _showMessage(context, '已有扫描任务在进行中，请稍后');
    return null;
  }
  final directory = await FilePickerService().pickDirectory();
  if (!context.mounted || directory == null || directory.trim().isEmpty) {
    return null;
  }
  await scanService.startDirectoryScan(
    directory,
    skipPreviouslyMatchedUnwatched: false,
  );
  if (!context.mounted) return null;
  _showMessage(context, '已开始扫描：${path.basename(directory)}');
  return const AdaptiveAddMediaResult(
    sectionId: MediaLibrarySectionIds.localManagement,
  );
}

Future<AdaptiveAddMediaResult?> _addWebDav(BuildContext context) async {
  final isPhone = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
  final result = isPhone
      ? await cupertino_webdav.CupertinoWebDAVConnectionDialog.show(context)
      : await desktop_webdav.WebDAVConnectionDialog.show(context);
  if (!context.mounted || result != true) return null;
  return const AdaptiveAddMediaResult(
    sectionId: MediaLibrarySectionIds.webdavManagement,
    connectionsChanged: true,
  );
}

Future<AdaptiveAddMediaResult?> _addSmb(BuildContext context) async {
  final isPhone = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
  final result = isPhone
      ? await cupertino_smb.CupertinoSmbConnectionDialog.show(context)
      : await desktop_smb.SMBConnectionDialog.show(context);
  if (!context.mounted || result != true) return null;
  return const AdaptiveAddMediaResult(
    sectionId: MediaLibrarySectionIds.smbManagement,
    connectionsChanged: true,
  );
}

Future<AdaptiveAddMediaResult?> _configureNetworkServer(
  BuildContext context,
  MediaServerType type,
) async {
  final result = await NetworkMediaServerDialog.show(context, type);
  if (!context.mounted || result != true) return null;
  return AdaptiveAddMediaResult(
    sectionId: type == MediaServerType.jellyfin
        ? MediaLibrarySectionIds.jellyfin
        : MediaLibrarySectionIds.emby,
  );
}

Future<AdaptiveAddMediaResult?> _configureDandanplay(
  BuildContext context,
) async {
  final surface = AppDisplaySurfaceScope.of(context);
  final provider = context.read<DandanplayRemoteProvider>();
  if (!provider.isInitialized) await provider.initialize();
  if (!context.mounted) return null;

  if (surface == AppDisplaySurface.phone) {
    final config = await showCupertinoDandanplayConnectionDialog(
      context: context,
      provider: provider,
    );
    if (config == null) return null;
    await provider.connect(config.baseUrl, token: config.apiToken);
    return const AdaptiveAddMediaResult(
      sectionId: MediaLibrarySectionIds.dandanplay,
    );
  }

  final result = await BlurLoginDialog.show(
    context,
    title: provider.isConnected ? '更新弹弹play远程连接' : '连接弹弹play远程服务',
    loginButtonText: provider.isConnected ? '保存' : '连接',
    fields: [
      LoginField(
        key: 'baseUrl',
        label: '远程服务地址',
        hint: '例如 http://192.168.1.2:23333',
        initialValue: provider.serverUrl ?? '',
      ),
      const LoginField(
        key: 'token',
        label: 'API密钥 (可选)',
        isPassword: true,
        required: false,
      ),
    ],
    onLogin: (values) async {
      try {
        await provider.connect(
          values['baseUrl'] ?? '',
          token: values['token'],
        );
        return const LoginResult(success: true, message: '连接成功');
      } catch (error) {
        return LoginResult(success: false, message: '$error');
      }
    },
  );
  if (!context.mounted || result != true) return null;
  return const AdaptiveAddMediaResult(
    sectionId: MediaLibrarySectionIds.dandanplay,
  );
}

Future<AdaptiveAddMediaResult?> _addSharedHost(BuildContext context) async {
  final provider = context.read<SharedRemoteLibraryProvider>();
  final previousHostId = provider.activeHostId;
  await SharedRemoteHostSelectionSheet.show(context);
  if (!context.mounted) return null;
  final activeHostId = provider.activeHostId;
  if (activeHostId == null || activeHostId == previousHostId) return null;
  return const AdaptiveAddMediaResult(
    sectionId: MediaLibrarySectionIds.shared,
  );
}

void _showMessage(BuildContext context, String message) {
  if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.info,
    );
    return;
  }
  BlurSnackBar.show(context, message);
}
