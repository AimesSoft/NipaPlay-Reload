import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class BangumiCommentDialog extends StatefulWidget {
  final String animeTitle;
  final int initialRating;
  final String? initialComment;
  final int collectionType;
  final Future<void> Function(BangumiCollectionSubmitResult result) onSubmit;

  const BangumiCommentDialog({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    this.initialComment,
    required this.collectionType,
    required this.onSubmit,
  });

  static Future<void> show({
    required BuildContext context,
    required String animeTitle,
    required int initialRating,
    String? initialComment,
    required int collectionType,
    required Future<void> Function(BangumiCollectionSubmitResult result)
        onSubmit,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: BangumiCommentDialog(
        animeTitle: animeTitle,
        initialRating: initialRating,
        initialComment: initialComment,
        collectionType: collectionType,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<BangumiCommentDialog> createState() => _BangumiCommentDialogState();
}

class _BangumiCommentDialogState extends State<BangumiCommentDialog> {
  static Color get _accentColor => AppAccentColors.current;
  static const Map<int, String> _ratingEvaluationMap = {
    1: '不忍直视',
    2: '很差',
    3: '差',
    4: '较差',
    5: '不过不失',
    6: '还行',
    7: '推荐',
    8: '力荐',
    9: '神作',
    10: '超神作',
  };

  late int _selectedRating;
  late TextEditingController _commentController;
  bool _isSubmitting = false;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelAltColor =>
      _isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);

  TextSelectionThemeData get _selectionTheme => TextSelectionThemeData(
        cursorColor: _accentColor,
        selectionColor: _accentColor.withOpacity(0.3),
        selectionHandleColor: _accentColor,
      );

  ButtonStyle _textButtonStyle({Color? baseColor}) {
    final resolvedBase = baseColor ?? _textColor;
    return ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return _mutedTextColor;
        }
        if (states.contains(MaterialState.hovered)) {
          return _accentColor;
        }
        return resolvedBase;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return _accentColor.withOpacity(0.5);
        }
        return _accentColor;
      }),
      foregroundColor: MaterialStateProperty.all(Colors.white),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      minimumSize: MaterialStateProperty.all(const Size(96, 44)),
      elevation: MaterialStateProperty.all(0),
      shadowColor: MaterialStateProperty.all(Colors.transparent),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.initialRating.clamp(0, 10);
    _commentController =
        TextEditingController(text: widget.initialComment ?? '');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    final focusScope = FocusScope.of(context);
    if (!focusScope.hasPrimaryFocus) {
      focusScope.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width >= 760
        ? 480.0
        : globals.DialogSizes.getDialogWidth(screenSize.width);
    final maxHeightFactor =
        (globals.isPhone && screenSize.shortestSide < 600) ? 0.85 : 0.8;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return TextSelectionTheme(
      data: _selectionTheme,
      child: NipaplayWindowScaffold(
        maxWidth: dialogWidth,
        maxHeightFactor: maxHeightFactor,
        onClose: () => Navigator.of(context).maybePop(),
        backgroundColor: _surfaceColor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _dismissKeyboard,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboardHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRatingSection(),
                        SizedBox(height: 18),
                        _buildCommentInput(),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                _buildActionButtons(),
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
            Ionicons.chatbubble_ellipses_outline,
            color: _accentColor,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '编辑短评',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                widget.animeTitle,
                style: TextStyle(
                  color: _subTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '评分',
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              Text(
                _selectedRating > 0 ? '$_selectedRating 分' : '未评分',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_selectedRating > 0) ...[
                SizedBox(height: 4),
                Text(
                  _ratingEvaluationMap[_selectedRating] ?? '',
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(10, (index) {
              final rating = index + 1;
              final isActive = rating <= _selectedRating;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedRating = rating),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isActive
                          ? _accentColor.withOpacity(_isDarkMode ? 0.2 : 0.12)
                          : _panelAltColor,
                      border: Border.all(
                        color: isActive ? _accentColor : _borderColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      isActive ? Ionicons.star : Ionicons.star_outline,
                      color: isActive ? _accentColor : _mutedTextColor,
                      size: 18,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(10, (index) {
            final rating = index + 1;
            final isSelected = rating == _selectedRating;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedRating = rating),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accentColor.withOpacity(_isDarkMode ? 0.2 : 0.12)
                        : _panelAltColor,
                    border: Border.all(
                      color: isSelected ? _accentColor : _borderColor,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '$rating',
                      style: TextStyle(
                        color: isSelected ? _accentColor : _textColor,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '短评',
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 4,
          maxLength: 200,
          onTapOutside: (_) => _dismissKeyboard(),
          style: TextStyle(color: _textColor, fontSize: 13, height: 1.4),
          cursorColor: _accentColor,
          decoration: InputDecoration(
            counterStyle: TextStyle(color: _mutedTextColor, fontSize: 11),
            hintText: '写下你的短评（可选）',
            hintStyle: TextStyle(color: _mutedTextColor, fontSize: 13),
            filled: true,
            fillColor: _panelAltColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _accentColor, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (_selectedRating > 0)
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() => _selectedRating = 0),
            style: _textButtonStyle(baseColor: _accentColor),
            child: const Text('清除评分'),
          ),
        const Spacer(),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          style: _textButtonStyle(),
          child: const Text('取消'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed:
              _isSubmitting || _selectedRating == 0 ? null : _handleSubmit,
          style: _primaryButtonStyle(),
          child: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  '确定',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    final result = BangumiCollectionSubmitResult(
      rating: _selectedRating,
      collectionType: widget.collectionType,
      comment: _commentController.text,
      episodeStatus: 0,
    );

    try {
      await widget.onSubmit(result);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}
