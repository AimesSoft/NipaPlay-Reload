import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'player_menu_theme.dart';
import 'settings_hint_text.dart';
import 'dart:convert';
import 'dart:io';
import 'blur_button.dart';
import 'fluent_settings_switch.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/utils/danmaku_history_sync.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/text_input_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

enum _DanmakuExportFormat { json, xml }

class DanmakuSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;
  final ValueChanged<bool>? onHoverChanged;

  const DanmakuSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
    this.onHoverChanged,
  });

  @override
  State<DanmakuSettingsMenu> createState() => _DanmakuSettingsMenuState();
}

class _DanmakuSettingsMenuState extends State<DanmakuSettingsMenu> {
  final TextEditingController _blockWordController = TextEditingController();
  bool _hasBlockWordError = false;
  String? _blockWordErrorMessage;
  bool _isSavingDanmaku = false;

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  List<String> _splitBlockWords(String input) {
    final result = <String>[];
    final current = StringBuffer();
    bool inRegex = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (char == '/' && !inRegex) {
        final prev = current.toString();
        if (prev.isNotEmpty && RegExp(r'\S$').hasMatch(prev)) {
          inRegex = true;
        }
        current.write(char);
      } else if (char == '/' && inRegex) {
        inRegex = false;
        current.write(char);
      } else if (char == ',' && !inRegex) {
        final word = current.toString().trim();
        if (word.isNotEmpty) {
          result.add(word);
        }
        current.clear();
      } else {
        current.write(char);
      }
    }

    final lastWord = current.toString().trim();
    if (lastWord.isNotEmpty) {
      result.add(lastWord);
    }

