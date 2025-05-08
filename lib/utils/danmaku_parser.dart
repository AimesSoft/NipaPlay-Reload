import 'package:flutter/foundation.dart';

// Top-level function for parsing danmaku data in a background isolate
List<Map<String, dynamic>> parseDanmakuListInBackground(List<dynamic>? rawDanmakuList) {
  if (rawDanmakuList == null || rawDanmakuList.isEmpty) {
    return [];
  }
  try {
    // Ensure each element in the list is correctly cast to Map<String, dynamic>
    return List<Map<String, dynamic>>.from(
      rawDanmakuList
          .whereType<Map<dynamic, dynamic>>() // Filter out non-map items if any
          .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
    );
  } catch (e, s) {
    // It's good practice to log errors that happen in isolates
    debugPrint('Error parsing danmaku data in background isolate: $e\n$s');
    return []; // Return an empty list or handle error as appropriate
  }
} 