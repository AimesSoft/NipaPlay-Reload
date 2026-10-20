import '../../ui_data/ui_data.dart';
import '../data/discover.dart';

/// What the interface adds to what you said (the work you asked from, the
/// files you dropped in), and how it is taken off again when the message is
/// shown.
abstract final class ChatContext {
  static const _mark = '[NipaPlay 界面]';
  static const _files = '[NipaPlay 附件]';
  static const _followup = '[NipaPlay followup';
  static const _memory = '[NipaPlay 记忆]';

  /// [text] asked from [work]'s page: the agent gets the work along.
  static String about(String text, UiWork work) => Found.isFound(work)
      ? '$text\n\n$_mark 这句话是在《${work.title}》的页面上问的'
          '（还不在片库里；${Found.describe(work)}）。'
      : '$text\n\n$_mark 这句话是在《${work.title}》的页面上问的'
          '（作品 ID：${work.workId}）。';

  /// [text] with the files you dropped in: the agent gets their paths.
  static String withFiles(String text, List<String> paths) => paths.isEmpty
      ? text
      : '$text\n\n$_files 用户拖进来的文件：\n'
          '${paths.map((p) => '- $p（${DroppedFile.kindOf(p)}）').join('\n')}';

  /// The files [text] carries, as [withFiles] wrote them.
  static List<String> files(String text) {
    final at = text.indexOf(_files);
    if (at < 0) return const [];
    final paths = <String>[];
    for (final line in text.substring(at).split('\n').skip(1)) {
      if (!line.startsWith('- ')) break;
      paths.add(line.substring(2).replaceFirst(RegExp(r'（[^（]*）$'), ''));
    }
    return paths;
  }

  /// The title of the work [text] was asked about, if any.
  static String? aboutTitle(String text) {
    final at = text.indexOf(_mark);
    if (at < 0) return null;
    return RegExp(r'《(.+?)》的页面上问的').firstMatch(text.substring(at))?.group(1);
  }

  /// What you said, without what the interface added.
  static String strip(String text) {
    final marks = [text.indexOf(_mark), text.indexOf(_files), text.indexOf(_memory)]
        .where((i) => i >= 0);
    final at = marks.isEmpty ? -1 : marks.reduce((a, b) => a < b ? a : b);
    return (at < 0 ? text : text.substring(0, at)).trim();
  }

  /// A turn NipaPlay started on Nipa's behalf, not something you said.
  static bool isFollowup(String text) => text.startsWith(_followup);
}

/// A file dropped into the conversation.
abstract final class DroppedFile {
  static const _images = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff'
  };
  static const _videos = {
    'mkv', 'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'm2ts',
    'rmvb', 'mpg', 'mpeg'
  };
  static const _subtitles = {'ass', 'ssa', 'srt', 'vtt', 'sub'};

  static String _ext(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static bool isImage(String path) => _images.contains(_ext(path));

  /// “图片”, “视频”, “种子”, “字幕”, “文件”.
  static String kindOf(String path) {
    final ext = _ext(path);
    if (_images.contains(ext)) return '图片';
    if (_videos.contains(ext)) return '视频';
    if (ext == 'torrent') return '种子';
    if (_subtitles.contains(ext)) return '字幕';
    return '文件';
  }

  static String name(String path) {
    final parts = path.split('/')..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}
