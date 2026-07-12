enum MediaSourceCategory { local, mediaServer, fileShare }

enum MediaSourceIconKind {
  localFolder,
  nipaplay,
  jellyfin,
  dandanplay,
  emby,
  webdav,
  smb,
}

class MediaSourceOption {
  const MediaSourceOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.iconKind,
  });

  final String id;
  final String title;
  final String subtitle;
  final MediaSourceCategory category;
  final MediaSourceIconKind iconKind;
}

extension MediaSourceCategoryLabel on MediaSourceCategory {
  String get label => switch (this) {
        MediaSourceCategory.local => '本地媒体',
        MediaSourceCategory.mediaServer => '网络媒体服务器',
        MediaSourceCategory.fileShare => '网络文件共享',
      };
}

const mediaSourceOptions = <MediaSourceOption>[
  MediaSourceOption(
    id: 'local_folder',
    title: '本地文件夹',
    subtitle: '添加本地媒体文件夹',
    category: MediaSourceCategory.local,
    iconKind: MediaSourceIconKind.localFolder,
  ),
  MediaSourceOption(
    id: 'nipaplay',
    title: 'NipaPlay',
    subtitle: '局域网媒体共享',
    category: MediaSourceCategory.mediaServer,
    iconKind: MediaSourceIconKind.nipaplay,
  ),
  MediaSourceOption(
    id: 'jellyfin',
    title: 'Jellyfin',
    subtitle: '开源媒体服务器',
    category: MediaSourceCategory.mediaServer,
    iconKind: MediaSourceIconKind.jellyfin,
  ),
  MediaSourceOption(
    id: 'dandanplay',
    title: '弹弹play',
    subtitle: '弹幕番剧远程服务',
    category: MediaSourceCategory.mediaServer,
    iconKind: MediaSourceIconKind.dandanplay,
  ),
  MediaSourceOption(
    id: 'emby',
    title: 'Emby',
    subtitle: '功能丰富的媒体服务器',
    category: MediaSourceCategory.mediaServer,
    iconKind: MediaSourceIconKind.emby,
  ),
  MediaSourceOption(
    id: 'webdav',
    title: 'WebDAV',
    subtitle: '添加 WebDAV 服务器',
    category: MediaSourceCategory.fileShare,
    iconKind: MediaSourceIconKind.webdav,
  ),
  MediaSourceOption(
    id: 'smb',
    title: 'SMB',
    subtitle: '添加 SMB 共享',
    category: MediaSourceCategory.fileShare,
    iconKind: MediaSourceIconKind.smb,
  ),
];
