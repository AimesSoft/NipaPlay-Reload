/// TextInputDialog - 通用文本输入对话框
///
/// 调用方法：
///
/// 基本调用：
/// final result = await TextInputDialog.show(
///   context,
///   title: '标题',
/// );
///
/// 完整参数调用：
/// final result = await TextInputDialog.show(
///   context,
///   title: '添加屏蔽词',
///   subtitle: '支持逗号分隔批量添加',
///   hintText: '请输入文本',
///   initialValue: '预设文本',
///   minLines: 4,
/// );
///
/// 参数说明：
/// [title] - 必填，对话框标题
/// [subtitle] - 可选，副标题
/// [hintText] - 可选，文本框提示文字
/// [initialValue] - 可选，文本框初始值
/// [minLines] - 可选，文本框最小行数，默认为5
///
/// 返回值：
/// 返回 Future<String?>，点击"确定"返回输入的文本，
/// 点击"取消"或关闭对话框返回null
///
/// 使用示例：
/// final result = await TextInputDialog.show(
///   context,
///   title: '编辑',
///   subtitle: '请输入内容',
///   hintText: '请输入',
/// );
/// if (result != null) {
///   print('用户输入：$result');
/// }
///
/// 支持键盘操作：
/// - ESC键 = 取消
/// - Enter键 = 确定
///
/// 窗口特性：
/// - 自动适应屏幕大小
/// - 键盘弹出时自动调整位置
/// - 支持内容滚动
/// - 可拖拽关闭
/// - 支持亮色/暗色主题切换
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

class TextInputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? hintText;
  final String? initialValue;
  final int minLines;

  const TextInputDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.hintText,
    this.initialValue,
    this.minLines = 5,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? hintText,
    String? initialValue,
    int minLines = 5,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<String>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: TextInputDialog(
        title: title,
        subtitle: subtitle,
        hintText: hintText,
        initialValue: initialValue,
        minLines: minLines,
      ),
    );
  }

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  static Color get _accentColor => AppAccentColors.current;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelAltColor =>
      _isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  TextSelectionThemeData get _selectionTheme => TextSelectionThemeData(
        cursorColor: _accentColor,
        selectionColor: _accentColor.withOpacity(0.3),
        selectionHandleColor: _accentColor,
      );

  ButtonStyle get _primaryButtonStyle => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return _accentColor.withOpacity(0.5);
          }
          return _accentColor;
        }),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        minimumSize: WidgetStateProperty.all(const Size(96, 44)),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    Navigator.of(context).maybePop(text.isEmpty ? null : text);
  }

  void _cancel() {
    Navigator.of(context).maybePop(null);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final double dialogWidth = screenWidth >= 1200
        ? 720.0
        : screenWidth >= 800
            ? screenWidth * 0.85
            : screenWidth * 0.95;
    final double dialogHeight =
        screenHeight >= 600 ? screenHeight * 0.55 : screenHeight * 0.7;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextSelectionTheme(
        data: _selectionTheme,
        child: NipaplayWindowScaffold(
          maxWidth: dialogWidth,
          maxHeightFactor: dialogHeight / screenHeight,
          onClose: _cancel,
          backgroundColor: _surfaceColor,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + keyboardHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: dialogHeight * 0.55,
                    minHeight: 120,
                  ),
                  child: _buildInputField(),
                ),
                const SizedBox(height: 20),
                _buildButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.edit,
            color: _accentColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!,
                  style: TextStyle(color: _subTextColor, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: _panelAltColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _borderColor,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: TextStyle(color: _textColor, fontSize: 15),
            maxLines: null,
            minLines: widget.minLines,
            textAlignVertical: TextAlignVertical.top,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: _subTextColor,
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _cancel,
          style: TextButton.styleFrom(
            foregroundColor: _subTextColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            minimumSize: const Size(88, 44),
            textStyle: const TextStyle(fontSize: 15),
          ),
          child: const Text('取消'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _confirm,
          style: _primaryButtonStyle,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
