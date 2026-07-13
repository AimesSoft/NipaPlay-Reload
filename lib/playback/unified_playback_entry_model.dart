import 'package:flutter/foundation.dart';

@immutable
class UnifiedPlaybackEntryContent {
  const UnifiedPlaybackEntryContent({
    required this.emptyTitle,
    required this.selectFileLabel,
    required this.selectFileDescription,
    required this.enterUrlLabel,
    required this.enterUrlDescription,
    required this.urlHelp,
    required this.urlPlaceholder,
    required this.oneTimeUserAgentLabel,
    required this.pasteLabel,
    required this.playUrlLabel,
    required this.processingLabel,
  });

  final String emptyTitle;
  final String selectFileLabel;
  final String selectFileDescription;
  final String enterUrlLabel;
  final String enterUrlDescription;
  final String urlHelp;
  final String urlPlaceholder;
  final String oneTimeUserAgentLabel;
  final String pasteLabel;
  final String playUrlLabel;
  final String processingLabel;
}

const UnifiedPlaybackEntryContent unifiedPlaybackEntryContent =
    UnifiedPlaybackEntryContent(
  emptyTitle: '诶？还没有在播放的视频！',
  selectFileLabel: '选择文件',
  selectFileDescription: '从本地文件、相册或文件管理器中打开视频',
  enterUrlLabel: '输入链接',
  enterUrlDescription: '粘贴 http/https 串流直链后直接播放',
  urlHelp: '支持 http/https 串流直链，建议使用 Media Kit 或 MDK 内核。',
  urlPlaceholder: 'https://example.com/video.mp4 或签名下载直链',
  oneTimeUserAgentLabel: '自定义 UA（仅一次）',
  pasteLabel: '粘贴',
  playUrlLabel: '播放链接',
  processingLabel: '处理中...',
);
