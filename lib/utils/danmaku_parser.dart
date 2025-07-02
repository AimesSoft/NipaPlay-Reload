
// Top-level function for parsing danmaku data in a background isolate
List<Map<String, dynamic>> parseDanmakuListInBackground(List<dynamic>? rawDanmakuList) {
  if (rawDanmakuList == null || rawDanmakuList.isEmpty) {
    return [];
  }
  try {
    final List<Map<String, dynamic>> parsedDanmaku = [];
    
    for (final item in rawDanmakuList) {
      if (item is Map) {
        final Map<String, dynamic> danmakuItem = Map<String, dynamic>.from(item.cast<String, dynamic>());
        
        // 标准化弹幕数据格式
        final Map<String, dynamic> standardizedItem = {};
        
        // 处理时间字段 (t -> time)
        if (danmakuItem.containsKey('t')) {
          final timeValue = danmakuItem['t'];
          if (timeValue is num) {
            standardizedItem['time'] = timeValue.toDouble();
          } else if (timeValue is String) {
            standardizedItem['time'] = double.tryParse(timeValue) ?? 0.0;
          } else {
            standardizedItem['time'] = 0.0;
          }
        } else if (danmakuItem.containsKey('time')) {
          final timeValue = danmakuItem['time'];
          if (timeValue is num) {
            standardizedItem['time'] = timeValue.toDouble();
          } else if (timeValue is String) {
            standardizedItem['time'] = double.tryParse(timeValue) ?? 0.0;
          } else {
            standardizedItem['time'] = 0.0;
          }
        } else {
          standardizedItem['time'] = 0.0;
        }
        
        // 处理内容字段 (c -> content)
        if (danmakuItem.containsKey('c')) {
          standardizedItem['content'] = danmakuItem['c']?.toString() ?? '';
        } else if (danmakuItem.containsKey('content')) {
          standardizedItem['content'] = danmakuItem['content']?.toString() ?? '';
        } else {
          standardizedItem['content'] = '';
        }
        
        // 处理弹幕类型字段 (y -> type)
        if (danmakuItem.containsKey('y')) {
          final typeValue = danmakuItem['y']?.toString() ?? 'scroll';
          switch (typeValue.toLowerCase()) {
            case 'scroll':
            case 'right':
              standardizedItem['type'] = 'scroll';
              break;
            case 'top':
              standardizedItem['type'] = 'top';
              break;
            case 'bottom':
              standardizedItem['type'] = 'bottom';
              break;
            default:
              standardizedItem['type'] = 'scroll';
          }
        } else if (danmakuItem.containsKey('type')) {
          standardizedItem['type'] = danmakuItem['type']?.toString() ?? 'scroll';
        } else {
          standardizedItem['type'] = 'scroll';
        }
        
        // 处理颜色字段 (r -> color)
        if (danmakuItem.containsKey('r')) {
          standardizedItem['color'] = danmakuItem['r']?.toString() ?? 'rgb(255,255,255)';
        } else if (danmakuItem.containsKey('color')) {
          standardizedItem['color'] = danmakuItem['color']?.toString() ?? 'rgb(255,255,255)';
        } else {
          standardizedItem['color'] = 'rgb(255,255,255)';
        }
        
        // 保留其他原始字段
        for (final entry in danmakuItem.entries) {
          if (!['t', 'c', 'y', 'r', 'time', 'content', 'type', 'color'].contains(entry.key)) {
            standardizedItem[entry.key] = entry.value;
          }
        }
        
        // 只添加有效的弹幕数据（有内容且时间有效）
        if (standardizedItem['content'] != null && 
            standardizedItem['content'].toString().isNotEmpty &&
            standardizedItem['time'] != null && 
            standardizedItem['time'] >= 0) {
          parsedDanmaku.add(standardizedItem);
        }
      }
    }
    
    return parsedDanmaku;
  } catch (e) {
    // It's good practice to log errors that happen in isolates
    //debugPrint('Error parsing danmaku data in background isolate: $e');
    return []; // Return an empty list or handle error as appropriate
  }
} 