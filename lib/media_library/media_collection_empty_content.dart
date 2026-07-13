import 'package:nipaplay/app/unified_media_library_sections.dart';

enum MediaCollectionEmptyIcon { library }

class MediaCollectionEmptyContent {
  const MediaCollectionEmptyContent({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final MediaCollectionEmptyIcon icon;
  final String title;
  final String subtitle;
}

MediaCollectionEmptyContent mediaCollectionEmptyContent(
  UnifiedMediaLibrarySource source, {
  required String sourceLabel,
}) {
  final subtitle = switch (source) {
    UnifiedMediaLibrarySource.local => '观看或扫描识别后的动画会显示在这里。',
    UnifiedMediaLibrarySource.webdav => '完成 WebDAV 刮削后，动画会显示在这里。',
    UnifiedMediaLibrarySource.smb => '完成 SMB 刮削后，动画会显示在这里。',
  };

  return MediaCollectionEmptyContent(
    icon: MediaCollectionEmptyIcon.library,
    title: '$sourceLabel为空',
    subtitle: subtitle,
  );
}
