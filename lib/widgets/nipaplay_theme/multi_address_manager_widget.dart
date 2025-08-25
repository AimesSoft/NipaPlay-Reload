import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/utils/url_name_generator.dart';

/// 多地址管理组件
class MultiAddressManagerWidget extends StatefulWidget {
  final List<ServerAddress> addresses;
  final String? currentAddressId;
  final Function(String url, String name) onAddAddress;
  final Function(String addressId) onRemoveAddress;
  final Function(String addressId) onSwitchAddress;
  final Function(String addressId, int priority)? onUpdatePriority;
  
  const MultiAddressManagerWidget({
    super.key,
    required this.addresses,
    this.currentAddressId,
    required this.onAddAddress,
    required this.onRemoveAddress,
    required this.onSwitchAddress,
    this.onUpdatePriority,
  });

  @override
  State<MultiAddressManagerWidget> createState() => _MultiAddressManagerWidgetState();
}

class _MultiAddressManagerWidgetState extends State<MultiAddressManagerWidget> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }
  
  Future<void> _showAddAddressDialog() async {
    _urlController.clear();
    _nameController.clear();
    
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        title: const Text('添加服务器地址', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '为同一服务器添加多个访问地址，系统会自动选择可用的地址连接。',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: '例如：http://192.168.1.100:8096',
                labelStyle: const TextStyle(color: Colors.white70),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '地址名称（可留空自动生成）',
                hintText: '例如：家庭网络、公网访问，或留空自动生成',
                labelStyle: const TextStyle(color: Colors.white70),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () {
            if (_urlController.text.trim().isNotEmpty) {
              final url = _urlController.text.trim();
              final name = UrlNameGenerator.generateAddressName(url, customName: _nameController.text.trim());
              
              Navigator.of(context).pop({
                'url': url,
                'name': name,
              });
            } else {
              BlurSnackBar.show(context, '请填写服务器地址');
            }
          },
          child: const Text('添加', style: TextStyle(color: Colors.blue)),
        ),
      ],
      ),
    );
    
    if (result != null) {
      widget.onAddAddress(result['url']!, result['name']!);
    }
  }
  
  Future<void> _confirmRemoveAddress(ServerAddress address) async {
    if (widget.addresses.length <= 1) {
      BlurSnackBar.show(context, '至少需要保留一个地址');
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        title: const Text('删除地址', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除地址 "${address.name}" 吗？\n${address.url}',
          style: const TextStyle(color: Colors.white70),
        ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
      ),
    );
    
    if (confirm == true) {
      widget.onRemoveAddress(address.id);
    }
  }

  Future<void> _showPriorityDialog(ServerAddress address) async {
    if (widget.onUpdatePriority == null) return;

    final TextEditingController priorityController = TextEditingController();
    priorityController.text = address.priority.toString();
    
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        title: const Text('设置优先级', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '地址: ${address.name}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'URL: ${address.url}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              '优先级（数字越小优先级越高）:',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 12),
            // 优先级输入框
            TextField(
              controller: priorityController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '输入0-99的数字，0为最高优先级',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '优先级说明:',
                    style: TextStyle(color: Colors.blue.withOpacity(0.9), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 0: 最高优先级（优先）\n• 1-3: 高优先级\n• 4-9: 中等优先级\n• 10+: 低优先级',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              priorityController.dispose();
              Navigator.of(context).pop();
            },
            child: const Text('取消', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final priorityText = priorityController.text.trim();
              final priority = int.tryParse(priorityText);
              
              if (priority == null) {
                BlurSnackBar.show(context, '请输入有效的数字');
                return;
              }
              
              if (priority < 0 || priority > 99) {
                BlurSnackBar.show(context, '优先级必须在0-99之间');
                return;
              }
              
              priorityController.dispose();
              Navigator.of(context).pop(priority);
            },
            child: const Text('确定', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
    
    if (result != null && result != address.priority) {
      widget.onUpdatePriority!(address.id, result);
    }
  }
  
  Widget _buildAddressStatus(ServerAddress address) {
    // 当前使用中的地址
    if (address.id == widget.currentAddressId) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 14),
            SizedBox(width: 4),
            Text('当前使用', style: TextStyle(color: Colors.green, fontSize: 12)),
          ],
        ),
      );
    }
    
    // 最近成功连接
    if (address.lastSuccessTime != null) {
      final timeDiff = DateTime.now().difference(address.lastSuccessTime!);
      String timeText;
      if (timeDiff.inMinutes < 1) {
        timeText = '刚刚';
      } else if (timeDiff.inHours < 1) {
        timeText = '${timeDiff.inMinutes}分钟前';
      } else if (timeDiff.inDays < 1) {
        timeText = '${timeDiff.inHours}小时前';
      } else {
        timeText = '${timeDiff.inDays}天前';
      }
      
      return Text(
        '上次成功: $timeText',
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
      );
    }
    
    // 连续失败
    if (address.failureCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '失败 ${address.failureCount} 次',
          style: const TextStyle(color: Colors.orange, fontSize: 12),
        ),
      );
    }
    
    // 未启用
    if (!address.isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '已禁用',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildPriorityBadge(ServerAddress address) {
    final lowestPriority = widget.addresses.map((a) => a.priority).reduce((a, b) => a < b ? a : b);
    final isHighestPriority = address.priority == lowestPriority;
    
    // 只有最高优先级（数字最小）的地址显示优先标记
    if (isHighestPriority && widget.addresses.length > 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '优先',
          style: TextStyle(color: Colors.blue, fontSize: 10),
        ),
      );
    }
    
    // 显示优先级数字（如果不是0且有多个地址）
    if (address.priority > 0 && widget.addresses.length > 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'P${address.priority}',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '服务器地址管理',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddAddressDialog,
              icon: const Icon(Icons.add, color: Colors.blue, size: 16),
              label: const Text('添加地址', style: TextStyle(color: Colors.blue)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: Colors.blue.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // 地址列表
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Builder(
            builder: (context) {
              // 按优先级排序地址列表
              final sortedAddresses = List<ServerAddress>.from(widget.addresses);
              sortedAddresses.sort((a, b) {
                // 当前使用的地址优先显示
                if (a.id == widget.currentAddressId && b.id != widget.currentAddressId) return -1;
                if (b.id == widget.currentAddressId && a.id != widget.currentAddressId) return 1;
                
                // 按优先级排序（数字越小优先级越高）
                return a.priority.compareTo(b.priority);
              });
              
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedAddresses.length,
                separatorBuilder: (context, index) => Divider(
                  color: Colors.white.withOpacity(0.1),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final address = sortedAddresses[index];
                  final isCurrent = address.id == widget.currentAddressId;
              
                  return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Row(
                  children: [
                    // 优先级标记
                    _buildPriorityBadge(address),
                    if (widget.addresses.length > 1) const SizedBox(width: 8),
                    Text(
                      address.name,
                      style: TextStyle(
                        color: isCurrent ? Colors.green : Colors.white,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildAddressStatus(address),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    address.url,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 优先级设置按钮
                    if (widget.onUpdatePriority != null && widget.addresses.length > 1)
                      IconButton(
                        icon: const Icon(Icons.tune, color: Colors.white70),
                        tooltip: '设置优先级',
                        onPressed: () => _showPriorityDialog(address),
                      ),
                    // 切换按钮
                    if (!isCurrent && address.isEnabled)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white70),
                        tooltip: '切换到此地址',
                        onPressed: () => widget.onSwitchAddress(address.id),
                      ),
                    // 删除按钮
                    if (widget.addresses.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red.withOpacity(0.7)),
                        tooltip: '删除地址',
                        onPressed: () => _confirmRemoveAddress(address),
                      ),
                  ],
                ),
                  );
                },
              );
            },
          ),
        ),
        
        // 提示信息
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.withOpacity(0.7), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '系统会自动选择最优地址连接。当一个地址无法连接时，会自动尝试其他地址。',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
