import 'package:nipa_harness/nipa_harness.dart';

JsonMap settingPresentation(String key, JsonMap schema) => {
  if (key == 'danmaku.fontSize') 'valueNames': {'0': '设备默认'},
  if (schema['enum'] case final List values)
    'enumNames': [for (final value in values) _label(key, value)],
  if (_pathFormats[key] case final String format) 'format': format,
};

const _pathFormats = {
  'next.harnessPath': 'directory',
  'download.directory': 'directory',
  'player.screenshotDirectory': 'directory',
  'subtitle.fontDir': 'directory',
  'danmaku.fontFilePath': 'file',
  'player.externalPath': 'file',
  'appearance.customBackgroundPath': 'file',
};

String _label(String key, Object? value) {
  final text = value is double && value == value.roundToDouble()
      ? '${value.toInt()}' : '$value';
  return _byKey[key]?['$value'] ?? _byKey[key]?[text] ?? _common[text] ?? text;
}

const _byKey = <String, Map<String, String>>{
    'network.dandanplayMode': {'auto': '自动', 'hongKong': '香港', 'china': '国内', 'custom': '自定义'},
    'appearance.classicLibrarySection': {'local_library': '本地', 'local_management': '本地管理', 'webdav_library': 'WebDAV', 'webdav_management': 'WebDAV 管理', 'smb_library': 'SMB', 'smb_management': 'SMB 管理', 'shared_library': '共享', 'shared_management': '共享管理', 'dandanplay': '弹弹play', 'jellyfin': 'Jellyfin', 'emby': 'Emby'},
    'appearance.animeDetailDisplayMode': {'simple': '简洁', 'vivid': '生动'},
    'player.anime4kProfile': {'off': '关闭', 'lite': '轻量', 'standard': '标准', 'high': '高'},
    'player.crtProfile': {'off': '关闭', 'lite': '轻量', 'standard': '标准', 'high': '高'},
    'player.androidAudioOutput': {'opensles': 'OpenSL ES', 'audiotrack': 'AudioTrack'},
    'player.erikaAndroidOutputMode': {'sdr': 'SDR', 'extendedLinearHdr': '扩展线性 HDR'},
    'player.playbackEndAction': {
      'autoNext': '下一集',
      'loop': '重播',
      'pause': '暂停',
      'exitPlayer': '退出播放'
    },
    'player.kernel': {
      'mdk': 'MDK',
      'videoPlayer': '系统',
      'mediaKit': 'mpv',
      'erika': 'Erika'
    },
    'player.erikaUpscalerMode': {
      'off': '关闭',
      'erikaArtCnnC4F16': '标准',
      'erikaArtCnnC4F32': '高',
      'erikaArtCnnC4F16Ds': '省电'
    },
    'player.videoAspectMode': {
      'contain': '完整',
      'cover': '铺满',
      'fill': '拉伸',
      'fitWidth': '适应宽度',
      'fitHeight': '适应高度',
      'none': '原始',
      'scaleDown': '缩小以适应',
      'ratio16x9': '16:9',
      'ratio4x3': '4:3'
    },
    'player.hwdecMode': {'no': '关闭', 'auto': '自动', 'autoSafe': '自动（稳妥）'},
    'player.screenshotSaveTarget': {
      'ask': '每次询问',
      'photos': '照片',
      'file': '文件夹'
    },
    'player.screenshotQuality': {
      'standard': '标准',
      'high': '高',
      'ultra': '超高',
      'max': '最高'
    },
    'player.screenshotFormat': {'jpeg': 'JPEG', 'png': 'PNG'},
    'player.externalType': {
      'unset': '未选择',
      'mpv': 'mpv',
      'mpvNet': 'mpv.net',
      'potPlayer': 'PotPlayer',
      'vlc': 'VLC',
      'generic': '其他'
    },
    'danmaku.autoLoadStrategy': {
      'remoteAndLocal': '在线和本地',
      'remote': '在线',
      'local': '本地'
    },
    'danmaku.outlineStyle': {'none': '无', 'stroke': '描边', 'uniform': '均匀'},
    'danmaku.shadowStyle': {
      'none': '无',
      'soft': '柔和',
      'medium': '中等',
      'strong': '浓重'
    },
    'danmaku.outlineWidth': {'0.0': '无', '1.0': '细', '2.0': '粗'},
    'danmaku.spoilerAiApiFormat': {'openai': 'OpenAI', 'gemini': 'Gemini'},
    'subtitle.alignX': {'left': '靠左', 'center': '居中', 'right': '靠右'},
    'subtitle.alignY': {'top': '顶部', 'center': '居中', 'bottom': '底部'},
    'subtitle.overrideMode': {
      'auto': '自动',
      'none': '不接管',
      'scale': '仅大小',
      'force': '完全接管'
    },
    'appearance.accentColor': {'rose': '玫瑰', 'blue': '蓝', 'green': '绿'},
    'appearance.folderNameDisplayMode': {'ellipsis': '单行', 'multiline': '多行'},
    'appearance.windowDisplayMode': {'windowed': '窗口', 'filledScreen': '铺满屏幕'},
    'appearance.backgroundRenderMode': {'opacity': '透明度', 'soft_light': '柔光'},
    'language.mode': {
      'auto': '跟随系统',
      'simplified': '简体中文',
      'traditional': '繁體中文',
      'english': 'English'
    },
    'general.desktopExitBehavior': {
      'askEveryTime': '每次询问',
      'minimizeToTrayOrTaskbar': '最小化',
      'closePlayer': '退出'
    },
    'general.startupWindowState': {'windowed': '窗口', 'maximized': '最大化'},
    'general.defaultHomeTab': {
      'home': '主页',
      'video': '视频',
      'webdav': 'WebDAV',
      'media_library': '媒体库',
      'torrent': '下载',
      'account': '账户'
    },
    'webdavQuick.sortPreset': {
      'default': '默认',
      'name_asc': '名称 ↑',
      'name_desc': '名称 ↓',
      'modified_desc': '最近修改',
      'modified_asc': '最早修改',
      'size_desc': '最大',
      'size_asc': '最小'
    },
    'webdavQuick.searchScope': {
      'current_directory': '当前目录',
      'current_with_depth': '当前及子目录',
      'global': '全部'
    },
    'appearance.quarterlyReviewSort': {
      'airDate': '播出时间',
      'commentNewest': '最新评论',
      'commentOldest': '最早评论',
      'ratingHigh': '评分高',
      'ratingLow': '评分低'
    },
    'appearance.blurPower': {'0': '无', '0.0': '无'},
  };

const _common = {
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
    'auto': '自动',
    'none': '无',
    'off': '关闭',
    'on': '开启',
    'center': '居中',
    'topLeft': '左上',
    'topRight': '右上',
    'bottomLeft': '左下',
    'bottomRight': '右下',
  };
