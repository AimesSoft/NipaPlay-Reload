import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_torrent_download_dialogs.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/desktop_torrent_download_dialogs.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

class AdaptiveTorrentDownloadDialogs {
  const AdaptiveTorrentDownloadDialogs._();

  static Future<AddTorrentDialogResult?> showAddTorrent(
    BuildContext context, {
    required Widget content,
  }) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoBottomSheet.show<AddTorrentDialogResult>(
        context: context,
        title: AddTorrentDialogViewModel.title,
        floatingTitle: true,
        heightRatio: 0.94,
        child: content,
      );
    }
    return NipaplayWindow.show<AddTorrentDialogResult>(
      context: context,
      barrierDismissible: false,
      child: content,
    );
  }

  static Future<bool> confirmDelete(
    BuildContext context,
    TorrentDeleteDialogViewModel data,
  ) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoTorrentDownloadDialogs.confirmDelete(context, data);
    }
    return DesktopTorrentDownloadDialogs.confirmDelete(context, data);
  }

  static Future<TorrentTaskFile?> selectPlayableFile(
    BuildContext context,
    TorrentPlayableFilesDialogViewModel data,
  ) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoTorrentDownloadDialogs.selectPlayableFile(context, data);
    }
    return DesktopTorrentDownloadDialogs.selectPlayableFile(context, data);
  }
}
