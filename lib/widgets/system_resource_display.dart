import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';

/// 系统资源显示组件
/// 用于在界面右上角显示当前CPU使用率、内存使用和帧率
class SystemResourceDisplay extends StatefulWidget {
  const SystemResourceDisplay({Key? key}) : super(key: key);

  @override
  State<SystemResourceDisplay> createState() => _SystemResourceDisplayState();
}

class _SystemResourceDisplayState extends State<SystemResourceDisplay> {
  // 用于定期刷新UI的计时器
  Timer? _refreshTimer;
  
  // 资源指标
  double _cpuUsage = 0.0;
  double _memoryUsageMB = 0.0;
  double _fps = 0.0;
  String _activeDecoder = "未知"; // 添加当前活跃的解码器
  String _mdkVersion = "未知"; // 添加MDK版本号
  
  @override
  void initState() {
    super.initState();
    
    // 只在桌面平台启用
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      _startUpdating();
    }
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  /// 开始定期更新资源信息
  void _startUpdating() {
    // 每0.5秒刷新一次UI
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          // 从SystemResourceMonitor获取最新数据
          _cpuUsage = SystemResourceMonitor().cpuUsage;
          _memoryUsageMB = SystemResourceMonitor().memoryUsageMB;
          _fps = SystemResourceMonitor().fps;
          _activeDecoder = SystemResourceMonitor().activeDecoder;
          _mdkVersion = SystemResourceMonitor().mdkVersion;
        });
      }
    });
  }
  
  /// 获取CPU使用率的颜色（根据负载程度变色）
  Color _getCpuColor() {
    if (_cpuUsage < 50) {
      return const Color.fromARGB(255, 113, 255, 117);
    } else if (_cpuUsage < 80) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
  
  /// 获取内存使用量的颜色
  Color _getMemoryColor() {
    if (_memoryUsageMB < 200) {
      return const Color.fromARGB(255, 111, 252, 116);
    } else if (_memoryUsageMB < 500) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
  
  /// 获取帧率的颜色
  Color _getFpsColor() {
    if (_fps >= 55) {
      return const Color.fromARGB(255, 112, 255, 117);
    } else if (_fps >= 30) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 仅在桌面平台显示
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return const SizedBox.shrink();
    }
    
    // 使用Consumer检查开发者选项中的设置
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        // 如果开发者选项设置为不显示，则返回空组件
        if (!devOptions.showSystemResources) {
          return const SizedBox.shrink();
        }
        
        // 否则显示系统资源信息（带毛玻璃效果）
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 253, 253, 253).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // CPU使用率
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.memory, size: 22, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${_cpuUsage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _getCpuColor(),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      
                      // 内存使用量
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sd_storage_outlined, size: 22, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${_memoryUsageMB.toStringAsFixed(1)}MB',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _getMemoryColor(),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      
                      // 帧率
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed, size: 22, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${_fps.toStringAsFixed(1)} FPS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _getFpsColor(),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  // 解码器和MDK版本信息
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 解码器信息
                      Flexible(
                        flex: 3,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.video_library, size: 18, color: Colors.white70),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _activeDecoder,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 分隔符
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Container(
                          height: 16,
                          width: 1,
                          color: Colors.white30,
                        ),
                      ),
                      
                      // MDK版本信息
                      Flexible(
                        flex: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.white70),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'MDK $_mdkVersion',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
} 