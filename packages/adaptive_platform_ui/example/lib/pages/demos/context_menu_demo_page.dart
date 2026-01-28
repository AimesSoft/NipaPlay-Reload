import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Demo page showcasing AdaptiveContextMenu features
class ContextMenuDemoPage extends StatelessWidget {
  const ContextMenuDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Context Menu'),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final topPadding = PlatformInfo.isIOS ? 100.0 : 16.0;

    return ListView(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: topPadding,
        bottom: 16.0,
      ),
      children: [
        _buildSection(
          context,
          title: 'Basic Context Menus',
          children: [
            _buildContextMenuItem(
              context,
              title: 'Simple Menu',
              subtitle: 'Long press to show context menu',
              color: PlatformInfo.isIOS
                  ? CupertinoColors.systemBlue
                  : Colors.blue,
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Edit',
                  icon: PlatformInfo.isIOS ? CupertinoIcons.pencil : Icons.edit,
                  onPressed: () {
                    _showSnackbar(context, 'Edit pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Share',
                  icon: PlatformInfo.isIOS ? CupertinoIcons.share : Icons.share,
                  onPressed: () {
                    _showSnackbar(context, 'Share pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Delete',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.trash
                      : Icons.delete,
                  isDestructive: true,
                  onPressed: () {
                    _showSnackbar(context, 'Delete pressed');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildContextMenuItem(
              context,
              title: 'Photo Card',
              subtitle: 'Context menu with photo actions',
              color: PlatformInfo.isIOS
                  ? CupertinoColors.systemGreen
                  : Colors.green,
              actions: [
                AdaptiveContextMenuAction(
                  title: 'View',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.eye
                      : Icons.visibility,
                  onPressed: () {
                    _showSnackbar(context, 'View pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Download',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.cloud_download
                      : Icons.download,
                  onPressed: () {
                    _showSnackbar(context, 'Download pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Set as Wallpaper',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.photo
                      : Icons.wallpaper,
                  onPressed: () {
                    _showSnackbar(context, 'Set as wallpaper pressed');
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Message Actions',
          children: [
            _buildContextMenuItem(
              context,
              title: 'Message from John',
              subtitle: 'Hey! How are you doing?',
              color: PlatformInfo.isIOS
                  ? CupertinoColors.systemPurple
                  : Colors.purple,
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Reply',
                  icon: PlatformInfo.isIOS ? CupertinoIcons.reply : Icons.reply,
                  onPressed: () {
                    _showSnackbar(context, 'Reply pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Forward',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.arrowshape_turn_up_right
                      : Icons.forward,
                  onPressed: () {
                    _showSnackbar(context, 'Forward pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Copy',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.doc_on_doc
                      : Icons.copy,
                  onPressed: () {
                    _showSnackbar(context, 'Copy pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Delete',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.trash
                      : Icons.delete,
                  isDestructive: true,
                  onPressed: () {
                    _showSnackbar(context, 'Delete pressed');
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'File Operations',
          children: [
            _buildContextMenuItem(
              context,
              title: 'Document.pdf',
              subtitle: 'PDF file • 2.5 MB',
              color: PlatformInfo.isIOS
                  ? CupertinoColors.systemRed
                  : Colors.red,
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Open',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.folder_open
                      : Icons.open_in_new,
                  onPressed: () {
                    _showSnackbar(context, 'Open pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Rename',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.pencil
                      : Icons.drive_file_rename_outline,
                  onPressed: () {
                    _showSnackbar(context, 'Rename pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Move',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.folder
                      : Icons.drive_file_move,
                  onPressed: () {
                    _showSnackbar(context, 'Move pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Share',
                  icon: PlatformInfo.isIOS ? CupertinoIcons.share : Icons.share,
                  onPressed: () {
                    _showSnackbar(context, 'Share pressed');
                  },
                ),
                AdaptiveContextMenuAction(
                  title: 'Delete',
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.trash
                      : Icons.delete,
                  isDestructive: true,
                  onPressed: () {
                    _showSnackbar(context, 'Delete pressed');
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildInfoCard(context),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: PlatformInfo.isIOS
                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildContextMenuItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color color,
    required List<AdaptiveContextMenuAction> actions,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: AdaptiveContextMenu(
        actions: actions,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? (PlatformInfo.isIOS
                      ? CupertinoColors.darkBackgroundGray
                      : Colors.grey[850])
                : (PlatformInfo.isIOS ? CupertinoColors.white : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? (PlatformInfo.isIOS
                        ? CupertinoColors.systemGrey4
                        : Colors.grey[700]!)
                  : (PlatformInfo.isIOS
                        ? CupertinoColors.separator
                        : Colors.grey[300]!),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.square_on_square
                      : Icons.insert_drive_file,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? (PlatformInfo.isIOS
                                  ? CupertinoColors.white
                                  : Colors.white)
                            : (PlatformInfo.isIOS
                                  ? CupertinoColors.black
                                  : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? (PlatformInfo.isIOS
                                  ? CupertinoColors.systemGrey
                                  : Colors.grey[400])
                            : (PlatformInfo.isIOS
                                  ? CupertinoColors.systemGrey2
                                  : Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.ellipsis_vertical
                    : Icons.more_vert,
                color: CupertinoColors.systemGrey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? (PlatformInfo.isIOS
                  ? CupertinoColors.darkBackgroundGray
                  : Colors.grey[850])
            : (PlatformInfo.isIOS
                  ? CupertinoColors.systemGrey6
                  : Colors.grey[200]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.info_circle_fill
                    : Icons.info,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue
                    : Colors.blue,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'How to use',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? (PlatformInfo.isIOS
                            ? CupertinoColors.white
                            : Colors.white)
                      : (PlatformInfo.isIOS
                            ? CupertinoColors.black
                            : Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Long press on any card above to show the context menu with available actions.',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? (PlatformInfo.isIOS
                        ? CupertinoColors.systemGrey
                        : Colors.grey[400])
                  : (PlatformInfo.isIOS
                        ? CupertinoColors.systemGrey2
                        : Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.success,
    );
  }
}
