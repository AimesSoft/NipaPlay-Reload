// erika_upscaler_group_tile.dart
// Erika 超分档位选择：分组折叠（方案 A，"调整时钟"式层级）。
// 档位多达 20+，垂直下拉既挤又容易被宽度截断；改为设置页内
// 可展开区块：收起态与其他设置卡片完全一致（AdaptiveSettingsTile.button，
// 显示当前档位），点击展开后按组折叠展示：
// - 组标题小灰字：基础 / ArtCNN 神经网络超分 / Anime4K / 其他后端
// - 每档主名（label）完整展示不省略，次行小灰描述（description）
// - 当前档位打勾；点击即应用并收起

import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class _UpscalerModeGroup {
  const _UpscalerModeGroup(this.title, this.modes);
  final String title;
  final List<PlayerUpscalerMode> modes;
}

List<_UpscalerModeGroup> _groupModes(List<PlayerUpscalerMode> modes) {
  final off =
      modes.where((m) => m == PlayerUpscalerMode.off).toList(growable: false);
  final rest = modes.where((m) => m != PlayerUpscalerMode.off).toList();
  final artCnn =
      rest.where((m) => m.label.startsWith('ArtCNN')).toList(growable: false);
  final anime4k =
      rest.where((m) => m.label.startsWith('Anime4K')).toList(growable: false);
  final others = rest
      .where((m) =>
          !m.label.startsWith('ArtCNN') && !m.label.startsWith('Anime4K'))
      .toList(growable: false);
  return [
    if (off.isNotEmpty) _UpscalerModeGroup('基础', off),
    if (artCnn.isNotEmpty) _UpscalerModeGroup('ArtCNN 神经网络超分', artCnn),
    if (anime4k.isNotEmpty) _UpscalerModeGroup('Anime4K', anime4k),
    if (others.isNotEmpty) _UpscalerModeGroup('其他后端', others),
  ];
}

class ErikaUpscalerGroupTile extends StatefulWidget {
  const ErikaUpscalerGroupTile({
    super.key,
    required this.currentMode,
    required this.availableModes,
    required this.onModeSelected,
  });

  final PlayerUpscalerMode currentMode;
  final List<PlayerUpscalerMode> availableModes;

  /// 应用档位（异步，异常由调用方决定提示方式）；完成后自动收起。
  final Future<void> Function(PlayerUpscalerMode mode) onModeSelected;

  @override
  State<ErikaUpscalerGroupTile> createState() => _ErikaUpscalerGroupTileState();
}

class _ErikaUpscalerGroupTileState extends State<ErikaUpscalerGroupTile> {
  bool _expanded = false;
  bool _applying = false;
  int? _pendingIndex;

  void _toggle() => setState(() => _expanded = !_expanded);

  Future<void> _select(PlayerUpscalerMode mode, int flatIndex) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _pendingIndex = flatIndex;
    });
    try {
      await widget.onModeSelected(mode);
      if (mounted) setState(() => _expanded = false);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _pendingIndex = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final Color groupTitleColor =
        isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black45;
    final Color secondaryText =
        isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;

    final groups = _groupModes(widget.availableModes);
    // 每次重建重置行序号，保证 applying 转圈定位正确。
    _flatCounter = 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveSettingsTile.button(
          title: 'Erika 超分辨率',
          subtitle: widget.currentMode == PlayerUpscalerMode.off
              ? '关闭 · 点击选择档位'
              : '当前：${widget.currentMode.label}',
          icon: Ionicons.sparkles_outline,
          trailingIcon:
              _expanded ? Ionicons.chevron_up : Ionicons.chevron_down,
          onTap: _toggle,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var g = 0; g < groups.length; g++) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                          child: Text(
                            groups[g].title,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: groupTitleColor),
                          ),
                        ),
                        for (var i = 0; i < groups[g].modes.length; i++)
                          _buildModeRow(
                            groups[g].modes[i],
                            secondaryText: secondaryText,
                          ),
                        if (g != groups.length - 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Divider(
                                height: 1,
                                thickness: 0.5,
                                color: dividerColor),
                          ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 简单递增序号用于应用中转圈：行扁平索引在闭包里按组累加。
  int _flatCounter = 0;

  Widget _buildModeRow(
    PlayerUpscalerMode mode, {
    required Color secondaryText,
  }) {
    final flatIndex = _flatCounter++;
    final theme = Theme.of(context);
    final selected = mode == widget.currentMode;
    final applying = _applying && _pendingIndex == flatIndex;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      enabled: !_applying,
      // 主名完整展示：卡片全宽 + 允许换行，绝不省略。
      title: Text(
        mode.label,
        softWrap: true,
        maxLines: 2,
        overflow: TextOverflow.visible,
      ),
      // 次行小灰字：模型定位与开销说明。
      subtitle: mode.description.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                mode.description,
                softWrap: true,
                maxLines: 3,
                overflow: TextOverflow.visible,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: secondaryText),
              ),
            ),
      trailing: applying
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (selected
              ? Icon(Ionicons.checkmark, color: AppAccentColors.current)
              : null),
      onTap: () => _select(mode, flatIndex),
    );
  }
}
