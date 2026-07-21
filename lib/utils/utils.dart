
// lib/utils/utils.dart
// 工具函数


/// 解析时间戳字符串为 [Duration], 支持 "HH:MM:SS", "MM:SS" 和 "SS" 格式, 可带小数秒.
///
/// - 参数:
/// timestamp: 时间戳字符串, 例如 "01:23:45.678", "12:34", "56.789"
///
/// - 返回值:
/// 对应的 [Duration] 对象, 如果解析失败返回 null
Duration? parseTimestamp(String timestamp) {
  final value = timestamp.trim();
  if (value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.isEmpty || parts.length > 3) return null;

  final secondsPattern = RegExp(r'^\d+(?:\.\d{1,3})?$');
  if (!secondsPattern.hasMatch(parts.last)) return null;
  final seconds = double.tryParse(parts.last);
  if (seconds == null || !seconds.isFinite) return null;

  var hours = 0;
  var minutes = 0;
  if (parts.length >= 2) {
    minutes = int.tryParse(parts[parts.length - 2]) ?? -1;
    if (minutes < 0) return null;
  }
  if (parts.length == 3) {
    hours = int.tryParse(parts.first) ?? -1;
    if (hours < 0 || minutes >= 60) return null;
  }
  if (parts.length > 1 && seconds >= 60) return null;

  final totalMilliseconds = ((hours * 3600 + minutes * 60 + seconds) * 1000).round();
  return Duration(milliseconds: totalMilliseconds);
}