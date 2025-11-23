import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';

class CupertinoBangumiCollectionSheet extends StatefulWidget {
  const CupertinoBangumiCollectionSheet({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    required this.initialCollectionType,
    required this.initialComment,
    required this.initialEpisodeStatus,
    required this.totalEpisodes,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
  });

  final String animeTitle;
  final int initialRating;
  final int initialCollectionType;
  final String? initialComment;
  final int initialEpisodeStatus;
  final int totalEpisodes;
  final bool isSubmitting;
  final Future<bool> Function(BangumiCollectionSubmitResult result) onSubmit;
  final VoidCallback onCancel;

  @override
  State<CupertinoBangumiCollectionSheet> createState() =>
      _CupertinoBangumiCollectionSheetState();
}

class _CupertinoBangumiCollectionSheetState
    extends State<CupertinoBangumiCollectionSheet> {
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
  late int _episodeStatus;
  bool _localSubmitting = false;

  bool get _isBusy => widget.isSubmitting || _localSubmitting;

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.initialRating.clamp(0, 10);
    final validTypes =
        _collectionOptions.map((option) => option['value'] as int).toSet();
    _selectedCollectionType = validTypes.contains(widget.initialCollectionType)
        ? widget.initialCollectionType
        : 3;
    _commentController =
        TextEditingController(text: widget.initialComment ?? '');
    _episodeStatus = widget.initialEpisodeStatus.clamp(
      0,
      widget.totalEpisodes > 0 ? widget.totalEpisodes : 999,
    );
    _episodeController =
        TextEditingController(text: _episodeStatus.toString());
  }

  @override
  void dispose() {
    _commentController.dispose();
    _episodeController.dispose();
    super.dispose();
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
                    _buildSectionCard(
                      context,
                      title: '评分',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRatingDisplay(context),
                          const SizedBox(height: 20),
                          _buildStarSelector(context),
                          const SizedBox(height: 20),
                          _buildNumberSelector(context),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      context,
                      title: '收藏状态',
                      child: _buildCollectionSelector(context),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      context,
                      title: '观看进度',
                      child: _buildEpisodeSelector(context),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      context,
                      title: '短评（可选）',
                      child: _buildCommentField(context),
                    ),
                    const SizedBox(height: 24),
                    _buildActionButtons(context),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '编辑Bangumi评分',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.animeTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final Color cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final TextStyle titleStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 14, fontWeight: FontWeight.w600);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildRatingDisplay(BuildContext context) {
    final TextStyle primaryStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 30, fontWeight: FontWeight.bold);
    final TextStyle secondaryStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 13, color: CupertinoColors.secondaryLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _selectedRating > 0 ? '${_selectedRating}分' : '未评分',
          style: primaryStyle,
        ),
        const SizedBox(height: 6),
        Text(
          _selectedRating > 0
              ? (_ratingEvaluationMap[_selectedRating] ?? '')
              : '请选择评分后再提交',
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
              ),
            ),
            child: Center(
              child: Text(
                '$rating',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isSelected ? activeColor : CupertinoColors.label,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCollectionSelector(BuildContext context) {
    final Color activeColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemBlue, context);
    final Color inactiveColor =
        CupertinoDynamicColor.resolve(CupertinoColors.separator, context);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _collectionOptions.map((option) {
        final int value = option['value'] as int;
        final String label = option['label'] as String;
        final bool isSelected = value == _selectedCollectionType;

        return GestureDetector(
          onTap: () => setState(() => _selectedCollectionType = value),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withOpacity(0.15)
                  : CupertinoColors.systemBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? activeColor : CupertinoColors.label,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEpisodeSelector(BuildContext context) {
    final Color iconColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color fillColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemFill, context);
    final int total = widget.totalEpisodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildStepperButton(
              context,
              icon: CupertinoIcons.minus,
              onPressed: () => _updateEpisodeStatus(_episodeStatus - 1),
            ),
            Expanded(
              child: CupertinoTextField(
                controller: _episodeController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed == null) {
                    _updateEpisodeStatus(0);
                  } else {
                    _updateEpisodeStatus(parsed);
                  }
                },
              ),
            ),
            _buildStepperButton(
              context,
              icon: CupertinoIcons.add,
              onPressed: () => _updateEpisodeStatus(_episodeStatus + 1),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          total > 0
              ? '共$total 集，当前$_episodeStatus 集'
              : '当前$_episodeStatus 集',
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel,
              ),
        ),
      ],
    );
  }

  Widget _buildStepperButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final Color iconColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 34,
        onPressed: _isBusy ? null : onPressed,
        child: Icon(icon, color: iconColor),
      ),
    );
  }

  Widget _buildCommentField(BuildContext context) {
    final Color fillColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemFill, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoTextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 4,
          placeholder: '写下你的短评（最多200字）',
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
          ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(200),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${_commentController.text.length}/200',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final bool disableSubmit = _selectedRating == 0 || _isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton.filled(
          onPressed: disableSubmit ? null : _handleSubmit,
          child: disableSubmit && _isBusy
              ? const CupertinoActivityIndicator()
              : const Text('保存更改'),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          onPressed: _isBusy ? null : widget.onCancel,
          child: const Text('取消'),
        ),
        if (_selectedRating > 0) ...[
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed:
                _isBusy ? null : () => setState(() => _selectedRating = 0),
            child: const Text('清除评分'),
          ),
        ],
      ],
    );
  }

  void _updateEpisodeStatus(int value) {
    final int maxEpisode = widget.totalEpisodes > 0 ? widget.totalEpisodes : 999;
    final int clamped = value.clamp(0, maxEpisode);
    if (_episodeStatus == clamped) {
      if (_episodeController.text != clamped.toString()) {
        _episodeController.text = clamped.toString();
      }
      return;
    }
    setState(() {
      _episodeStatus = clamped;
      if (_episodeController.text != clamped.toString()) {
        _episodeController.text = clamped.toString();
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (_selectedRating == 0 || _isBusy) {
      return;
    }
    setState(() {
      _localSubmitting = true;
    });

    final result = BangumiCollectionSubmitResult(
      rating: _selectedRating,
      collectionType: _selectedCollectionType,
      comment: _commentController.text,
      episodeStatus: _episodeStatus,
    );

    final success = await widget.onSubmit(result);

    if (!mounted) {
      return;
    }

    setState(() {
      _localSubmitting = false;
    });

    if (success) {
      widget.onCancel();
    }
  }
}