    return result;
  }

  void _addBlockWordFromInput(String input) {
    final trimmed = input.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }

    final rawWords = _splitBlockWords(trimmed);
    final validWords = <String>[];
    final duplicateWords = <String>[];
    final emptyWords = <String>[];

    for (final w in rawWords) {
      final word = w.trim();
      if (word.isEmpty) {
        emptyWords.add(w);
        continue;
      }
      if (widget.videoState.danmakuBlockWords.contains(word)) {
        duplicateWords.add(word);
      } else {
        validWords.add(word);
      }
    }

    for (final word in validWords) {
      widget.videoState.addDanmakuBlockWord(word);
    }

    String? errorMessage;
    if (validWords.isEmpty && duplicateWords.isEmpty && emptyWords.isNotEmpty) {
      errorMessage = '所有输入的词都是空的';
    } else if (validWords.isEmpty && duplicateWords.isNotEmpty) {
      errorMessage = duplicateWords.length == 1
          ? '该屏蔽词已存在'
          : '这些屏蔽词已存在：${duplicateWords.join('、')}';
    } else if (validWords.isNotEmpty) {
      final successMessage = validWords.length == 1
          ? '已添加屏蔽词：${validWords.first}'
          : '已添加 ${validWords.length} 个屏蔽词';
      BlurSnackBar.show(context, successMessage);
      _blockWordController.clear();
      setState(() {
        _hasBlockWordError = false;
        _blockWordErrorMessage = '';
      });
      return;
    }

    if (errorMessage != null) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = errorMessage;
      });
    }
  }

  Future<void> _showBlockWordInputDialog() async {
    final result = await TextInputDialog.show(
      context,
      title: '添加屏蔽词',
      subtitle: '输入要屏蔽的关键词，批量添加请用逗号隔开（支持正则，以"规则名称/表达式/"形式输入）',
      hintText: '请输入文本',
      minLines: 4,
    );

    if (result != null && result.isNotEmpty) {
      _addBlockWordFromInput(result);
    }
  }

  void _addBlockWord() {
    if (globals.isMobilePlatform) {
      _showBlockWordInputDialog();
      return;
    }

    final input = _blockWordController.text.trim();

    if (input.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }

    _addBlockWordFromInput(input);
  }

  Future<void> _saveDanmaku(_DanmakuExportFormat format) async {
    if (_isSavingDanmaku) return;

    final exportList = widget.videoState.collectDanmakuForExport();
    if (exportList.isEmpty) {
      if (mounted) {
        BlurSnackBar.show(context, '当前没有可保存的弹幕');
      }
      return;
    }

    if (mounted) {
      setState(() => _isSavingDanmaku = true);
    } else {
      _isSavingDanmaku = true;
    }

    try {
      final extension = format == _DanmakuExportFormat.xml ? 'xml' : 'json';
      final fileName =
          _buildDanmakuExportFileName(widget.videoState, extension);
      final savePath = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: extension.toUpperCase(),
            extensions: [extension],
          ),
        ],
      );

      if (savePath == null) {
        return;
      }

      final content = format == _DanmakuExportFormat.xml
          ? widget.videoState.buildDanmakuXmlExport(exportList)
          : widget.videoState.buildDanmakuJsonExport(exportList);
      final file = File(savePath.path);
      await file.writeAsString(content, encoding: utf8);

      if (mounted) {
        BlurSnackBar.show(context, '弹幕已保存到: ${savePath.path}');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '保存弹幕失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingDanmaku = false);
      } else {
        _isSavingDanmaku = false;
      }
    }
  }

  String _buildDanmakuExportFileName(
    VideoPlayerState videoState,
    String extension,
  ) {
    final title = videoState.animeTitle?.trim();
    final fallback = videoState.currentVideoPath == null
        ? 'danmaku'
        : p.basenameWithoutExtension(videoState.currentVideoPath!);
    final baseName = (title == null || title.isEmpty) ? fallback : title;
    final timestamp = _formatTimestamp(DateTime.now());
    return '${baseName}_danmaku_$timestamp.$extension';
  }

  String _formatTimestamp(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${time.year}'
        '${twoDigits(time.month)}'
        '${twoDigits(time.day)}_'
        '${twoDigits(time.hour)}'
        '${twoDigits(time.minute)}'
        '${twoDigits(time.second)}';
  }

  // 检查是否是正则表达式规则格式: 规则名称/表达式/
  bool _isRegexRule(String word) {
    if (!word.contains('/')) return false;
    final parts = word.split('/');
    return parts.length >= 3 && parts.first.isNotEmpty && parts.last.isEmpty;
  }

  // 获取屏蔽词的显示文本
  String _getDisplayText(String word) {
    if (_isRegexRule(word)) {
      final firstSlash = word.indexOf('/');
      final name = word.substring(0, firstSlash);
      return '规则：$name';
    }
    return word;
  }

  // 构建屏蔽词展示UI
  Widget _buildBlockWordsList() {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        if (videoState.danmakuBlockWords.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            child: Text(
              '暂无屏蔽词',
              style:
                  TextStyle(color: menuColors.disabledForeground, fontSize: 14),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: videoState.danmakuBlockWords.map((word) {
            return Container(
              decoration: BoxDecoration(
                color: menuColors.controlBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: menuColors.controlBorder,
                  width: 0.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getDisplayText(word),
                      style: TextStyle(
                        color: menuColors.foreground,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => videoState.removeDanmakuBlockWord(word),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: menuColors.secondaryForeground,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        return BaseSettingsMenu(
          title: '弹幕设置',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '显示弹幕',
                          style: TextStyle(
                            color: menuColors.foreground,
                            fontSize: 14,
                          ),
                        ),
                        FluentSettingsSwitch(
                          value: videoState.danmakuVisible,
                          onChanged: (value) {
                            videoState.setDanmakuVisible(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('开启后在视频上显示弹幕内容'),
                  ],
                ),
              ),
              // 手动匹配弹幕
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlurButton(
                      text: '手动匹配弹幕',
                      icon: Icons.search,
                      onTap: () async {
                        debugPrint('=== 弹幕设置菜单：点击手动匹配弹幕按钮 ===');
                        print('=== 强制输出：手动匹配弹幕按钮被点击！ ===');
                        final rootContext =
                            Navigator.of(context, rootNavigator: true).context;
                        final uiThemeProvider = Provider.of<UIThemeProvider>(
                          context,
                          listen: false,
                        );
                        if (uiThemeProvider.isCupertinoTheme) {
                          final menuScope = SettingsMenuScope.maybeOf(context);
                          if (menuScope?.requestClose != null) {
                            await menuScope!.requestClose!();
                          }
                        }
                        final videoState = widget.videoState;
                        final initialVideoPath = videoState.currentVideoPath;
                        final String? initialSearchKeyword = initialVideoPath ==
                                null
                            ? null
                            : (initialVideoPath.startsWith('jellyfin://') ||
                                    initialVideoPath.startsWith('emby://'))
                                ? (videoState.animeTitle?.trim().isNotEmpty ==
                                        true
                                    ? videoState.animeTitle!.trim()
                                    : null)
                                : p.basenameWithoutExtension(initialVideoPath);
                        final result = await ManualDanmakuMatcher.instance
                            .showManualMatchDialog(
                          uiThemeProvider.isCupertinoTheme
                              ? rootContext
                              : context,
                          initialVideoTitle: initialSearchKeyword,
                        );

                        if (result != null) {
                          if (videoState.isDisposed ||
                              videoState.currentVideoPath != initialVideoPath) {
                            debugPrint('视频已切换或播放器已销毁，取消加载弹幕');
                            return;
                          }

                          // 如果用户选择了弹幕，重新加载弹幕
                          final episodeId =
                              result['episodeId']?.toString() ?? '';
                          final animeId = result['animeId']?.toString() ?? '';

                          if (episodeId.isNotEmpty && animeId.isNotEmpty) {
                            // 调用新的弹幕历史同步方法来更新历史记录
                            try {
                              final currentVideoPath =
                                  videoState.currentVideoPath;
                              if (currentVideoPath != null) {
                                await DanmakuHistorySync
                                    .updateHistoryWithDanmakuInfo(
                                  videoPath: currentVideoPath,
                                  episodeId: episodeId,
                                  animeId: animeId,
                                  animeTitle: result['animeTitle']?.toString(),
                                  episodeTitle:
                                      result['episodeTitle']?.toString(),
                                );

                                // 立即更新视频播放器状态中的动漫和剧集标题
                                videoState.setAnimeTitle(
                                    result['animeTitle']?.toString());
                                videoState.setEpisodeTitle(
                                    result['episodeTitle']?.toString());
                              }
                            } catch (e) {}
                            videoState.loadDanmaku(episodeId, animeId);
                          }
                        }
                      },
                      expandHorizontally: true,
                    ),
                    const SettingsHintText('手动搜索并选择匹配的弹幕文件'),
                  ],
                ),
              ),
              // 保存弹幕
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保存弹幕',
                      style: TextStyle(
                        color: menuColors.foreground,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: BlurButton(
                            text: '保存为 JSON',
                            icon: Icons.save_alt,
                            onTap: () =>
                                _saveDanmaku(_DanmakuExportFormat.json),
                            expandHorizontally: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BlurButton(
                            text: '保存为 XML',
                            icon: Icons.save_alt,
                            onTap: () => _saveDanmaku(_DanmakuExportFormat.xml),
                            expandHorizontally: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('保存当前启用轨道的弹幕到本地文件'),
                  ],
                ),
              ),
              // 弹幕屏蔽词
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: Consumer<VideoPlayerState>(
                    builder: (context, videoState, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '弹幕屏蔽词',
                            style: TextStyle(
                              color: menuColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // 毛玻璃效果的白色添加按钮
                          BlurButton(
                            icon: Icons.add,
                            text: '添加',
                            onTap: () => _addBlockWord(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (globals.isMobilePlatform)
                        _buildMobileBlockWordInput()
                      else
                        _buildDesktopBlockWordInput(),
                      if (_hasBlockWordError && _blockWordErrorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 12),
                          child: Text(
                            _blockWordErrorMessage!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _buildBlockWordsList(),
                      const SettingsHintText('包含屏蔽词或被正则表达式命中的弹幕将被过滤'),
                    ],
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopBlockWordInput() {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: menuColors.controlBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasBlockWordError
              ? Colors.redAccent.withOpacity(0.8)
              : menuColors.controlBorder,
          width: 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: _blockWordController,
          style: TextStyle(color: menuColors.foreground, fontSize: 13),
          textAlignVertical: TextAlignVertical.center,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '输入要屏蔽的关键词\n（支持正则，以"规则名称/表达式/"形式输入；支持逗号分隔批量添加）',
            hintStyle: TextStyle(
              color: menuColors.disabledForeground,
              fontSize: 13,
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                Icons.clear,
                color: menuColors.secondaryForeground,
                size: 18,
              ),
              onPressed: () => _blockWordController.clear(),
              tooltip: '',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
            ),
          ),
          onSubmitted: (_) => _addBlockWord(),
        ),
      ),
    );
  }

  Widget _buildMobileBlockWordInput() {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return GestureDetector(
      onTap: _showBlockWordInputDialog,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: menuColors.controlBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hasBlockWordError
                ? Colors.redAccent.withOpacity(0.8)
                : menuColors.controlBorder,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            '点击输入屏蔽词',
            style: TextStyle(
              color: menuColors.disabledForeground,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
