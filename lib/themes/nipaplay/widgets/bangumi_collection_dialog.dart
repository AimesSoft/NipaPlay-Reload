import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class BangumiCollectionDialog extends StatefulWidget {
  final String animeTitle;
  final int initialRating;
  final int initialCollectionType;
  final String? initialComment;
  final int initialEpisodeStatus;
  final int totalEpisodes;
  final Future<void> Function(BangumiCollectionSubmitResult result) onSubmit;

  const BangumiCollectionDialog({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    required this.initialCollectionType,
    this.initialComment,
    required this.initialEpisodeStatus,
    required this.totalEpisodes,
    required this.onSubmit,
  });

  static Future<void> show({
    required BuildContext context,
    required String animeTitle,
    required int initialRating,
    required int initialCollectionType,
    String? initialComment,
    required int initialEpisodeStatus,
    required int totalEpisodes,
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
      child: BangumiCollectionDialog(
        animeTitle: animeTitle,
        initialRating: initialRating,
        initialCollectionType: initialCollectionType,
        initialComment: initialComment,
        initialEpisodeStatus: initialEpisodeStatus,
        totalEpisodes: totalEpisodes,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<BangumiCollectionDialog> createState() =>
      _BangumiCollectionDialogState();
}

class _BangumiCollectionDialogState extends State<BangumiCollectionDialog> {
  static const Color _accentColor = Color(0xFFFF2E55);
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

  static const List<Map<String, dynamic>> _collectionOptions = [
    {'value': 1, 'label': '想看'},
    {'value': 3, 'label': '在看'},
    {'value': 2, 'label': '已看'},
    {'value': 4, 'label': '搁置'},
    {'value': 5, 'label': '抛弃'},
  ];

  late int _selectedRating;
  late int _selectedCollectionType;
  late TextEditingController _commentController;
  late TextEditingController _episodeController;
  late int _selectedEpisodeStatus;
  bool _isSubmitting = false;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
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
    final initialType = widget.initialCollectionType;
    final validTypes =
        _collectionOptions.map((option) => option['value'] as int);
    _selectedCollectionType =
        validTypes.contains(initialType) ? initialType : 3;
    _commentController =
        TextEditingController(text: widget.initialComment ?? '');
    final total = widget.totalEpisodes;
    final initialEpisode = widget.initialEpisodeStatus;
    _selectedEpisodeStatus = initialEpisode.clamp(0, total > 0 ? total : 999);
    _episodeController =
        TextEditingController(text: _selectedEpisodeStatus.toString());
  }

  @override
  void dispose() {
    _commentController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width >= 760
        ? 620.0
        : globals.DialogSizes.getDialogWidth(screenSize.width);
    final maxHeightFactor = (globals.isPhone && screenSize.shortestSide < 600)
        ? 0.9
        : 0.85;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return TextSelectionTheme(
      data: _selectionTheme,
      child: NipaplayWindowScaffold(
        maxWidth: dialogWidth,
        maxHeightFactor: maxHeightFactor,
        onClose: () => Navigator.of(context).maybePop(),
        backgroundColor: _surfaceColor,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboardHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRatingSection(),
                      const SizedBox(height: 18),
                      _buildCollectionSection(),
                      const SizedBox(height: 18),
                      _buildEpisodeStatusSection(),
                      const SizedBox(height: 18),
                      _buildCommentInput(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(),
            ],
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
          child: const Icon(
            Icons.star_rate_rounded,
            color: _accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '编辑 Bangumi 评分',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
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
        const SizedBox(height: 8),
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
                const SizedBox(height: 4),
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
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(10, (index) {
              final rating = index + 1;
              final isActive = rating <= _selectedRating;
              return GestureDetector(
                onTap: () => setState(() => _selectedRating = rating),
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
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(10, (index) {
            final rating = index + 1;
            final isSelected = rating == _selectedRating;
            return GestureDetector(
              onTap: () => setState(() => _selectedRating = rating),
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
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCollectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '收藏状态',
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _collectionOptions.map((option) {
            final value = option['value'] as int;
            final label = option['label'] as String;
            final isSelected = value == _selectedCollectionType;
            return GestureDetector(
              onTap: () => setState(() => _selectedCollectionType = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeInOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _accentColor.withOpacity(_isDarkMode ? 0.2 : 0.12)
                      : _panelAltColor,
                  border: Border.all(
                    color: isSelected ? _accentColor : _borderColor,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? _accentColor : _textColor,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildEpisodeStatusSection() {
    final total = widget.totalEpisodes;
    final hasTotal = total > 0;
    final maxValue = hasTotal ? total : 999;

    Widget buildAdjustButton(int delta, IconData icon) {
      return InkWell(
        onTap: _isSubmitting
            ? null
            : () {
                final nextValue = _selectedEpisodeStatus + delta;
                final int sanitized = nextValue < 0
                    ? 0
                    : (nextValue > maxValue ? maxValue : nextValue);
                _updateEpisodeStatus(sanitized);
              },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(_isDarkMode ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _accentColor.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 16, color: _accentColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '观看进度',
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            buildAdjustButton(-1, Ionicons.remove),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _episodeController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: TextStyle(color: _textColor, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  filled: true,
                  fillColor: _panelAltColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _accentColor),
                  ),
                ),
                onChanged: (value) {
                  if (value.isEmpty) {
                    _updateEpisodeStatus(0);
                    return;
                  }
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    final int sanitized = parsed < 0
                        ? 0
                        : (parsed > maxValue ? maxValue : parsed);
                    _updateEpisodeStatus(sanitized);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            buildAdjustButton(1, Ionicons.add),
            if (hasTotal) ...[
              const SizedBox(width: 16),
              Expanded(
                child: fluent.FluentTheme(
                  data: fluent.FluentThemeData(
                    brightness: Theme.of(context).brightness,
                    accentColor: fluent.AccentColor.swatch({
                      'normal': _accentColor,
                      'default': _accentColor,
                    }),
                  ),
                  child: fluent.Slider(
                    value: _selectedEpisodeStatus.clamp(0, maxValue).toDouble(),
                    min: 0,
                    max: maxValue.toDouble(),
                    divisions: maxValue > 0 ? maxValue : null,
                    onChanged: _isSubmitting
                        ? null
                        : (value) => _updateEpisodeStatus(value.round()),
                    label: _selectedEpisodeStatus.toString(),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hasTotal
              ? '当前进度：$_selectedEpisodeStatus/$total 集'
              : '当前进度：$_selectedEpisodeStatus 集',
          style: TextStyle(color: _subTextColor, fontSize: 12),
        ),
      ],
    );
  }

  void _updateEpisodeStatus(int newValue) {
    final total = widget.totalEpisodes;
    final maxValue = total > 0 ? total : 999;
    final int clampedValue = newValue.clamp(0, maxValue);
    if (_selectedEpisodeStatus == clampedValue &&
        _episodeController.text == clampedValue.toString()) {
      return;
    }
    setState(() {
      _selectedEpisodeStatus = clampedValue;
      if (_episodeController.text != clampedValue.toString()) {
        _episodeController.text = clampedValue.toString();
      }
    });
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
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 4,
          maxLength: 200,
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
              borderSide: const BorderSide(color: _accentColor, width: 1.2),
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
            onPressed:
                _isSubmitting ? null : () => setState(() => _selectedRating = 0),
            style: _textButtonStyle(baseColor: _accentColor),
            child: const Text('清除评分'),
          ),
        const Spacer(),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          style: _textButtonStyle(),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed:
              _isSubmitting || _selectedRating == 0 ? null : _handleSubmit,
          style: _primaryButtonStyle(),
          child: _isSubmitting
              ? const SizedBox(
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
    if (_selectedCollectionType == 0) return;

    setState(() {
      _isSubmitting = true;
    });

    final result = BangumiCollectionSubmitResult(
      rating: _selectedRating,
      collectionType: _selectedCollectionType,
      comment: _commentController.text,
      episodeStatus: _selectedEpisodeStatus,
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
