import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';

class SubtitleEntry {
  final int startTimeMs;
  final int endTimeMs;
  final String content;
  final String style;
  final String layer;
  final String name;
  final String effect;

  SubtitleEntry({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.content,
    this.style = 'Default',
    this.layer = '0',
    this.name = '',
    this.effect = '',
  });

  String get formattedStartTime => _formatTime(startTimeMs);
  String get formattedEndTime => _formatTime(endTimeMs);

  String _formatTime(int timeMs) {
    final seconds = (timeMs / 1000).floor();
    final minutes = (seconds / 60).floor();
    final hours = (minutes / 60).floor();
    final milliseconds = timeMs % 1000;
    
    return '${hours.toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}.'
        '${milliseconds.toString().padLeft(3, '0')}';
  }
}

class SubtitleParser {
  static List<SubtitleEntry> parseAss(String content) {
    List<SubtitleEntry> entries = [];
    List<String> lines = LineSplitter.split(content).toList();
    
    bool isEventsSection = false;
    List<String> formatFields = [];
    
    for (String line in lines) {
      line = line.trim();
      
      // 检查是否进入Events部分
      if (line == '[Events]') {
        isEventsSection = true;
        continue;
      }
      
      // 如果不在Events部分，继续下一行
      if (!isEventsSection) continue;
      
      // 解析Format行
      if (line.startsWith('Format:')) {
        String formatLine = line.substring('Format:'.length).trim();
        formatFields = formatLine.split(',').map((e) => e.trim()).toList();
        continue;
      }
      
      // 解析Dialogue行
      if (line.startsWith('Dialogue:')) {
        String dialogueLine = line.substring('Dialogue:'.length).trim();
        
        // 先处理逗号内的引号问题，避免错误分割
        List<String> parts = _splitDialogueLine(dialogueLine);
        
        if (parts.length < formatFields.length) continue;
        
        // 将对话内容映射到format字段
        Map<String, String> dialogueMap = {};
        for (int i = 0; i < formatFields.length; i++) {
          dialogueMap[formatFields[i]] = parts[i];
        }
        
        // 解析开始和结束时间
        int startTimeMs = _parseTimeToMs(dialogueMap['Start'] ?? '0:00:00.00');
        int endTimeMs = _parseTimeToMs(dialogueMap['End'] ?? '0:00:00.00');
        
        // 提取文本内容（去除ASS标记）
        String content = dialogueMap['Text'] ?? '';
        content = _cleanAssText(content);
        
        // 创建字幕条目
        entries.add(SubtitleEntry(
          startTimeMs: startTimeMs,
          endTimeMs: endTimeMs,
          content: content,
          style: dialogueMap['Style'] ?? 'Default',
          layer: dialogueMap['Layer'] ?? '0',
          name: dialogueMap['Name'] ?? '',
          effect: dialogueMap['Effect'] ?? '',
        ));
      }
    }
    
    // 按开始时间排序
    entries.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    
    return entries;
  }
  
  // 特殊处理Dialogue行的分割，考虑文本中可能包含逗号的情况
  static List<String> _splitDialogueLine(String line) {
    List<String> result = [];
    
    // 前面的9个字段通常是固定的格式 (Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect)
    // 我们可以按逗号分割，但最后一个字段(Text)可能包含逗号和各种特殊字符
    
    int commaCount = 0;
    int lastCommaIndex = -1;
    
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ',' && commaCount < 8) { // 前8个逗号
        commaCount++;
        result.add(line.substring(lastCommaIndex + 1, i).trim());
        lastCommaIndex = i;
      }
    }
    
    // 添加第9个字段 (Effect)
    int nextCommaIndex = line.indexOf(',', lastCommaIndex + 1);
    if (nextCommaIndex != -1) {
      result.add(line.substring(lastCommaIndex + 1, nextCommaIndex).trim());
      
      // 添加最后一个字段 (Text)
      result.add(line.substring(nextCommaIndex + 1).trim());
    } else {
      // 如果没有找到第9个逗号，说明格式可能有问题
      result.add(line.substring(lastCommaIndex + 1).trim());
    }
    
    return result;
  }
  
  // 将时间字符串解析为毫秒数
  static int _parseTimeToMs(String timeStr) {
    // 格式: h:mm:ss.cs 或 h:mm:ss.ms
    List<String> parts = timeStr.split(':');
    
    if (parts.length != 3) return 0;
    
    int hours = int.tryParse(parts[0]) ?? 0;
    int minutes = int.tryParse(parts[1]) ?? 0;
    
    // 处理秒和毫秒
    List<String> secondsParts = parts[2].split('.');
    int seconds = int.tryParse(secondsParts[0]) ?? 0;
    
    int milliseconds = 0;
    if (secondsParts.length > 1) {
      String msStr = secondsParts[1];
      // ASS格式通常使用厘秒(cs)，1cs = 10ms
      if (msStr.length <= 2) {
        // 如果是厘秒
        milliseconds = (int.tryParse(msStr) ?? 0) * 10;
      } else {
        // 如果已经是毫秒
        milliseconds = int.tryParse(msStr) ?? 0;
      }
    }
    
    return (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
  }
  
  // 清理ASS文本中的样式标记
  static String _cleanAssText(String text) {
    // 移除 {\xxx} 格式的样式标记
    String result = text.replaceAll(RegExp(r'\{\\[^}]*\}'), '');
    
    // 根据需要添加更多清理，例如处理\N表示的换行
    result = result.replaceAll('\\N', '\n');
    
    return result;
  }
  
  // 直接从文件解析ASS字幕
  static Future<List<SubtitleEntry>> parseAssFile(String filePath) async {
    try {
      File file = File(filePath);
      if (!await file.exists()) {
        return [];
      }
      
      String content = await file.readAsString();
      return parseAss(content);
    } catch (e) {
      debugPrint('解析字幕文件出错: $e');
      return [];
    }
  }
} 