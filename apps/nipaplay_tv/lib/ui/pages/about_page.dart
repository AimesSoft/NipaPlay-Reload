import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';
import 'package:nipaplay_ui_common/settings/about_settings_data.dart';

import '../focusable_card.dart';

/// 关于页：复用 ui_common 的 AboutSettingsData 契约与 core 的致谢常量。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.entryFocusNode});

  /// 壳在切换到本页时把焦点交给这里的入口卡片。
  final FocusNode? entryFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.about, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          FocusableCard(
            focusNode: entryFocusNode,
            onActivate: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appTitle,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF26C6DA),
                        )),
                const SizedBox(height: 6),
                Text('TV 壳 0.1.0 · 阶段三（core + ui_common 架构验证版）',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white54)),
                const SizedBox(height: 8),
                Text(AboutSettingsData.repositoryUrl,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white38)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.acknowledgements,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white60)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final name in AboutSettingsData.sponsorNames.take(12))
                FocusableCard(
                  onActivate: () {},
                  borderRadius: 10,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${l10n.aboutStoryPrefix}咪啪～☆${l10n.aboutStorySuffix}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
