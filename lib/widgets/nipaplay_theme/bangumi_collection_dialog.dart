import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class BangumiCollectionSubmitResult {
  final int rating;
  final int collectionType;
  final String comment;

  const BangumiCollectionSubmitResult({
    required this.rating,
    required this.collectionType,
    required this.comment,
  });
}

class BangumiCollectionDialog extends StatefulWidget {
  final String animeTitle;
  final int initialRating;
  final int initialCollectionType;
  final String? initialComment;
  final Future<void> Function(BangumiCollectionSubmitResult result) onSubmit;

  const BangumiCollectionDialog({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    required this.initialCollectionType,
    this.initialComment,
    required this.onSubmit,
  });

  static Future<void> show({
    required BuildContext context,
    required String animeTitle,
    required int initialRating,
    required int initialCollectionType,
    String? initialComment,
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
  }

  @override
  void dispose() {
    _commentController.dispose();
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
                        '编辑Bangumi收藏',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
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
                      ? Colors.blue.withOpacity(0.3)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue
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
                          ? Colors.blue
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
          '观看进度',
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
                      ? Colors.blue.withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue
                        : Colors.white.withOpacity(0.25),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.blueAccent
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
          cursorColor: Colors.blueAccent,
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
              borderSide:
                  const BorderSide(color: Colors.blueAccent, width: 1.2),
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
              backgroundColor: Colors.blueAccent.withOpacity(0.85),
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
