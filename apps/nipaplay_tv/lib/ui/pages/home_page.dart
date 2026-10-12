import 'package:flutter/material.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../danmaku/tv_danmaku_source.dart';
import '../focusable_card.dart';
import 'player_page.dart';

/// 首页：可聚焦入口网格。首个入口进入播放页（本地演示视频 + 弹幕）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 内置示例弹幕（B 站 XML 协议），交给 core 解析。
  static const _demoXml = '''
<i>
  <d p="1.2,1,25,16777215,0,0,user1,d1">NipaPlay TV 启动成功</d>
  <d p="2.0,1,25,16711680,0,0,user2,d2">弹幕来自 core 的 XML 解析</d>
  <d p="2.8,5,25,65280,0,0,user3,d3">顶部弹幕 · 十英尺可读</d>
  <d p="3.6,1,25,16776960,0,0,user4,d4">D-pad 左右可快进快退</d>
  <d p="4.4,4,25,16711935,0,0,user5,d5">底部弹幕示例</d>
  <d p="5.2,1,25,16777215,0,0,user6,d6">core + ui_common 架构验证</d>
  <d p="6.4,1,25,16711935,0,0,user7,d7">咪啪～☆</d>
</i>
''';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tabHome,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          FocusableCard(
            autofocus: true,
            onActivate: () => _openDemo(context),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    size: 34, color: Color(0xFF26C6DA)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('播放演示视频',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('NipaPlayer 接口（core）+ video_player 内核（TV）+ 弹幕渲染',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FocusableCard(
            onActivate: () {},
            child: Row(
              children: [
                const Icon(Icons.subtitles_outlined,
                    size: 30, color: Color(0xFF26C6DA)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tabDanmakuConsole,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('解析与时间轴已在 core；渲染层为 TV 自建（轨道分配 + 滚动绘制）',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FocusableCard(
            onActivate: () {},
            child: Row(
              children: [
                const Icon(Icons.dns_outlined,
                    size: 30, color: Color(0xFF26C6DA)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('媒体服务器 / WebDAV',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('客户端与主机发现已在 core（webdav_service / lan_discovery）',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDemo(BuildContext context) async {
    final path = await demoFilePath();
    final items = TvDanmakuSource.parseBilibiliXml(_demoXml);
    if (!context.mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到演示视频，请先推送到应用目录')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvPlayerPage(
          source: MediaSource(uri: Uri.file(path).toString()),
          title: '演示视频',
          danmakuItems: items,
        ),
      ),
    );
  }
}
