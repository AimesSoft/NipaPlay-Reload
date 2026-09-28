import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/harmony_local_media_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/platform_identity.dart' as platform;

/// Shared by both local media entry points. Importing is specific to media;
/// download destinations and app storage settings must still choose directories.
Future<String?> pickLocalMediaDirectory(BuildContext context) async {
  if (!platform.isHarmonyOS) return FilePickerService().pickDirectory();
  return pickHarmonyLocalMediaDirectory(context);
}

/// Kept separate so the complete HarmonyOS flow can be exercised on a host
/// with a fake native channel, including navigation and cancellation.
Future<String?> pickHarmonyLocalMediaDirectory(BuildContext context) async {
  try {
    final directory = await HarmonyLocalMediaService.pickMediaDirectory();
    if (directory == null) return null;
    if (await HarmonyLocalMediaService.canReadDirectory(directory)) {
      return directory;
    }
    throw PlatformException(
      code: 'directory-access-denied',
      message: '所选文件夹无法读取。',
    );
  } on PlatformException catch (error) {
    if (!HarmonyLocalMediaService.canOfferImport(error) || !context.mounted) {
      rethrow;
    }
    final accepted = await BlurDialog.show<bool>(
      context: context,
      title: '导入本地视频',
      content: '${error.message ?? '当前设备无法直接添加文件夹。'}\n\n'
          '可以选择一个或多个 MP4、MKV 视频，复制到 NipaPlay 的本地媒体库。'
          '导入会额外占用存储空间，原文件会保留；卸载应用会删除导入的副本。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('选择视频并导入'),
        ),
      ],
    );
    if (accepted != true || !context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final progressRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('正在导入视频'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('请选择视频。大文件复制需要一些时间，请保持应用打开。'),
            ],
          ),
        ),
      ),
    );
    unawaited(navigator.push(progressRoute));
    HarmonyMediaImportResult? imported;
    try {
      imported = await HarmonyLocalMediaService.importMediaFiles();
    } finally {
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
    }
    if (imported == null) return null;
    if (context.mounted) {
      BlurSnackBar.show(
        context,
        imported.failedCount == 0
            ? '已导入 ${imported.importedCount} 个视频'
            : '已导入 ${imported.importedCount} 个视频，${imported.failedCount} 个失败，请检查空间和文件权限。',
      );
    }
    return imported.directory;
  }
}
