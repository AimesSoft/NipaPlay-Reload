import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

class DesktopTorrentDownloadDialogs {
  const DesktopTorrentDownloadDialogs._();

  static Future<bool> confirmDelete(
    BuildContext context,
    TorrentDeleteDialogViewModel data,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final result = await BlurDialog.show<bool>(
      context: context,
      title: data.title,
      content: data.message,
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            data.cancelLabel,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7)),
          ),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          idleColor: colors.error,
          hoverColor: colors.error,
          child: Text(data.confirmLabel),
        ),
      ],
    );
    return result ?? false;
  }

  static Future<TorrentTaskFile?> selectPlayableFile(
    BuildContext context,
    TorrentPlayableFilesDialogViewModel data,
  ) {
    final colors = Theme.of(context).colorScheme;
    return BlurDialog.show<TorrentTaskFile>(
      context: context,
      title: data.title,
      contentWidget: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: data.files.length,
          separatorBuilder: (_, __) => Divider(
            color: colors.onSurface.withValues(alpha: 0.08),
            height: 1,
          ),
          itemBuilder: (dialogContext, index) {
            final file = data.files[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(file),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Ionicons.play_circle_outline,
                      color: colors.onSurface.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formatTorrentBytes(file.length),
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            data.cancelLabel,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7)),
          ),
        ),
      ],
    );
  }
}
