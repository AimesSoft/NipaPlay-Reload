import 'package:flutter/material.dart';
import 'dart:ui';

class JellyfinSortOption {
  final String value;
  final String label;
  final String description;

  const JellyfinSortOption({
    required this.value,
    required this.label,
    required this.description,
  });
}

class JellyfinSortDialog extends StatefulWidget {
  final String currentSortBy;
  final String currentSortOrder;

  const JellyfinSortDialog({
    super.key,
    required this.currentSortBy,
    required this.currentSortOrder,
  });

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String currentSortBy,
    required String currentSortOrder,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => JellyfinSortDialog(
        currentSortBy: currentSortBy,
        currentSortOrder: currentSortOrder,
      ),
    );
  }

  @override
  State<JellyfinSortDialog> createState() => _JellyfinSortDialogState();
}

class _JellyfinSortDialogState extends State<JellyfinSortDialog> {
  late String _selectedSortBy;
  late String _selectedSortOrder;

  // 可用的排序选项
  static const List<JellyfinSortOption> _sortOptions = [
    JellyfinSortOption(
      value: 'DateCreated,SortName',
      label: '创建时间',
      description: '按文件创建时间排序',
    ),
    JellyfinSortOption(
      value: 'SortName',
      label: '名称',
      description: '按名称字母顺序排序',
    ),
    JellyfinSortOption(
      value: 'PremiereDate',
      label: '首播日期',
      description: '按首播日期排序',
    ),
    JellyfinSortOption(
      value: 'DatePlayed',
      label: '播放时间',
      description: '按最后播放时间排序',
    ),
    JellyfinSortOption(
      value: 'ProductionYear',
      label: '制作年份',
      description: '按制作年份排序',
    ),
    JellyfinSortOption(
      value: 'CommunityRating',
      label: '社区评分',
      description: '按社区评分排序',
    ),
    JellyfinSortOption(
      value: 'Runtime',
      label: '时长',
      description: '按视频时长排序',
    ),
    JellyfinSortOption(
      value: 'PlayCount',
      label: '播放次数',
      description: '按播放次数排序',
    ),
  ];

  static const List<Map<String, String>> _sortOrders = [
    {'value': 'Ascending', 'label': '升序'},
    {'value': 'Descending', 'label': '降序'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedSortBy = widget.currentSortBy;
    _selectedSortOrder = widget.currentSortOrder;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.9;
    final maxDialogWidth = 400.0;
    final finalWidth = dialogWidth > maxDialogWidth ? maxDialogWidth : dialogWidth;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: finalWidth,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.white.withValues(alpha: 0.05),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 标题
                  const Text(
                    'Jellyfin 排序设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // 排序方式选择
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '排序方式',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _sortOptions.length,
                      itemBuilder: (context, index) {
                        final option = _sortOptions[index];
                        final isSelected = _selectedSortBy == option.value;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected 
                                  ? Colors.lightBlueAccent 
                                  : Colors.white.withValues(alpha: 0.2),
                              width: isSelected ? 2 : 1,
                            ),
                            color: isSelected 
                                ? Colors.lightBlueAccent.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _selectedSortBy = option.value;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                                                      Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    color: isSelected ? Colors.lightBlueAccent : Colors.white70,
                                    size: 20,
                                  ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option.label,
                                            style: TextStyle(
                                              color: isSelected ? Colors.lightBlueAccent : Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            option.description,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.7),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // 排序顺序选择
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '排序顺序',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: _sortOrders.map((order) {
                      final isSelected = _selectedSortOrder == order['value'];
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected 
                                  ? Colors.lightBlueAccent 
                                  : Colors.white.withValues(alpha: 0.2),
                              width: isSelected ? 2 : 1,
                            ),
                            color: isSelected 
                                ? Colors.lightBlueAccent.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _selectedSortOrder = order['value']!;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    order['label']!,
                                    style: TextStyle(
                                      color: isSelected ? Colors.lightBlueAccent : Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // 按钮
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop({
                            'sortBy': _selectedSortBy,
                            'sortOrder': _selectedSortOrder,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlueAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          '应用',
                          style: TextStyle(fontWeight: FontWeight.w600),
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
    );
  }
} 