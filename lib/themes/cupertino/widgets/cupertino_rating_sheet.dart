import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoRatingSheet extends StatefulWidget {
  const CupertinoRatingSheet({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
  });

  final String animeTitle;
  final int initialRating;
  final bool isSubmitting;
  final Future<bool> Function(int rating) onSubmit;
  final VoidCallback onCancel;

  @override
  State<CupertinoRatingSheet> createState() => _CupertinoRatingSheetState();
}

class _CupertinoRatingSheetState extends State<CupertinoRatingSheet> {
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

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.initialRating.clamp(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    return Container(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: CupertinoScrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _buildRatingDisplay(context),
                    const SizedBox(height: 28),
                    _buildStarSelector(context),
                    const SizedBox(height: 20),
                    _buildNumberSelector(context),
                    const SizedBox(height: 24),
                    if (_selectedRating > 0)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: widget.isSubmitting
                            ? null
                            : () => setState(() => _selectedRating = 0),
                        child: const Text('清除评分'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '为番剧评分',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.animeTitle,
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: widget.isSubmitting || _selectedRating == 0
                ? null
                : _submitRating,
            child: widget.isSubmitting
                ? const CupertinoActivityIndicator(radius: 8)
                : const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingDisplay(BuildContext context) {
    final TextStyle primaryStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 32, fontWeight: FontWeight.bold);
    final TextStyle secondaryStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 14, color: CupertinoColors.secondaryLabel);

    return Column(
      children: [
        Text(
          _selectedRating > 0 ? '${_selectedRating}分' : '未评分',
          style: primaryStyle,
        ),
        const SizedBox(height: 6),
        Text(
          _selectedRating > 0
              ? (_ratingEvaluationMap[_selectedRating] ?? '')
              : '选择一个评分（1-10分）',
          style: secondaryStyle,
        ),
      ],
    );
  }

  Widget _buildStarSelector(BuildContext context) {
    final Color activeColor = CupertinoColors.systemYellow;
    final Color inactiveColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey4, context);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: List.generate(10, (index) {
        final rating = index + 1;
        final bool isSelected = rating <= _selectedRating;

        return GestureDetector(
          onTap: () => setState(() => _selectedRating = rating),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withOpacity(0.2)
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.systemFill,
                      context,
                    ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            child: Icon(
              isSelected ? CupertinoIcons.star_fill : CupertinoIcons.star,
              size: 18,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNumberSelector(BuildContext context) {
    final Color activeColor = CupertinoTheme.of(context).primaryColor;
    final Color borderColor =
        CupertinoDynamicColor.resolve(CupertinoColors.separator, context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(10, (index) {
        final rating = index + 1;
        final bool isSelected = rating == _selectedRating;

        return GestureDetector(
          onTap: () => setState(() => _selectedRating = rating),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withOpacity(0.15)
                  : CupertinoColors.systemBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? activeColor : borderColor,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                '$rating',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? activeColor : CupertinoColors.label,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _submitRating() async {
    if (_selectedRating <= 0 || widget.isSubmitting) {
      return;
    }
    final success = await widget.onSubmit(_selectedRating);
    if (success && mounted) {
      widget.onCancel();
    }
  }
}
