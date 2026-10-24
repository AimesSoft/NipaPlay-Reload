import 'package:flutter/foundation.dart' show immutable;

import '../../chat/delegation_message.dart';
import '../../ui_data/ui_data.dart';
import '../data/discover.dart';

/// What the interface adds to what you said (the work you asked from, what
/// played under the conversation, the files you dropped in), and how it is
/// taken off again when the message is shown.
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

  /// [text] said over a video: the agent gets what plays and where, as
  /// [now] read it the moment it was said.
  static String watching(String text, Watching now) {
    final known = now.known;
    final facts = [
      if (known != null) '作品 ID：${known.workId}',
      if (known?.episodeId case final episode?) '剧集 ID：$episode',
      now.duration > Duration.zero
          ? '位置 ${_clock(now.position)} / ${_clock(now.duration)}'
          : '位置 ${_clock(now.position)}',
      if (now.paused) '暂停中',
    ];
    return '$text\n\n$_mark 这句话是在播放${now.named}${known?.episode ?? ''}'
        '时说的（${facts.join('；')}）。';
  }

  /// What played when [text] was said, as [Watching.named] names it.
  static String? watched(String text) {
    final at = text.indexOf(_mark);
    if (at < 0) return null;
    return RegExp(r'这句话是在播放(《.+?》|「.+」(?=时说的（))')
        .firstMatch(text.substring(at))
        ?.group(1);
  }

  /// `12:34`, or `1:02:03` past an hour, as the player's timeline shows it.
  static String _clock(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

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
    if (text.startsWith(delegationMarker)) return showDelegation(text);
    final marks = [text.indexOf(_mark), text.indexOf(_files), text.indexOf(_memory)]
        .where((i) => i >= 0);
    final at = marks.isEmpty ? -1 : marks.reduce((a, b) => a < b ? a : b);
    return (at < 0 ? text : text.substring(0, at)).trim();
  }

  /// A turn NipaPlay started on Nipa's behalf, not something you said.
  static bool isFollowup(String text) => text.startsWith(_followup);
}

/// What plays under the conversation the moment something is said: the
/// file, what the library knows it as (null: nothing), where the video is.
@immutable
final class Watching {
  const Watching({
    required this.path,
    this.known,
    required this.position,
    this.duration = Duration.zero,
    this.paused = false,
  });

  final String path;
  final UiNowPlaying? known;
  final Duration position;

  /// Zero while not known.
  final Duration duration;
  final bool paused;

  /// 《寻龙记》; 「file.mkv」 for a file the library does not know.
  String get named => nameOf(path, known);

  static String nameOf(String path, UiNowPlaying? known) =>
      known != null ? '《${known.work}》' : '「${fileName(path)}」';

  /// The file's name, from a path or a source's address (without its
  /// query, which may carry a key).
  static String fileName(String path) {
    final address = path.contains('://');
    final uri = address ? Uri.tryParse(path) : null;
    final parts = uri != null
        ? uri.pathSegments
        : (address ? path.split(RegExp(r'[?#]')).first : path)
            .split(RegExp(r'[/\\]'));
    return parts.where((p) => p.isNotEmpty).lastOrNull ?? uri?.host ?? path;
  }
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
