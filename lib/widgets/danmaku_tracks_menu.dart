import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart';
import '../services/file_picker_service.dart';
import '../widgets/blur_snackbar.dart';
import '../widgets/blur_button.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';

class DanmakuTracksMenu extends StatefulWidget {
  final VoidCallback onClose;

  const DanmakuTracksMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<DanmakuTracksMenu> createState() => _DanmakuTracksMenuState();
}

class _DanmakuTracksMenuState extends State<DanmakuTracksMenu> {
  bool _isLoadingLocalDanmaku = false;

    // 加载本地JSON弹幕文件
  Future<void> _loadLocalDanmakuFile() async {
    if (_isLoadingLocalDanmaku) return;

    setState(() {
      _isLoadingLocalDanmaku = true;
    });

    try {
      // 使用文件选择器选择弹幕文件
      const XTypeGroup jsonTypeGroup = XTypeGroup(
        label: 'JSON弹幕文件',
        extensions: ['json'],
      );
      
      const XTypeGroup xmlTypeGroup = XTypeGroup(
        label: 'XML弹幕文件',
        extensions: ['xml'],
      );
      
      final XFile? file = await openFile(
        acceptedTypeGroups: [jsonTypeGroup, xmlTypeGroup],
        confirmButtonText: '选择弹幕文件',
      );

      if (file == null) {
        // 用户取消选择
        setState(() {
          _isLoadingLocalDanmaku = false;
        });
        return;
      }

      // 读取文件内容并根据扩展名处理
      final fileContent = await file.readAsString();
      final fileName = file.name.toLowerCase();
      Map<String, dynamic> jsonData;
      
      if (fileName.endsWith('.xml')) {
        // XML文件，先转换为JSON格式
        debugPrint('检测到XML弹幕文件，开始转换...');
        jsonData = _convertXmlToJson(fileContent);
        debugPrint('XML转换完成，共${jsonData['comments']?.length ?? 0}条弹幕');
      } else {
        // JSON文件，直接解析
        jsonData = json.decode(fileContent);
      }

      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];
      
      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 获取VideoPlayerState并计算轨道编号
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      final localTrackCount = videoState.danmakuTracks.values.where((track) => track['source'] == 'local').length;
      final trackName = '本地弹幕${localTrackCount + 1}';
      
      // 添加弹幕轨道
      await videoState.loadDanmakuFromLocal(jsonData, trackName: trackName);

      if (mounted) {
        BlurSnackBar.show(context, '弹幕轨道添加成功，共${comments.length}条弹幕');
      }

    } catch (e) {
      debugPrint('加载本地弹幕文件失败: $e');
      if (mounted) {
        BlurSnackBar.show(context, '加载弹幕文件失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocalDanmaku = false;
        });
      }
    }
  }

  // XML弹幕转换为JSON格式
  Map<String, dynamic> _convertXmlToJson(String xmlContent) {
    final List<Map<String, dynamic>> comments = [];
    
    // 使用正则表达式解析XML弹幕格式: <d p="参数">内容</d>
    final RegExp danmakuRegex = RegExp(r'<d p="([^"]+)">([^<]+)</d>');
    final Iterable<RegExpMatch> matches = danmakuRegex.allMatches(xmlContent);
    
    for (final match in matches) {
      try {
        final String pAttr = match.group(1) ?? '';
        final String textContent = match.group(2) ?? '';
        
        if (textContent.isEmpty) continue;
        
        // 解析p属性中的参数，用逗号分隔
        final List<String> pParams = pAttr.split(',');
        
        if (pParams.length >= 4) {
          // XML弹幕格式参数：时间,类型,字号,颜色,时间戳,池,用户id,弹幕id
          final double time = double.tryParse(pParams[0]) ?? 0.0;
          final int typeCode = int.tryParse(pParams[1]) ?? 1;
          final int fontSize = int.tryParse(pParams[2]) ?? 25;
          final int colorCode = int.tryParse(pParams[3]) ?? 16777215; // 默认白色
          
          // 将类型代码转换为弹幕类型
          String danmakuType;
          switch (typeCode) {
            case 4:
              danmakuType = 'bottom';
              break;
            case 5:
              danmakuType = 'top';
              break;
            case 1:
            case 6:
            default:
              danmakuType = 'scroll';
              break;
          }
          
          // 将颜色代码转换为RGB格式
          final int r = (colorCode >> 16) & 0xFF;
          final int g = (colorCode >> 8) & 0xFF;
          final int b = colorCode & 0xFF;
          final String color = 'rgb($r,$g,$b)';
          
          // 创建标准化的弹幕对象
          final Map<String, dynamic> comment = {
            't': time,                    // 时间
            'c': textContent,             // 内容
            'y': danmakuType,             // 类型
            'r': color,                   // 颜色
            'fontSize': fontSize,         // 字号
            'originalType': typeCode,     // 原始类型代码
          };
          
          comments.add(comment);
        }
      } catch (e) {
        debugPrint('解析XML弹幕项失败: $e, 内容: ${match.group(0)}');
        // 跳过无效的弹幕项，继续处理下一个
        continue;
      }
    }
    
    return {
      'count': comments.length,
      'comments': comments,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final tracks = videoState.danmakuTracks;
        final trackEnabled = videoState.danmakuTrackEnabled;
        final totalDanmakuCount = videoState.danmakuList.length;
        final filteredDanmakuCount = videoState.getFilteredDanmakuList().length;

        return BaseSettingsMenu(
          title: '弹幕轨道',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 总览信息
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.5),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '弹幕轨道总览',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共${tracks.length}个轨道，合计$totalDanmakuCount条弹幕',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          if (totalDanmakuCount != filteredDanmakuCount)
                            Text(
                              '显示: $filteredDanmakuCount条 (已过滤${totalDanmakuCount - filteredDanmakuCount}条)',
                              style: TextStyle(
                                color: Colors.orange.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 轨道列表
              ...tracks.entries.map((entry) {
                final trackId = entry.key;
                final trackData = entry.value;
                final isEnabled = trackEnabled[trackId] ?? false;
                final trackName = trackData['name'] as String;
                final source = trackData['source'] as String;
                final count = trackData['count'] as int;
                
                IconData trackIcon;
                Color trackColor;
                
                switch (source) {
                  case 'dandanplay':
                    trackIcon = Icons.cloud;
                    trackColor = Colors.white;
                    break;
                  case 'local':
                    trackIcon = Icons.folder;
                    trackColor = Colors.white;
                    break;
                  default:
                    trackIcon = Icons.track_changes;
                    trackColor = Colors.white;
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => videoState.toggleDanmakuTrack(trackId, !isEnabled),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isEnabled ? Colors.white.withOpacity(0.1) : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.5),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEnabled ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            trackIcon,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trackName,
                                  style: TextStyle(
                                    color: isEnabled ? Colors.white : Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                    fontWeight: isEnabled ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  '$count条弹幕',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 删除按钮（本地轨道才显示）
                          if (source == 'local')
                            GestureDetector(
                              onTap: () => videoState.removeDanmakuTrack(trackId),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),

              // 添加本地弹幕轨道按钮
              _isLoadingLocalDanmaku
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '正在加载弹幕文件...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : BlurButton(
                    icon: Icons.add_circle_outline,
                    text: "加载本地弹幕文件",
                    onTap: _loadLocalDanmakuFile,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    margin: const EdgeInsets.symmetric(horizontal: 0),
                    expandHorizontally: true,
                    borderRadius: BorderRadius.zero,
                  ),
            ],
          ),
        );
      },
    );
  }
} 