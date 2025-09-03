import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'blur_snackbar.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';

class JellyfinQualityMenu extends StatefulWidget {
  final VoidCallback onClose;

  const JellyfinQualityMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<JellyfinQualityMenu> createState() => _JellyfinQualityMenuState();
}

class _JellyfinQualityMenuState extends State<JellyfinQualityMenu> {
  JellyfinVideoQuality? _currentQuality;
  bool _isLoading = false;
  List<Map<String, dynamic>> _serverSubtitles = [];
  int? _selectedServerSubtitleIndex; // null 表示不指定
  bool _burnIn = false; // 转码时是否烧录字幕

  @override
  void initState() {
    super.initState();
    _loadCurrentQuality();
  }

  Future<void> _loadCurrentQuality() async {
    try {
      // 根据当前播放协议使用对应 provider，保证两端持久化与默认值独立
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (videoState.currentVideoPath != null && videoState.currentVideoPath!.startsWith('emby://')) {
        final embyProv = Provider.of<EmbyTranscodeProvider>(context, listen: false);
        await embyProv.initialize();
        setState(() {
          _currentQuality = embyProv.currentVideoQuality;
        });
      } else {
        final transcodeProvider = Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await transcodeProvider.initialize();
        setState(() {
          _currentQuality = transcodeProvider.currentVideoQuality;
        });
      }

      // 读取当前播放的 jellyfin:// 或 emby:// itemId 并获取服务器字幕列表
      final vp = Provider.of<VideoPlayerState>(context, listen: false);
      final path = vp.currentVideoPath;
      if (path != null && path.startsWith('jellyfin://')) {
        final itemId = path.replaceFirst('jellyfin://', '');
        final tracks = await JellyfinService.instance.getSubtitleTracks(itemId);
        setState(() {
          _serverSubtitles = tracks;
          final def = tracks.firstWhere(
            (t) => (t['isDefault'] == true),
            orElse: () => {},
          );
          _selectedServerSubtitleIndex = def.isEmpty ? null : def['index'] as int?;
        });
      } else if (path != null && path.startsWith('emby://')) {
        final itemId = path.replaceFirst('emby://', '');
        final tracks = await EmbyService.instance.getSubtitleTracks(itemId);
        setState(() {
          _serverSubtitles = tracks;
          // 预选默认字幕（如果存在）
          final def = tracks.firstWhere(
            (t) => (t['isDefault'] == true),
            orElse: () => {},
          );
          _selectedServerSubtitleIndex = def.isEmpty ? null : def['index'] as int?;
        });
      }
    } catch (e) {
      debugPrint('加载当前转码质量失败: $e');
      setState(() {
        _currentQuality = JellyfinVideoQuality.bandwidth5m; // 默认值
      });
    }
  }

  void _changeQuality(JellyfinVideoQuality quality) {
    if (_currentQuality == quality) return;
    
    // 仅更新本地状态，不直接重载播放器
    setState(() {
      _currentQuality = quality;
    });
  }

  Future<void> _applySelection() async {
    if (_currentQuality == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 先保存默认清晰度设置
      // 根据当前播放协议选择对应的 provider（保证两者持久化独立且行为一致）
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (videoState.currentVideoPath != null && videoState.currentVideoPath!.startsWith('emby://')) {
        final embyProv = Provider.of<EmbyTranscodeProvider>(context, listen: false);
        await embyProv.initialize();
        await embyProv.setDefaultVideoQuality(_currentQuality!);
        
        // 当选择非原画质量时，自动启用转码
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await embyProv.setTranscodeEnabled(true);
        }
      } else {
        final transcodeProvider = Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await transcodeProvider.setDefaultVideoQuality(_currentQuality!);
        
        // 当选择非原画质量时，自动启用转码
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await transcodeProvider.setTranscodeEnabled(true);
        }
      }
      
      // 然后重载播放器
      final vp = Provider.of<VideoPlayerState>(context, listen: false);
      final path = vp.currentVideoPath;
      if (path != null && path.startsWith('jellyfin://')) {
        await vp.reloadCurrentJellyfinStream(
          quality: _currentQuality!,
          serverSubtitleIndex: _selectedServerSubtitleIndex,
          burnInSubtitle: _burnIn,
        );
      } else if (path != null && path.startsWith('emby://')) {
        await vp.reloadCurrentEmbyStream(
          quality: _currentQuality!,
          serverSubtitleIndex: _selectedServerSubtitleIndex,
          burnInSubtitle: _burnIn,
        );
      }
      
      setState(() {
        _isLoading = false;
      });
      
