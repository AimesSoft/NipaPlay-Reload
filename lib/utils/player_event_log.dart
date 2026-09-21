import 'package:nipaplay/services/debug_log_service.dart';

/// 关键播放器事件的日志终端输出（release 构建同样记录）。
///
/// DebugLogService 会拦截 debugPrint，但内核/弹幕引擎选择、Erika 自愈等
/// 决策点用显式 INFO/WARN 级别写入，保证在日志终端可直接过滤定位，
/// 不受 kDebugMode / trace 开关门控影响。
void logPlayerEvent(
  String tag,
  String message, {
  String level = 'INFO',
}) {
  DebugLogService().addLog(message, level: level, tag: tag);
}
