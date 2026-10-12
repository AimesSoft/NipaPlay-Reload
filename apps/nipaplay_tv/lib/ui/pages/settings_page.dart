import 'package:flutter/material.dart';
import 'package:nipaplay_core/constants/settings_keys.dart';
import 'package:nipaplay_core/utils/network_settings.dart';

import 'package:nipaplay_core/utils/settings_storage.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../data/tv_recent_play_store.dart';
import 'package:nipaplay_ui_common/settings/unified_setting_content_type.dart';

import '../focusable_card.dart';

/// 设置页：TV 瓦片，覆盖 ui_common [UnifiedSettingContentType] 的分类，
/// 开关值经 core 的 [SettingsStorage] 持久化。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.entryFocusNode});

  /// 壳在切换到本页时把焦点交给这里的入口卡片。
  final FocusNode? entryFocusNode;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _toggles = <String, bool>{};
  double _danmakuArea = 0.5;
  bool _danmakuOn = true;
  String _upscaler = 'off';
  String _videoFit = 'auto';
  UnifiedSettingContentType _section = UnifiedSettingContentType.general;
  String _bangumiServer = NetworkSettings.bangumiDefaultServer;
  bool _bangumiCustom = false;

  static const _sections = [
    (UnifiedSettingContentType.general, '通用', Icons.tune),
    (UnifiedSettingContentType.player, '播放器', Icons.play_circle_outline),
    (UnifiedSettingContentType.danmaku, '弹幕', Icons.subtitles_outlined),
    (UnifiedSettingContentType.network, '网络', Icons.wifi),
    (UnifiedSettingContentType.storage, '存储', Icons.folder_outlined),
    (UnifiedSettingContentType.appearance, '外观', Icons.palette_outlined),
  ];

  static const _itemsBySection = {
    UnifiedSettingContentType.general: [
      ('tv.settings.autoPlayNext', '自动连播'),
      ('tv.settings.resumePlayback', '记忆播放进度'),
    ],
    UnifiedSettingContentType.player: [
      ('tv.settings.hardwareDecode', '硬件解码'),
      ('tv.settings.showControlsOnStart', '起播显示控件'),
    ],
    UnifiedSettingContentType.danmaku: [
      ('tv.settings.danmaku', '显示弹幕'),
      ('tv.settings.danmakuTop', '顶部弹幕'),
      ('tv.settings.danmakuBottom', '底部弹幕'),
    ],
    UnifiedSettingContentType.network: [
      ('tv.settings.proxy', '使用 HTTP 代理'),
    ],
    UnifiedSettingContentType.storage: [
      ('tv.settings.cacheDanmaku', '缓存弹幕'),
    ],
    UnifiedSettingContentType.appearance: [
      ('tv.settings.compactCards', '紧凑卡片'),
    ],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = <String, bool>{};
    for (final entry in _itemsBySection.entries) {
      for (final item in entry.value) {
        map[item.$1] =
            await SettingsStorage.loadBool(item.$1, defaultValue: true);
      }
    }
    final bangumi = await NetworkSettings.getBangumiServer();
    final area = await TvPlaybackPrefs.danmakuArea();
    final danmakuOn = await TvPlaybackPrefs.danmakuOn();
    final upscaler = await TvPlaybackPrefs.upscaler();
    final fit = await TvPlaybackPrefs.videoFit();
    if (mounted) {
      setState(() {
        _toggles.addAll(map);
        _danmakuArea = area;
        _danmakuOn = danmakuOn;
        _upscaler = upscaler;
        _videoFit = fit;
        _bangumiServer = bangumi;
        _bangumiCustom = NetworkSettings.isCustomBangumiServer(bangumi);
      });
    }
  }



  Future<void> _editBangumiMirror() async {
    final controller = TextEditingController(
      text: _bangumiCustom ? _bangumiServer : '',
    );
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2026),
        title: const Text('Bangumi 镜像 / API 服务器'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '留空使用官方 api.bgm.tv；填写镜像可加速访问。',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '镜像地址',
                  hintText: NetworkSettings.bangumiDefaultServer,
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('__reset__'),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;

    if (result == '__reset__' || result.trim().isEmpty) {
      await NetworkSettings.resetBangumiServer();
    } else {
      if (!NetworkSettings.isValidServerUrl(result)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('地址无效，请填写 http(s):// 开头的完整地址')),
          );
        }
        return;
      }
      await NetworkSettings.setBangumiServer(result);
    }
    final server = await NetworkSettings.getBangumiServer();
    if (!mounted) return;
    setState(() {
      _bangumiServer = server;
      _bangumiCustom = NetworkSettings.isCustomBangumiServer(server);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bangumi 服务器已更新：$server')),
      );
    }
  }

  /// 循环切换画面超分档位（artCNN 模型按需加载，首次会有卡顿）。
  Future<void> _cycleUpscaler() async {
    const modes = ['off', 'artCnnC4F16', 'artCnnC4F32', 'artCnnC4F16Ds'];
    final idx = modes.indexOf(_upscaler);
    setState(() => _upscaler = modes[(idx + 1) % modes.length]);
    await TvPlaybackPrefs.setUpscaler(_upscaler);
  }

  /// 循环切换播放画面比例。
  Future<void> _cycleVideoFit() async {
    const modes = ['auto', '16:9', '4:3'];
    final idx = modes.indexOf(_videoFit);
    setState(() => _videoFit = modes[(idx + 1) % modes.length]);
    await TvPlaybackPrefs.setVideoFit(_videoFit);
  }

  /// 通用「点击循环切换」设置卡。
  Widget _cycleCard({
    required IconData icon,
    required String title,
    required String value,
    required Future<void> Function() onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FocusableCard(
        onActivate: () => onTap(),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.bodyLarge),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF26C6DA)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  /// 滑块设置卡（弹幕占比）。
  Widget _sliderCard({
    required String title,
    required IconData icon,
    required double value,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FocusableCard(
        onActivate: () =>
            onChanged(value >= 0.9 ? 0.1 : (value + 0.1)),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.bodyLarge),
                      const Spacer(),
                      Text(label,
                          style: const TextStyle(
                              color: Color(0xFF26C6DA), fontSize: 15)),
                    ],
                  ),
                  Slider(
                    value: value,
                    min: 0.1,
                    max: 0.9,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(String key, bool value) async {
    await SettingsStorage.saveBool(key, value);
    if (mounted) setState(() => _toggles[key] = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _itemsBySection[_section] ?? const [];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tabSettings,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sections.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final s = _sections[i];
                final active = s.$1 == _section;
                return FocusableCard(
                  focusNode: i == 0 ? widget.entryFocusNode : null,
                  // 选中态常驻：切换分区时高光跟随（用户反馈的缺陷）
                  selected: active,
                  onActivate: () => setState(() => _section = s.$1),
                  borderRadius: 12,
                  accentColor: const Color(0xFF26C6DA),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.$3, size: 20),
                      const SizedBox(width: 8),
                      Text(s.$2,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                if (_section == UnifiedSettingContentType.player) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FocusableCard(
                      onActivate: () {},
                      child: Row(
                        children: [
                          const Icon(Icons.memory, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('播放内核',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge),
                                const SizedBox(height: 2),
                                Text('Erika（TV 版唯一内核，已为体积优化）',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white38)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _cycleCard(
                    icon: Icons.auto_fix_high,
                    title: '画面超分（Erika artCNN）',
                    value: _upscaler == 'off'
                        ? '关闭 · 最流畅'
                        : '$_upscaler · 首次开启需加载模型，可能卡顿数秒',
                    onTap: _cycleUpscaler,
                  ),
                  _cycleCard(
                    icon: Icons.aspect_ratio,
                    title: '播放画面比例',
                    value: _videoFit,
                    onTap: _cycleVideoFit,
                  ),
                ],
                if (_section == UnifiedSettingContentType.danmaku) ...[
                  _sliderCard(
                    title: '弹幕画面占比',
                    icon: Icons.subtitles_outlined,
                    value: _danmakuArea,
                    label: '${(_danmakuArea * 100).round()}%',
                    onChanged: (v) {
                      setState(() => _danmakuArea = v);
                      TvPlaybackPrefs.setDanmakuArea(v);
                    },
                  ),
                  _cycleCard(
                    icon: Icons.blur_circular,
                    title: '弹幕渲染引擎 / 显示',
                    value: _danmakuOn
                        ? '开 · TV 自建引擎（轨道分配 + 滚动绘制）'
                        : '关 · 播放页亦可用 D 键临时开关',
                    onTap: () async {
                      setState(() => _danmakuOn = !_danmakuOn);
                      await TvPlaybackPrefs.setDanmakuOn(_danmakuOn);
                    },
                  ),
                ],
                if (_section == UnifiedSettingContentType.network)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FocusableCard(
                      onActivate: _editBangumiMirror,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Bangumi 镜像 / API 服务器',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge),
                                const SizedBox(height: 2),
                                Text(
                                  _bangumiCustom
                                      ? '$_bangumiServer（自定义）'
                                      : '$_bangumiServer（默认）',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.white38),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 20),
                        ],
                      ),
                    ),
                  ),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FocusableCard(
                      onActivate: () =>
                          _toggle(item.$1, !(_toggles[item.$1] ?? true)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(item.$2,
                                style:
                                    Theme.of(context).textTheme.bodyLarge),
                          ),
                          Switch(
                            value: _toggles[item.$1] ?? true,
                            onChanged: (v) => _toggle(item.$1, v),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '分区契约: ui_common UnifiedSettingContentType · 存储: core SettingsStorage（示例键 ${SettingsKeys.appLanguageMode}）',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white24),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
