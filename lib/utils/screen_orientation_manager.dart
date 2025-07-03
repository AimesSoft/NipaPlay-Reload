import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'globals.dart' as globals;

class ScreenOrientationManager {
  static ScreenOrientationManager? _instance;
  static ScreenOrientationManager get instance => _instance ??= ScreenOrientationManager._();
  
  ScreenOrientationManager._();
  
  bool _isTransitioning = false;
  bool _initialWasLandscape = false; // 记录进入播放器时的初始屏幕方向
  bool _isTabletDevice = false; // 记录是否为平板设备（基于进入时的判断，固定不变）
  
  // 获取当前是否处于横屏状态
  bool get isLandscape {
    final window = WidgetsBinding.instance.window;
    final size = window.physicalSize / window.devicePixelRatio;
    return size.width > size.height;
  }
  
  // 是否正在转换中
  bool get isTransitioning => _isTransitioning;
  
  // 设置初始屏幕方向（进入播放器时调用）
  Future<void> setInitialOrientation() async {
    if (!globals.isPhone) return;
    
    // 记录当前的屏幕方向作为初始状态
    _initialWasLandscape = isLandscape;
    // 记录是否为平板设备（基于进入时的判断，固定不变）
    _isTabletDevice = globals.isTablet;
    
    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板设备：强制横屏并锁定
        await _setLandscapeOnly();
      } else {
        // 手机设备：设置为竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }
  
  // 播放视频时的屏幕方向设置
  Future<void> setVideoPlayingOrientation() async {
    if (!globals.isPhone) return;
    
    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板设备：已经是横屏，无需改变
        return;
      } else {
        // 手机设备：切换到横屏
        await _setLandscapeOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }
  
  // 停止播放视频时的屏幕方向设置
  Future<void> setVideoStoppedOrientation() async {
    if (!globals.isPhone) return;
    
    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板设备：恢复到初始屏幕方向
        if (_initialWasLandscape) {
          await _setLandscapeOnly();
        } else {
          await _setPortraitOnly();
        }
      } else {
        // 手机设备：切换回竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }
  
  // 重置播放器时的屏幕方向设置
  Future<void> resetOrientation() async {
    if (!globals.isPhone) return;
    
    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板设备：恢复到初始屏幕方向
        if (_initialWasLandscape) {
          await _setLandscapeOnly();
        } else {
          await _setPortraitOnly();
        }
      } else {
        // 手机设备：切换回竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }
  
  // 设置横屏并锁定
  Future<void> _setLandscapeOnly() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
      await Future.delayed(const Duration(milliseconds: 100));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      
      if (_isTabletDevice) {
        // 平板设备不自动隐藏系统UI，由全屏按钮控制
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        // 手机设备隐藏系统UI
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('设置横屏时出错: $e');
    }
  }
  
  // 设置竖屏并锁定
  Future<void> _setPortraitOnly() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
      await Future.delayed(const Duration(milliseconds: 100));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('设置竖屏时出错: $e');
    }
  }
  
  // 恢复自由旋转（不建议使用，除非特殊需求）
  Future<void> enableFreeRotation() async {
    if (!globals.isPhone) return;
    
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('恢复自由旋转时出错: $e');
    }
  }
} 