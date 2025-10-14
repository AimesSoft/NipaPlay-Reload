import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class BangumiCollectionSubmitResult {
  final int rating;
  final int collectionType;
  final String comment;
  final int episodeStatus;

  const BangumiCollectionSubmitResult({
    required this.rating,
    required this.collectionType,
    required this.comment,
    required this.episodeStatus,
  });
}

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
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭Bangumi收藏对话框',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) {
        return BangumiCollectionDialog(
          animeTitle: animeTitle,
          initialRating: initialRating,
          initialCollectionType: initialCollectionType,
          initialComment: initialComment,
          initialEpisodeStatus: initialEpisodeStatus,
          totalEpisodes: totalEpisodes,
          onSubmit: onSubmit,
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  @override
  State<BangumiCollectionDialog> createState() =>
      _BangumiCollectionDialogState();
}

class _BangumiCollectionDialogState extends State<BangumiCollectionDialog> {
  static const Color _accentColor = Color(0xFFEB4994);
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
    final enableBlur =
        context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: IntrinsicWidth(
        child: IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
            child: GlassmorphicContainer(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 16,
              blur: enableBlur ? 25 : 0,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.18),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.5),
                  Colors.white.withOpacity(0.15),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '编辑Bangumi评分',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: _accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.animeTitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 18),
                      _buildRatingSection(),
                      const SizedBox(height: 20),
                      _buildCollectionSection(),
                      const SizedBox(height: 20),
                      _buildEpisodeStatusSection(),
                      const SizedBox(height: 20),
                      _buildCommentInput(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '评分',
          style: TextStyle(
            color: Colors.white,
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_selectedRating > 0) ...[
                const SizedBox(height: 4),
                Text(
                  _ratingEvaluationMap[_selectedRating] ?? '',
                  style: TextStyle(
                    color: _accentColor.withOpacity(0.9),
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
                        ? Colors.yellow[600]?.withOpacity(0.3)
                        : Colors.white.withOpacity(0.08),
                    border: Border.all(
                      color: isActive
                          ? Colors.yellow[600]!
                          : Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isActive ? Ionicons.star : Ionicons.star_outline,
                    color: isActive
                        ? Colors.yellow[600]
                        : Colors.white.withOpacity(0.6),
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
                      ? _accentColor.withOpacity(0.3)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? _accentColor
                        : Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    '$rating',
                    style: TextStyle(
                      color: isSelected
                          ? _accentColor
                          : Colors.white.withOpacity(0.8),
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
        const Text(
          '收藏状态',
          style: TextStyle(
            color: Colors.white,
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
                      ? _accentColor.withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                  border: Border.all(
                    color: isSelected
                        ? _accentColor
                        : Colors.white.withOpacity(0.25),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? _accentColor
                        : Colors.white.withOpacity(0.85),
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
            color: _accentColor.withOpacity(0.15),
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
        const Text(
          '观看进度',
          style: TextStyle(
            color: Colors.white,
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
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.25)),
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _accentColor,
                    inactiveTrackColor: Colors.white.withOpacity(0.2),
                    thumbColor: _accentColor,
                    overlayColor: _accentColor.withOpacity(0.2),
                  ),
                  child: Slider(
                    value: _selectedEpisodeStatus.clamp(0, maxValue).toDouble(),
                    min: 0,
                    max: maxValue.toDouble(),
                    divisions: maxValue > 0 ? maxValue : null,
                    onChanged: (value) => _updateEpisodeStatus(value.round()),
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
          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
        const Text(
          '短评',
          style: TextStyle(
            color: Colors.white,
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
          style:
              const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          cursorColor: _accentColor,
          decoration: InputDecoration(
            counterStyle: const TextStyle(color: Colors.white54, fontSize: 11),
            hintText: '写下你的短评（可选）',
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
            filled: true,
            fillColor: Colors.black.withOpacity(0.2),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.25), width: 1),
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
          Expanded(
            child: TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _selectedRating = 0),
              child: const Text(
                '清除评分',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        if (_selectedRating > 0) const SizedBox(width: 8),
        Expanded(
          child: TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed:
                _isSubmitting || _selectedRating == 0 ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor.withOpacity(0.9),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '确定',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
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
