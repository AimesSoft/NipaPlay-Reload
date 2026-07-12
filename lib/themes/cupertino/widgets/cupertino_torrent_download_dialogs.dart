import 'package:flutter/cupertino.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoTorrentDownloadDialogs {
  const CupertinoTorrentDownloadDialogs._();

  static Future<bool> confirmDelete(
    BuildContext context,
    TorrentDeleteDialogViewModel data,
  ) async {
    final result = await CupertinoBottomSheet.show<bool>(
      context: context,
      title: data.title,
      heightRatio: 0.44,
      child: CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 28),
            sliver: SliverList.list(
              children: [
                Text(
                  data.message,
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 15,
                            height: 1.4,
                          ),
                ),
                const SizedBox(height: 20),
                AdaptiveButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: AdaptiveButtonStyle.filled,
                  color: CupertinoColors.systemRed,
                  label: data.confirmLabel,
                ),
                const SizedBox(height: 10),
                AdaptiveButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: AdaptiveButtonStyle.gray,
                  label: data.cancelLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<TorrentTaskFile?> selectPlayableFile(
    BuildContext context,
    TorrentPlayableFilesDialogViewModel data,
  ) {
    return CupertinoBottomSheet.showSelection<TorrentTaskFile>(
      context: context,
      title: data.title,
      options: [
        for (final file in data.files)
          CupertinoBottomSheetOption(
            label: file.displayName,
            subtitle: formatTorrentBytes(file.length),
            value: file,
          ),
      ],
    );
  }
}
