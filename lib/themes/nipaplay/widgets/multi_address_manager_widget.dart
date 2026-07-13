import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/url_name_generator.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

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
  State<MultiAddressManagerWidget> createState() =>
      _MultiAddressManagerWidgetState();
}

class _MultiAddressManagerWidgetState extends State<MultiAddressManagerWidget> {
  static Color get _accentColor => AppAccentColors.current;

  late List<ServerAddress> _sortedAddresses;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _panelColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
  @override
  void initState() {
    super.initState();
    _sortedAddresses =
        _sortedAddressList(widget.addresses, widget.currentAddressId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.addresses.isEmpty) {
        _showAddAddressDialog();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MultiAddressManagerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.addresses != widget.addresses ||
        oldWidget.currentAddressId != widget.currentAddressId) {
      _sortedAddresses =
          _sortedAddressList(widget.addresses, widget.currentAddressId);
    }
  }

  Future<void> _showAddAddressDialog() async {
    await BlurLoginDialog.show(
      context,
      title: '添加服务器地址',
      fields: const [
        LoginField(
          key: 'url',
          label: '服务器地址',
          hint: '例如：http://192.168.1.100:8096',
        ),
        LoginField(
          key: 'name',
          label: '地址名称（可留空自动生成）',
          hint: '例如：家庭网络、公网访问',
          required: false,
        ),
      ],
      loginButtonText: '添加',
      onLogin: (values) async {
        final url = values['url']?.trim() ?? '';
        if (url.isEmpty) {
          return const LoginResult(success: false, message: '请填写服务器地址');
        }
        final name = UrlNameGenerator.generateAddressName(
          url,
          customName: values['name']?.trim(),
        );
        await widget.onAddAddress(url, name);
        return const LoginResult(success: true);
      },
    );
  }

  Future<void> _confirmRemoveAddress(ServerAddress address) async {
    if (widget.addresses.length <= 1) {
      BlurSnackBar.show(context, '至少需要保留一个地址');
      return;
    }

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '删除地址',
      content: '确定要删除地址 "${address.name}" 吗？\n${address.url}',
      barrierDismissible: false,
      actions: [
        AdaptiveMediaActionButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(false),
          compact: true,
        ),
        AdaptiveMediaActionButton(
          label: '删除',
          onPressed: () => Navigator.of(context).pop(true),
          emphasis: AdaptiveMediaActionEmphasis.destructive,
          compact: true,
        ),
      ],
    );

    if (confirm == true) {
      widget.onRemoveAddress(address.id);
    }
  }

  Future<void> _showPriorityDialog(ServerAddress address) async {
    if (widget.onUpdatePriority == null) return;

    await BlurLoginDialog.show(
      context,
      title: '设置优先级',
      fields: [
        LoginField(
          key: 'priority',
          label: '优先级（0-99，数字越小越优先）',
          hint: '0 为最高优先级',
          initialValue: address.priority.toString(),
        ),
      ],
      loginButtonText: '确定',
      onLogin: (values) async {
        final priority = int.tryParse(values['priority']?.trim() ?? '');
        if (priority == null) {
          return const LoginResult(success: false, message: '请输入有效的数字');
        }
        if (priority < 0 || priority > 99) {
          return const LoginResult(
            success: false,
            message: '优先级必须在0-99之间',
          );
        }
        if (priority != address.priority) {
          await widget.onUpdatePriority!(address.id, priority);
        }
        return const LoginResult(success: true);
      },
    );
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
        style: TextStyle(color: _mutedTextColor, fontSize: 12),
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
          style: TextStyle(color: Colors.orange, fontSize: 12),
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
    final lowestPriority =
        widget.addresses.map((a) => a.priority).reduce((a, b) => a < b ? a : b);
    final isHighestPriority = address.priority == lowestPriority;

    // 只有最高优先级（数字最小）的地址显示优先标记
    if (isHighestPriority && widget.addresses.length > 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _accentColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '优先',
          style: TextStyle(color: _accentColor, fontSize: 10),
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
          style: TextStyle(color: _mutedTextColor, fontSize: 10),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  List<ServerAddress> _sortedAddressList(
      List<ServerAddress> addresses, String? currentId) {
    final sorted = List<ServerAddress>.from(addresses);
    sorted.sort((a, b) {
      if (a.id == currentId && b.id != currentId) return -1;
      if (b.id == currentId && a.id != currentId) return 1;
      return a.priority.compareTo(b.priority);
    });
    return sorted;
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
            Text(
              '服务器地址管理',
              style: TextStyle(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            AdaptiveMediaActionButton(
              label: '添加地址',
              onPressed: _showAddAddressDialog,
              desktopIcon: Icons.add,
              phoneIcon: cupertino.CupertinoIcons.add,
              compact: true,
            ),
          ],
        ),
        SizedBox(height: 12),

        // 地址列表
        Container(
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sortedAddresses.length,
            separatorBuilder: (context, index) => Divider(
              color: _borderColor,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final address = _sortedAddresses[index];
              final isCurrent = address.id == widget.currentAddressId;

              return AdaptiveMediaListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Row(
                  children: [
                    // 优先级标记
                    _buildPriorityBadge(address),
                    if (widget.addresses.length > 1) SizedBox(width: 8),
                    Text(
                      address.name,
                      style: TextStyle(
                        color: isCurrent ? Colors.green : _textColor,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    SizedBox(width: 8),
                    _buildAddressStatus(address),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    address.url,
                    style: TextStyle(
                      color: _mutedTextColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 优先级设置按钮
                    if (widget.onUpdatePriority != null &&
                        widget.addresses.length > 1)
                      AdaptiveMediaIconButton(
                        desktopIcon: Icons.tune,
                        phoneIcon: cupertino.CupertinoIcons.slider_horizontal_3,
                        tooltip: '设置优先级',
                        color: _subTextColor,
                        onPressed: () => _showPriorityDialog(address),
                      ),
                    // 切换按钮
                    if (!isCurrent && address.isEnabled)
                      AdaptiveMediaIconButton(
                        desktopIcon: Icons.swap_horiz,
                        phoneIcon:
                            cupertino.CupertinoIcons.arrow_right_arrow_left,
                        tooltip: '切换到此地址',
                        color: _subTextColor,
                        onPressed: () => widget.onSwitchAddress(address.id),
                      ),
                    // 删除按钮
                    if (widget.addresses.length > 1)
                      AdaptiveMediaIconButton(
                        desktopIcon: Icons.delete_outline,
                        phoneIcon: cupertino.CupertinoIcons.delete,
                        tooltip: '删除地址',
                        color: Colors.redAccent.withOpacity(0.8),
                        onPressed: () => _confirmRemoveAddress(address),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        // 提示信息
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accentColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: _accentColor.withOpacity(0.8), size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '系统会自动选择最优地址连接。当一个地址无法连接时，会自动尝试其他地址。',
                  style: TextStyle(color: _subTextColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
