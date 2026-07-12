import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoCommentDialog extends StatefulWidget {
  final String animeTitle;
  final int initialRating;
  final String? initialComment;
  final int collectionType;
  final Future<void> Function(BangumiCollectionSubmitResult result) onSubmit;

  const CupertinoCommentDialog({
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
    return CupertinoBottomSheet.show<void>(
      context: context,
      title: '编辑短评',
      heightRatio: 0.78,
      child: CupertinoCommentDialog(
        animeTitle: animeTitle,
        initialRating: initialRating,
        initialComment: initialComment,
        collectionType: collectionType,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<CupertinoCommentDialog> createState() => _CupertinoCommentDialogState();
}

class _CupertinoCommentDialogState extends State<CupertinoCommentDialog> {
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

  Color get _accentColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.systemPurple, context);
  Color get _textColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.label, context);
  Color get _subTextColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
  Color get _mutedTextColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.tertiaryLabel, context);
  Color get _borderColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
  Color get _fillColor => CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground, context);

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
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.animeTitle,
                style: TextStyle(
                  color: _subTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _buildRatingSection(),
              const SizedBox(height: 18),
              _buildCommentInput(),
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
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
                    color:
                        isActive ? _accentColor.withOpacity(0.12) : _fillColor,
                    border: Border.all(
                      color: isActive ? _accentColor : _borderColor,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isActive ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    color: isActive ? _accentColor : _mutedTextColor,
                    size: 18,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
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
                  color:
                      isSelected ? _accentColor.withOpacity(0.12) : _fillColor,
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
        CupertinoTextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 4,
          maxLength: 200,
          onTapOutside: (_) => _dismissKeyboard(),
          style: TextStyle(color: _textColor, fontSize: 13),
          cursorColor: _accentColor,
          placeholder: '写下你的短评（可选）',
          placeholderStyle: TextStyle(color: _mutedTextColor, fontSize: 13),
          decoration: BoxDecoration(
            color: _fillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderColor, width: 1),
          ),
          padding: const EdgeInsets.all(12),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (_selectedRating > 0)
          CupertinoButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() => _selectedRating = 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text('清除评分',
                style: TextStyle(color: _accentColor, fontSize: 14)),
          ),
        const Spacer(),
        CupertinoButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text('取消', style: TextStyle(color: _textColor, fontSize: 14)),
        ),
        const SizedBox(width: 4),
        CupertinoButton(
          onPressed:
              _isSubmitting || _selectedRating == 0 ? null : _handleSubmit,
          borderRadius: BorderRadius.circular(10),
          color: _accentColor,
          disabledColor: _accentColor.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CupertinoActivityIndicator(color: CupertinoColors.white),
                )
              : const Text(
                  '确定',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white),
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
