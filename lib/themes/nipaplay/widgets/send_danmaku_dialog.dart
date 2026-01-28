import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bounce_hover_scale.dart';
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
  bool _isSendButtonHovered = false;
  bool _isSendButtonPressed = false;

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
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final bool isRealPhone = globals.isPhone && shortestSide < 600;
    
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const inputThemeColor = Color(0xFFff2e55);

    final strokeColor = _getStrokeColor(selectedColor);
    
    final previewStyle = TextStyle(
      fontSize: 18,
      color: selectedColor,
      shadows: [
        Shadow(
          offset: Offset(globals.strokeWidth, globals.strokeWidth),
          blurRadius: 0.0,
          color: strokeColor,
        ),
        Shadow(
          offset: Offset(-globals.strokeWidth, -globals.strokeWidth),
          blurRadius: 0.0,
          color: strokeColor,
        ),
        Shadow(
          offset: Offset(globals.strokeWidth, -globals.strokeWidth),
          blurRadius: 0.0,
          color: strokeColor,
        ),
        Shadow(
          offset: Offset(-globals.strokeWidth, globals.strokeWidth),
          blurRadius: 0.0,
          color: strokeColor,
        ),
      ],
    );

    if (isRealPhone) {
      return _buildPhoneLayout(theme, previewStyle, inputThemeColor);
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
                TextField(
                  controller: textController,
                  autofocus: true,
                  style: previewStyle,
                  cursorColor: inputThemeColor,
                  decoration: InputDecoration(
                    hintText: '在这里输入弹幕内容...',
                    hintStyle: TextStyle(
                      color: theme.hintColor,
                      fontSize: previewStyle.fontSize,
                      shadows: const [],
                    ),
                    border: const OutlineInputBorder(),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: inputThemeColor, width: 2),
                    ),
                    fillColor: colorScheme.surfaceContainerHighest,
                    filled: true,
                  ),
                  maxLength: 100,
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                Text('选择颜色', style: TextStyle(color: colorScheme.onSurface)),
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
                        borderColor = colorScheme.secondary;
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
                  style: TextStyle(color: colorScheme.onSurface),
                  cursorColor: inputThemeColor,
                  decoration: InputDecoration(
                    hintText: '输入六位十六进制颜色值',
                    counterText: '',
                    prefixText: '#',
                    hintStyle: TextStyle(color: theme.hintColor),
                    prefixStyle: TextStyle(color: theme.hintColor),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: inputThemeColor, width: 2),
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
                Text('弹幕模式', style: TextStyle(color: colorScheme.onSurface)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
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
                              borderRadius: BorderRadius.circular(8),
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              selectedColor: inputThemeColor,
                              fillColor: Colors.transparent,
                              color: theme.colorScheme.onSurface,
                              constraints: const BoxConstraints(minHeight: 32.0, minWidth: 80.0),
                              children: const [
                                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('滚动')),
                                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('顶部')),
                                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('底部')),
                              ],
                            ),                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isSending
                      ? const CircularProgressIndicator()
                      : MouseRegion(
                          onEnter: (_) => setState(() => _isSendButtonHovered = true),
                          onExit: (_) => setState(() => _isSendButtonHovered = false),
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTapDown: (_) => setState(() => _isSendButtonPressed = true),
                            onTapUp: (_) => setState(() => _isSendButtonPressed = false),
                            onTapCancel: () => setState(() => _isSendButtonPressed = false),
                            onTap: _isSending ? null : _sendDanmaku,
                            child: BounceHoverScale(
                              isHovered: _isSendButtonHovered,
                              isPressed: _isSendButtonPressed,
                              child: Container(
                                width: 120,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(25),
                                  color: inputThemeColor,
                                ),
                                alignment: Alignment.center,
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
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildPhoneLayout(
    ThemeData theme,
    TextStyle previewStyle,
    Color inputThemeColor,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: textController,
            autofocus: true,
            style: previewStyle,
            cursorColor: inputThemeColor,
            decoration: InputDecoration(
              hintText: '输入弹幕内容...',
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: previewStyle.fontSize,
                shadows: const [],
              ),
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: inputThemeColor, width: 2),
              ),
              fillColor: theme.colorScheme.surfaceContainerHighest,
              filled: true,
            ),
            maxLength: 100,
            onChanged: (text) {
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          Text('弹幕模式', style: TextStyle(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          CupertinoSegmentedControl<String>(
            groupValue: danmakuType,
            selectedColor: inputThemeColor,
            unselectedColor: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey5,
              context,
            ),
            borderColor: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey3,
              context,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: const {
              'scroll': Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('滚动', style: TextStyle(fontSize: 12)),
              ),
              'top': Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('顶部', style: TextStyle(fontSize: 12)),
              ),
              'bottom': Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('底部', style: TextStyle(fontSize: 12)),
              ),
            },
            onValueChanged: (value) {
              setState(() {
                danmakuType = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Text('选择颜色', style: TextStyle(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _presetColors.map((color) {
              final isSelected = selectedColor == color;
              Color borderColor;
              if (isSelected) {
                if (color.value == 0xFFFFFFFF) {
                  borderColor = theme.colorScheme.secondary;
                } else {
                  borderColor = _lighten(color);
                }
              } else {
                if (color == const Color(0xFF000000) ||
                    color == const Color(0xFF222222)) {
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
          const SizedBox(height: 12),
          TextField(
            controller: _hexColorController,
            maxLength: 6,
            style: TextStyle(color: theme.colorScheme.onSurface),
            cursorColor: inputThemeColor,
            decoration: InputDecoration(
              hintText: '输入六位十六进制颜色值',
              counterText: '',
              prefixText: '#',
              hintStyle: TextStyle(color: theme.hintColor),
              prefixStyle: TextStyle(color: theme.hintColor),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: inputThemeColor, width: 2),
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
          _buildSendButton(
            width: double.infinity,
            label: '发送弹幕',
            height: 46,
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton({
    required double width,
    required String label,
    required double height,
  }) {
    if (_isSending) {
      return const Center(child: CircularProgressIndicator());
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _isSendButtonHovered = true),
      onExit: (_) => setState(() => _isSendButtonHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isSendButtonPressed = true),
        onTapUp: (_) => setState(() => _isSendButtonPressed = false),
        onTapCancel: () => setState(() => _isSendButtonPressed = false),
        onTap: _isSending ? null : _sendDanmaku,
        child: BounceHoverScale(
          isHovered: _isSendButtonHovered,
          isPressed: _isSendButtonPressed,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              color: const Color(0xFFff2e55),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建输入区域（手机设备左侧）
  Widget _buildInputSection(ThemeData theme, TextStyle previewStyle, Color inputThemeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 输入框
        TextField(
          controller: textController,
          autofocus: true,
          style: previewStyle,
          cursorColor: inputThemeColor,
          decoration: InputDecoration(
            hintText: '输入弹幕内容...',
            hintStyle: TextStyle(
              color: theme.hintColor,
              fontSize: previewStyle.fontSize,
              shadows: const [],
            ),
            border: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: inputThemeColor, width: 2),
            ),
            fillColor: theme.colorScheme.surfaceContainerHighest,
            filled: true,
          ),
          maxLength: 100,
          onChanged: (text) {
            setState(() {});
          },
        ),
        
        const SizedBox(height: 16),
        
        // 弹幕模式选择
        Text('弹幕模式', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
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
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            selectedColor: const Color(0xFFff2e55),
            fillColor: Colors.transparent,
            color: theme.colorScheme.onSurface,
            constraints: const BoxConstraints(minHeight: 32.0, minWidth: 60.0),
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
  Widget _buildColorSection(ThemeData theme) {
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
                borderColor = theme.colorScheme.secondary;
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
            child: _buildSendButton(
              width: double.infinity,
              label: '发送弹幕',
              height: 45,
            ),
          ),
        ),
      ],
    );
  }
}
