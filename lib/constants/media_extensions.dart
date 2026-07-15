/// 媒体文件扩展名常量
/// 集中定义，供 local_media_share_service 和 remote_subtitle_service 共享使用
library;

/// 支持的字幕扩展名
const Set<String> subtitleExtensions = {
  '.ass',
  '.ssa',
  '.srt',
  '.sub',
  '.sup',
};

/// 支持的外挂音轨扩展名
const Set<String> audioExtensions = {
  '.mka',
  '.aac',
  '.flac',
  '.wav',
  '.mp3',
};

/// 支持的字体文件扩展名
const Set<String> fontExtensions = {
  '.ttf',
  '.otf',
  '.ttc',
};


/// 外部播放器类型,
/// 决定弹幕 ASS 字幕的注入参数
enum ExternalPlayerType {
  mpv,
  mpvNet,
  potPlayer,
  vlc,
  generic,
}
