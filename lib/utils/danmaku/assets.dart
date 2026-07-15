
// lib/utils/danmaku/assets.dart


/// 启动外部播放器时用于加载弹幕的临时文件及渲染参数.
///
/// [assPath] 指向导出的 ASS 弹幕字幕; [luaPath] 指向供 mpv/mpv.net 将
/// 弹幕轨设为次字幕的脚本. 并非所有播放器都会使用其中的全部文件.
class DanmakuLaunchAssets {

  final String assPath; // 临时 ASS 弹幕字幕文件路径
  final String luaPath; // 临时 mpv Lua 脚本文件路径
  final double opacity; // 生成 ASS 时采用的弹幕不透明度

  /// 创建一组已生成的弹幕启动产物.
  const DanmakuLaunchAssets({
    required this.assPath,
    required this.luaPath,
    required this.opacity,
  });
}
