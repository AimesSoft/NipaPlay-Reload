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

/// 连接地址最近一次连通性检测的结果。
enum LibraryManagementAddressStatus { unknown, reachable, unreachable }

/// 库管理卡片中的一行连接地址（内网/公网各占一行）。
class LibraryManagementAddressLine {
  const LibraryManagementAddressLine({
    required this.label,
    required this.address,
    required this.status,
  });

  /// 地址角色，如「内网」「公网」。
  final String label;

  /// 地址文本。
  final String address;

  /// 该地址最近一次连通性检测结果。
  final LibraryManagementAddressStatus status;
}

/// 连通性检测结果对应的短文本；[LibraryManagementAddressStatus.unknown] 返回空串。
String libraryManagementAddressStatusText(
  LibraryManagementAddressStatus status,
) =>
    switch (status) {
      LibraryManagementAddressStatus.unknown => '',
      LibraryManagementAddressStatus.reachable => '可达',
      LibraryManagementAddressStatus.unreachable => '不可用',
    };

class UnifiedLibraryManagementItem {
  const UnifiedLibraryManagementItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.status,
    this.matchSubtitle,
    this.addressLines,
    this.actions = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String? status;
  /// 多地址连接的内网/公网明细（各占一行并附带最近一次连通性）。
  /// 非空时优先于 [subtitle] 渲染。
  final List<LibraryManagementAddressLine>? addressLines;
  /// 匹配信息，如 "CLANNAD AFTER STORY - 第5话"，仅在视频文件已匹配时显示
  final String? matchSubtitle;
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
