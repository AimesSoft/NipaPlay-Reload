import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';
import 'package:nipaplay_ui_common/media_library/unified_library_management_model.dart';

import '../focusable_card.dart';

/// 媒体库页：消费 ui_common 的库管理契约（视图模式 / 图标枚举 / 空态模型）。
/// 数据源（观看历史/WebDAV/媒体服务器）在阶段四接入。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryManagementViewMode _viewMode = LibraryManagementViewMode.icons;

  IconData _iconOf(LibraryManagementIcon icon) => switch (icon) {
        LibraryManagementIcon.folder => Icons.folder_outlined,
        LibraryManagementIcon.video => Icons.smart_display_outlined,
        LibraryManagementIcon.file => Icons.insert_drive_file_outlined,
        LibraryManagementIcon.cloud => Icons.cloud_outlined,
        LibraryManagementIcon.server => Icons.dns_outlined,
        LibraryManagementIcon.browse => Icons.travel_explore,
        LibraryManagementIcon.refresh => Icons.refresh,
        LibraryManagementIcon.scan => Icons.radar,
        LibraryManagementIcon.info => Icons.info_outline,
        LibraryManagementIcon.subtitles => Icons.subtitles_outlined,
        LibraryManagementIcon.edit => Icons.edit_outlined,
        LibraryManagementIcon.delete => Icons.delete_outline,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final empty = LibraryManagementEmptyContent(
      title: l10n.tabMediaLibrary,
      subtitle: 'WebDAV / 媒体服务器 / 本地扫描数据源将在阶段四接入',
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tabMediaLibrary,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < LibraryManagementViewMode.values.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: FocusableCard(
                    autofocus: i == 0,
                    onActivate: () => setState(() =>
                        _viewMode = LibraryManagementViewMode.values[i]),
                    borderRadius: 12,
                    accentColor: _viewMode == LibraryManagementViewMode.values[i]
                        ? const Color(0xFF26C6DA)
                        : Colors.white24,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _viewMode == LibraryManagementViewMode.values[i]
                              ? Icons.toggle_on
                              : Icons.toggle_off,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                            _viewMode == LibraryManagementViewMode.values[i]
                                ? '当前: ${LibraryManagementViewMode.values[i].name}'
                                : LibraryManagementViewMode.values[i].name,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Icon(_iconOf(LibraryManagementIcon.server),
                    size: 72, color: Colors.white24),
                const SizedBox(height: 12),
                Text(empty.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white60)),
                const SizedBox(height: 6),
                Text(empty.subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
