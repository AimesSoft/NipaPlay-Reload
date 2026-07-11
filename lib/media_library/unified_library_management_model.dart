import 'package:flutter/widgets.dart';

enum LibraryManagementViewMode { icons, list }

enum LibraryManagementIcon {
  folder,
  video,
  file,
  cloud,
  server,
  browse,
  refresh,
  scan,
  info,
  subtitles,
  edit,
  delete,
}

class UnifiedLibraryManagementAction {
  const UnifiedLibraryManagementAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final LibraryManagementIcon icon;
  final VoidCallback? onPressed;
  final bool destructive;
}

class UnifiedLibraryManagementItem {
  const UnifiedLibraryManagementItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.status,
    this.actions = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String? status;
  final LibraryManagementIcon icon;
  final VoidCallback? onOpen;
  final List<UnifiedLibraryManagementAction> actions;
}

class LibraryManagementEmptyContent {
  const LibraryManagementEmptyContent({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}
