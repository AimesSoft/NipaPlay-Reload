import 'package:flutter/foundation.dart';
import 'hotkey_service.dart';

/// 全局热键管理器
/// 
/// 专门负责禁用和启用全局热键，解决对话框等界面中快捷键冲突的问题
/// 使用堆栈式管理，支持多层嵌套的禁用/启用操作
class GlobalHotkeyManager {
  static final GlobalHotkeyManager _instance = GlobalHotkeyManager._internal();
  static GlobalHotkeyManager get instance => _instance;
  
  GlobalHotkeyManager._internal();
  
  // 禁用堆栈，记录禁用热键的组件
  final List<String> _disableStack = [];
  
  // 是否已经禁用
  bool _isDisabled = false;
  
  // 热键服务实例
  final HotkeyService _hotkeyService = HotkeyService();
  
  /// 禁用全局热键
  /// 
  /// [reason] 禁用原因，用于调试和堆栈管理
  /// 支持多层嵌套禁用，只有当所有禁用都被移除时，热键才会重新启用
  Future<void> disableGlobalHotkeys(String reason) async {
    debugPrint('[GlobalHotkeyManager] 请求禁用全局热键: $reason');
    
    // 添加到禁用堆栈
    _disableStack.add(reason);
    
    // 如果是第一次禁用，才真正注销热键
    if (!_isDisabled) {
      debugPrint('[GlobalHotkeyManager] 执行热键注销...');
      try {
        await _hotkeyService.unregisterHotkeys();
        _isDisabled = true;
        debugPrint('[GlobalHotkeyManager] 全局热键已禁用');
      } catch (e) {
        debugPrint('[GlobalHotkeyManager] 禁用全局热键失败: $e');
      }
    } else {
      debugPrint('[GlobalHotkeyManager] 热键已处于禁用状态，添加到堆栈');
    }
    
    debugPrint('[GlobalHotkeyManager] 当前禁用堆栈: $_disableStack');
  }
  
  /// 启用全局热键
  /// 
  /// [reason] 启用原因，必须与之前的禁用原因匹配
  /// 只有当禁用堆栈为空时，热键才会真正启用
  Future<void> enableGlobalHotkeys(String reason) async {
    debugPrint('[GlobalHotkeyManager] 请求启用全局热键: $reason');
    
    // 从禁用堆栈中移除
    if (_disableStack.contains(reason)) {
      _disableStack.remove(reason);
      debugPrint('[GlobalHotkeyManager] 从禁用堆栈移除: $reason');
    } else {
      debugPrint('[GlobalHotkeyManager] 警告: 尝试移除不存在的禁用原因: $reason');
    }
    
    // 只有当堆栈为空时，才真正启用热键
    if (_disableStack.isEmpty && _isDisabled) {
      debugPrint('[GlobalHotkeyManager] 禁用堆栈为空，执行热键注册...');
      try {
        await _hotkeyService.registerHotkeys();
        _isDisabled = false;
        debugPrint('[GlobalHotkeyManager] 全局热键已启用');
      } catch (e) {
        debugPrint('[GlobalHotkeyManager] 启用全局热键失败: $e');
      }
    } else if (_disableStack.isNotEmpty) {
      debugPrint('[GlobalHotkeyManager] 禁用堆栈非空，保持热键禁用状态');
    }
    
    debugPrint('[GlobalHotkeyManager] 当前禁用堆栈: $_disableStack');
  }
  
  /// 强制启用全局热键
  /// 
  /// 清空所有禁用堆栈，强制启用热键
  /// 谨慎使用，主要用于错误恢复
  Future<void> forceEnableGlobalHotkeys([String reason = 'force_enable']) async {
    debugPrint('[GlobalHotkeyManager] 强制启用全局热键: $reason');
    
    _disableStack.clear();
    
    if (_isDisabled) {
      try {
        await _hotkeyService.registerHotkeys();
        _isDisabled = false;
        debugPrint('[GlobalHotkeyManager] 强制启用成功');
      } catch (e) {
        debugPrint('[GlobalHotkeyManager] 强制启用失败: $e');
      }
    }
  }
  
  /// 获取当前状态
  bool get isDisabled => _isDisabled;
  
  /// 获取禁用堆栈的副本
  List<String> get disableStack => List.unmodifiable(_disableStack);
  
  /// 检查是否有特定原因的禁用
  bool hasDisableReason(String reason) => _disableStack.contains(reason);
  
  /// 获取状态信息（用于调试）
  Map<String, dynamic> getDebugInfo() {
    return {
      'isDisabled': _isDisabled,
      'disableStackCount': _disableStack.length,
      'disableStack': _disableStack,
    };
  }
  
  /// 清理资源
  void dispose() {
    _disableStack.clear();
    _isDisabled = false;
  }
}

/// 全局热键管理器的便捷扩展
/// 
/// 提供更简洁的API
extension GlobalHotkeyManagerExtension on GlobalHotkeyManager {
  /// 临时禁用热键的便捷方法
  /// 
  /// 返回一个Future，当调用时会自动启用热键
  Future<VoidCallback> temporaryDisable(String reason) async {
    await disableGlobalHotkeys(reason);
    return () async {
      await enableGlobalHotkeys(reason);
    };
  }
}

/// 全局热键管理器的Mixin
/// 
/// 为需要管理热键的Widget提供便捷的混入
mixin GlobalHotkeyManagerMixin {
  String get hotkeyDisableReason;
  
  /// 禁用全局热键
  Future<void> disableHotkeys() async {
    await GlobalHotkeyManager.instance.disableGlobalHotkeys(hotkeyDisableReason);
  }
  
  /// 启用全局热键
  Future<void> enableHotkeys() async {
    await GlobalHotkeyManager.instance.enableGlobalHotkeys(hotkeyDisableReason);
  }
  
  /// 在dispose时自动启用热键
  void disposeHotkeys() {
    GlobalHotkeyManager.instance.enableGlobalHotkeys(hotkeyDisableReason);
  }
}
