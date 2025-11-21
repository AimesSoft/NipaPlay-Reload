import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class RatingDialog extends StatefulWidget {
  final String animeTitle;
  final int initialRating; // 0-10, 0代表未评分
  final Function(int rating) onRatingSubmitted;

  const RatingDialog({
    super.key,
    required this.animeTitle,
    required this.initialRating,
    required this.onRatingSubmitted,
  });

  static Future<void> show({
    required BuildContext context,
    required String animeTitle,
    required int initialRating,
    required Function(int rating) onRatingSubmitted,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭评分对话框',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return RatingDialog(
          animeTitle: animeTitle,
          initialRating: initialRating,
          onRatingSubmitted: onRatingSubmitted,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  late int _selectedRating;
  bool _isSubmitting = false;

  // 评分到评价文本的映射
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

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: IntrinsicWidth(
        child: IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 320,
              maxWidth: 400,
            ),
            child: GlassmorphicContainer(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 15,
              blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.5),
                  Colors.white.withOpacity(0.2),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      '为番剧评分',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // 番剧名称
                    Text(
                      widget.animeTitle,
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    
                    // 当前选择的评分显示
                    Center(
                      child: Column(
                        children: [
                          Text(
                            _selectedRating > 0 ? '$_selectedRating 分' : '未评分',
                            locale:Locale("zh-Hans","zh"),
style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_selectedRating > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              _ratingEvaluationMap[_selectedRating] ?? '',
                              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // 星星评分选择器
                    Center(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(10, (index) {
                          final rating = index + 1;
                          final isSelected = rating <= _selectedRating;
                          
                          return GestureDetector(
                            onTap: () => setState(() => _selectedRating = rating),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Colors.yellow[600]?.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.1),
                                border: Border.all(
                                  color: isSelected 
                                      ? Colors.yellow[600]!
                                      : Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Icon(
                                  isSelected ? Ionicons.star : Ionicons.star_outline,
                                  color: isSelected 
                                      ? Colors.yellow[600]
                                      : Colors.white.withOpacity(0.6),
                                  size: 18,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 数字按钮
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
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: isSelected 
                                      ? Colors.blue
                                      : Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                  fontWeight: isSelected 
                                      ? FontWeight.bold 
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    
                    // 操作按钮
                    Row(
                      children: [
                        // 清除评分按钮
                        if (_selectedRating > 0)
                          Expanded(
                            child: TextButton(
                              onPressed: _isSubmitting 
                                  ? null 
                                  : () => setState(() => _selectedRating = 0),
                              child: Text(
                                '清除评分',
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        if (_selectedRating > 0) const SizedBox(width: 8),
                        
                        // 取消按钮
                        Expanded(
                          child: TextButton(
                            onPressed: _isSubmitting 
                                ? null 
                                : () => Navigator.of(context).pop(),
                            child: Text(
                              '取消',
                              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        
                        // 确定按钮
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting || _selectedRating == 0
                                ? null
                                : _submitRating,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.withOpacity(0.8),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
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
                                : Text(
                                    '确定',
                                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitRating() async {
    if (_selectedRating <= 0 || _isSubmitting) return;
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      await widget.onRatingSubmitted(_selectedRating);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 错误处理由调用方负责
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
} 