      // 显示成功通知并关闭菜单
      if (mounted) {
        final qualityName = _getQualityDisplayName(_currentQuality!);
        String message = '已切换到$qualityName清晰度';
        
        // 添加字幕信息到通知
        if (_selectedServerSubtitleIndex != null) {
          final selectedSubtitle = _serverSubtitles.firstWhere(
            (s) => s['index'] == _selectedServerSubtitleIndex,
            orElse: () => <String, dynamic>{},
          );
          if (selectedSubtitle.isNotEmpty) {
            final subtitleName = selectedSubtitle['display'] as String? ?? 
                                selectedSubtitle['title']?.toString() ?? 
                                '字幕 ${selectedSubtitle['index']}';
            message += '\n字幕: $subtitleName';
            if (_burnIn) {
              message += ' (烧录)';
            }
          }
        }
        
        BlurSnackBar.show(context, message);
        widget.onClose();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('应用清晰度/字幕选择失败: $e');
      if (mounted) {
        BlurSnackBar.show(context, '设置失败: $e');
      }
    }
  }

  String _getQualityDisplayName(JellyfinVideoQuality quality) {
    switch (quality) {
      case JellyfinVideoQuality.auto:
        return '自动';
      case JellyfinVideoQuality.original:
        return '原画 (不转码)';
      case JellyfinVideoQuality.bandwidth40m:
        return '4K (40 Mbps)';
      case JellyfinVideoQuality.bandwidth20m:
        return '超清 (20 Mbps)';
      case JellyfinVideoQuality.bandwidth10m:
        return '全高清 (10 Mbps)';
      case JellyfinVideoQuality.bandwidth5m:
        return '高清 (5 Mbps)';
      case JellyfinVideoQuality.bandwidth2m:
        return '标清 (2 Mbps)';
      case JellyfinVideoQuality.bandwidth1m:
        return '省流 (1 Mbps)';
    }
  }

  String _getQualityDescription(JellyfinVideoQuality quality) {
    switch (quality) {
      case JellyfinVideoQuality.auto:
        return '让服务器根据网络情况自动选择';
      case JellyfinVideoQuality.original:
        return '直接播放原始文件，无转码';
      case JellyfinVideoQuality.bandwidth40m:
        return '超高清画质，需要高速网络';
      case JellyfinVideoQuality.bandwidth20m:
        return '1080p超清画质，网络要求较高';
      case JellyfinVideoQuality.bandwidth10m:
        return '1080p全高清画质，网络要求适中';
      case JellyfinVideoQuality.bandwidth5m:
        return '720p高清画质，流畅播放';
      case JellyfinVideoQuality.bandwidth2m:
        return '480p标清画质，省流量';
      case JellyfinVideoQuality.bandwidth1m:
        return '360p低清画质，最省流量';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseSettingsMenu(
      title: '清晰度设置',
      onClose: widget.onClose,
      extraButton: TextButton(
        onPressed: _applySelection,
        child: const Text('应用', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsHintText('选择视频播放质量'),
                  const SizedBox(height: 16),
                  ...JellyfinVideoQuality.values.map((quality) {
                    final isSelected = _currentQuality == quality;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _changeQuality(quality),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected 
                                    ? Colors.blue
                                    : Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.blue : Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getQualityDisplayName(quality),
                                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                          color: isSelected ? Colors.blue : Colors.white,
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _getQualityDescription(quality),
                                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                          color: isSelected ? Colors.blue.withOpacity(0.8) : Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 16),
                  const SettingsHintText('服务器字幕（用于转码时选择/烧录）'),
                  const SizedBox(height: 8),
                  // “不指定字幕”选项
                  _buildSubtitleOption(
                    title: '不指定字幕（沿用播放器选择或无）',
                    selected: _selectedServerSubtitleIndex == null,
                    onTap: () => setState(() => _selectedServerSubtitleIndex = null),
                  ),
                  const SizedBox(height: 6),
                  ..._serverSubtitles.map((t) => _buildSubtitleOption(
                        title: (t['display'] as String?) ?? (t['title']?.toString() ?? '字幕 ${t['index']}'),
                        selected: _selectedServerSubtitleIndex == t['index'],
                        onTap: () => setState(() => _selectedServerSubtitleIndex = t['index'] as int),
                      )),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('转码时烧录字幕', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Switch(
                        value: _burnIn,
                        onChanged: (v) => setState(() => _burnIn = v),
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtitleOption({required String title, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.blue : Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? Colors.blue : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: selected ? Colors.blue : Colors.white,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
