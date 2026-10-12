import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../focusable_card.dart';

/// 首页：焦点网格，展示内容分区（阶段三为壳，阶段四接入真实数据源）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = [
      (l10n.tabMediaLibrary, Icons.smart_display_outlined,
          '继续观看 / 媒体服务器（阶段四接入）'),
      (l10n.tabDanmakuConsole, Icons.subtitles_outlined,
          '弹幕引擎已在 core：解析 / 时间轴 / 碰撞（阶段四接入渲染）'),
      (l10n.settingsBasicSection, Icons.tune,
          'NipaPlayer 统一播放器接口（core/player/nipa_player.dart）'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tabHome,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FocusableCard(
                onActivate: () {},
                child: Row(
                  children: [
                    Icon(s.$2, size: 30, color: const Color(0xFF26C6DA)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(s.$3,
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
            ),
        ],
      ),
    );
  }
}
