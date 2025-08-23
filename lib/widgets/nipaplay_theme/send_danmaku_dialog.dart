import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class SendDanmakuDialogContent extends StatefulWidget {
  final int episodeId;
  final double currentTime;
  final Function(Map<String, dynamic> danmaku)? onDanmakuSent;

  const SendDanmakuDialogContent({
    super.key,
    required this.episodeId,
    required this.currentTime,
    this.onDanmakuSent,
  });

  @override
  SendDanmakuDialogContentState createState() => SendDanmakuDialogContentState();
}

class SendDanmakuDialogContentState extends State<SendDanmakuDialogContent> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController textController = TextEditingController();
  final TextEditingController _hexColorController = TextEditingController();
  Color selectedColor = const Color(0xFFffffff);
  String danmakuType = 'scroll'; // 'scroll', 'top', 'bottom'
  bool _isSending = false;

  final List<Color> _presetColors = [
    const Color(0xFFfe0502), const Color(0xFFff7106), const Color(0xFFffaa01), const Color(0xFFffd301),
    const Color(0xFFffff00), const Color(0xFFa0ee02), const Color(0xFF04cd00), const Color(0xFF019899),
    const Color(0xFF4266be), const Color(0xFF89d5ff), const Color(0xFFcc0173), const Color(0xFF000000), const Color(0xFF222222),
    const Color(0xFF9b9b9b), const Color(0xFFffffff),
  ];

  Color _getStrokeColor(Color textColor) {
    // This logic should match the actual danmaku rendering
    final luminance = (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    return luminance < 0.2 ? Colors.white : Colors.black;
  }

  Color _darken(Color color, [double amount = .3]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  Color _lighten(Color color, [double amount = .3]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    textController.dispose();
    _hexColorController.dispose();
    super.dispose();
  }

  int _getDanmakuMode() {
    switch (danmakuType) {
      case 'top':
        return 5;
      case 'bottom':
        return 4;
      case 'scroll':
      default:
        return 1;
    }
  }

  int _colorToInt(Color color) {
    return (color.red * 256 * 256) + (color.green * 256) + color.blue;
  }

  Future<void> _sendDanmaku() async {
    if (textController.text.isEmpty) {
      BlurSnackBar.show(context, '弹幕内容不能为空');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final result = await DandanplayService.sendDanmaku(
        episodeId: widget.episodeId,
        time: widget.currentTime,
        mode: _getDanmakuMode(),
        color: _colorToInt(selectedColor),
        comment: textController.text,
      );

      if (mounted) {
        BlurSnackBar.show(context, '弹幕发送成功');
        if (result['success'] == true && result.containsKey('danmaku')) {
          widget.onDanmakuSent?.call(result['danmaku']);
        }
        Navigator.of(context).pop(true); // Close the dialog
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '发送失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否为真正的手机设备
    final window = WidgetsBinding.instance.window;
    final size = window.physicalSize / window.devicePixelRatio;
    final shortestSide = size.width < size.height ? size.width : size.height;
    final bool isRealPhone = globals.isPhone && shortestSide < 600;

    final strokeColor = _getStrokeColor(selectedColor);
     
    final danmakuPreview = Text(
      textController.text,
      style: TextStyle(
        fontSize: 20,
        color: selectedColor,
        shadows: [
          Shadow(
            offset: Offset(globals.strokeWidth, globals.strokeWidth),
            blurRadius: 2.0,
            color: strokeColor,
          ),
          Shadow(
            offset: Offset(-globals.strokeWidth, -globals.strokeWidth),
            blurRadius: 2.0,
            color: strokeColor,
          ),
          Shadow(
            offset: Offset(globals.strokeWidth, -globals.strokeWidth),
            blurRadius: 2.0,
            color: strokeColor,
          ),
          Shadow(
            offset: Offset(-globals.strokeWidth, globals.strokeWidth),
            blurRadius: 2.0,
            color: strokeColor,
          ),
        ],
      ),
    );

    if (isRealPhone) {
      // 手机设备使用左右布局，充满可用空间
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, // 让子项拉伸到父容器高度
          children: [
            // 左侧：输入区域
            Expanded(
              flex: 1,
              child: _buildInputSection(),
            ),
            const SizedBox(width: 16),
            // 右侧：颜色选择
            Expanded(
              flex: 1,
              child: _buildColorSection(),
            ),
          ],
        ),
      );
    } else {
      // 非手机设备保持原有布局
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 弹幕预览
                Container(
                  height: 100,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: danmakuPreview,
                  ),
                ),
                TextField(
                  controller: textController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '在这里输入弹幕内容...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  fillColor: Colors.white24,
                  filled: true,
                ),
                maxLength: 100,
                onChanged: (text) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              const Text('选择颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _presetColors.map((color) {
                  final isSelected = selectedColor == color;
                  Color borderColor;
                  if (isSelected) {
                    // For white, we can't lighten it, so use a highlight color.
                    if (color.value == 0xFFFFFFFF) {
                      borderColor = Theme.of(context).colorScheme.secondary;
                    } else {
                      borderColor = _lighten(color);
                    }
                  } else {
                    // For black, we can't darken it, so use a slightly lighter grey to show the border.
                    if (color == const Color(0xFF000000) || color == const Color(0xFF222222)) {
                      borderColor = Colors.grey.shade800;
                    } else {
                      borderColor = _darken(color);
                    }
                  }
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: borderColor,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hexColorController,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '输入六位十六进制颜色值',
                  counterText: '',
                  prefixText: '#',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                  ),
                ),
                onChanged: (value) {
                  if (value.length == 6) {
                    try {
                      final colorInt = int.parse(value, radix: 16);
                      setState(() {
                        selectedColor = Color(0xFF000000 | colorInt);
                      });
                    } catch (e) {
                      // Ignore invalid hex values
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('弹幕模式'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey),
                ),
                child: ToggleButtons(
                  isSelected: [
                    danmakuType == 'scroll',
                    danmakuType == 'top',
                    danmakuType == 'bottom',
                  ],
                  onPressed: (index) {
                    setState(() {
                      if (index == 0) danmakuType = 'scroll';
                      if (index == 1) danmakuType = 'top';
                      if (index == 2) danmakuType = 'bottom';
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  selectedColor: Colors.black,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  color: Colors.white,
                  constraints: const BoxConstraints(minHeight: 40.0, minWidth: 80.0),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('滚动')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('顶部')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('底部')),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: _isSending
                    ? const CircularProgressIndicator()
                    : GestureDetector(
                        onTap: _isSending ? null : _sendDanmaku,
                        child: GlassmorphicContainer(
                          width: 120,
                          height: 50,
                          borderRadius: 25,
                          blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
                          alignment: Alignment.center,
                          border: 2,
                          linearGradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                                Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                              ],
                              stops: const [
                                0.1,
                                1,
                              ]),
                          borderGradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                              Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                            ],
                          ),
                          child: const Text(
                            '发送',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    }
  }

  /// 构建输入区域（手机设备左侧）
  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 输入框
        TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入弹幕内容...',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
            fillColor: Colors.white24,
            filled: true,
          ),
          maxLength: 100,
          onChanged: (text) {
            setState(() {});
          },
        ),
        
        const SizedBox(height: 16),
        
        // 弹幕模式选择
        const Text('弹幕模式', style: TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey),
          ),
          child: ToggleButtons(
            isSelected: [
              danmakuType == 'scroll',
              danmakuType == 'top',
              danmakuType == 'bottom',
            ],
            onPressed: (index) {
              setState(() {
                if (index == 0) danmakuType = 'scroll';
                if (index == 1) danmakuType = 'top';
                if (index == 2) danmakuType = 'bottom';
              });
            },
            borderRadius: BorderRadius.circular(20),
            selectedColor: Colors.black,
            fillColor: Theme.of(context).colorScheme.secondary,
            color: Colors.white,
            constraints: const BoxConstraints(minHeight: 35.0, minWidth: 60.0),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('滚动', style: TextStyle(fontSize: 12))),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('顶部', style: TextStyle(fontSize: 12))),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('底部', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建颜色选择区域（手机设备右侧）
  Widget _buildColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 上部：预设颜色
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: _presetColors.map((color) {
            final isSelected = selectedColor == color;
            Color borderColor;
            if (isSelected) {
              // For white, we can't lighten it, so use a highlight color.
              if (color.value == 0xFFFFFFFF) {
                borderColor = Theme.of(context).colorScheme.secondary;
              } else {
                borderColor = _lighten(color);
              }
            } else {
              // For black, we can't darken it, so use a slightly lighter grey to show the border.
              if (color == const Color(0xFF000000) || color == const Color(0xFF222222)) {
                borderColor = Colors.grey.shade800;
              } else {
                borderColor = _darken(color);
              }
            }
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedColor = color;
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        
        const Spacer(), // 推送发送按钮到底部
        
        // 底部：发送按钮 - 固定在底部
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: SizedBox(
            width: double.infinity,
            child: _isSending
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    onTap: _isSending ? null : _sendDanmaku,
                    child: GlassmorphicContainer(
                      width: double.infinity,
                      height: 45,
                      borderRadius: 22,
                      blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
                      alignment: Alignment.center,
                      border: 2,
                      linearGradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                            Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                          ],
                          stops: const [
                            0.1,
                            1,
                          ]),
                      borderGradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                          Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                        ],
                      ),
                      child: const Text(
                        '发送弹幕',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
} 