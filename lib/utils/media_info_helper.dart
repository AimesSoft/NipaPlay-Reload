import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart';

class MediaInfoHelper {
  /// 分析并打印视频的媒体信息，特别是字幕轨道信息
  static void analyzeMediaInfo(MediaInfo mediaInfo) {
    try {
      // 打印基本媒体信息
      debugPrint('=== 视频媒体信息 ===');
      debugPrint('格式: ${mediaInfo.format ?? "未知"}');
      debugPrint('时长: ${_formatDuration(mediaInfo.duration)}');
      debugPrint('开始时间: ${_formatDuration(mediaInfo.startTime)}');
      debugPrint('比特率: ${mediaInfo.bitRate} bps');
      
      // 打印视频流数量
      final videoCount = mediaInfo.video?.length ?? 0;
      debugPrint('=== 视频轨道 (${videoCount}) ===');
      
      // 打印音频流数量
      final audioCount = mediaInfo.audio?.length ?? 0;
      debugPrint('=== 音频轨道 (${audioCount}) ===');
      
      // 打印字幕轨道信息
      final subtitleCount = mediaInfo.subtitle?.length ?? 0;
      //debugPrint('=== 字幕轨道 (${subtitleCount}) ===');
      
      if (subtitleCount > 0) {
        for (var i = 0; i < subtitleCount; i++) {
          final track = mediaInfo.subtitle![i];
          //debugPrint('字幕轨道 #$i:');
          //debugPrint('  编解码器: ${track.codec}');
          //debugPrint('  完整数据: ${track.toString()}');
          
          // 尝试更详细地解析codec信息
          try {
            // 解析codec字符串
            final codecString = track.codec.toString();
            final parts = codecString.split(',');
            
            if (parts.length > 1) {
              // 解析codec属性
              for (final part in parts) {
                final trimmed = part.trim();
                //debugPrint('  属性: $trimmed');
              }
            }
            
            // 检查是否有附加属性的getter
            final instance = track;
            final properties = ['description', 'index', 'id', 'title', 'language', 'extraData'];
            
            // 使用runtimeType查看对象类型
            //debugPrint('  类型: ${instance.runtimeType}');
            
            // 打印原始对象字符串的所有部分
            final objectString = instance.toString();
            if (objectString.contains('(') && objectString.contains(')')) {
              final content = objectString.substring(
                objectString.indexOf('(') + 1,
                objectString.lastIndexOf(')')
              );
              final attributes = content.split(',');
              for (final attr in attributes) {
                final trimmed = attr.trim();
                if (trimmed.isNotEmpty) {
                  //debugPrint('  属性: $trimmed');
                }
              }
            }
          } catch (e) {
            //debugPrint('  无法获取更多字幕属性: $e');
          }
        }
      } else {
        //debugPrint('该视频没有字幕轨道');
      }
      
      // 打印章节信息
      final chapterCount = mediaInfo.chapters?.length ?? 0;
      debugPrint('=== 章节信息 (${chapterCount}) ===');
      
      // 尝试识别字幕语言
      identifySubtitleLanguages(mediaInfo);
      
    } catch (e) {
      debugPrint('分析媒体信息时出错: $e');
    }
  }
  
  /// 格式化毫秒为时:分:秒.毫秒格式
  static String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final ms = duration.inMilliseconds.remainder(1000);
    
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }
  
  /// 尝试识别字幕轨道的语言
  static void identifySubtitleLanguages(MediaInfo mediaInfo) {
    final subtitleCount = mediaInfo.subtitle?.length ?? 0;
    if (subtitleCount == 0) return;
    
    debugPrint('=== 字幕轨道信息汇总 ===');
    
    // 语言代码映射
    final languageCodes = {
      'chi': '中文',
      'eng': '英文',
      'jpn': '日语',
      'kor': '韩语',
      'fra': '法语',
      'deu': '德语',
      'spa': '西班牙语',
      'ita': '意大利语',
      'rus': '俄语',
    };
    
    // 常见的语言标识符
    final languagePatterns = {
      r'chi|chs|zh|中文|简体|繁体|chi.*?simplified|chinese': '中文',
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
    };
    
    for (var i = 0; i < subtitleCount; i++) {
      final track = mediaInfo.subtitle![i];
      final fullString = track.toString();
      
      // 尝试从metadata中提取title和language信息
      String? detectedLanguage;
      String? subtitleTitle;
      
      // 从metadata中提取信息
      if (fullString.contains('metadata: {')) {
        final metadataStart = fullString.indexOf('metadata: {') + 'metadata: {'.length;
        final metadataEnd = fullString.indexOf('}', metadataStart);
        
        if (metadataEnd > metadataStart) {
          final metadataStr = fullString.substring(metadataStart, metadataEnd);
          
          // 提取language字段
          final languageMatch = RegExp(r'language: ([^,}]+)').firstMatch(metadataStr);
          if (languageMatch != null) {
            final langCode = languageMatch.group(1)?.trim();
            detectedLanguage = languageCodes[langCode] ?? langCode;
          }
          
          // 提取title字段
          final titleMatch = RegExp(r'title: ([^,}]+)').firstMatch(metadataStr);
          if (titleMatch != null) {
            subtitleTitle = titleMatch.group(1)?.trim();
          }
        }
      }
      
      // 如果metadata中没有language信息，尝试从字符串猜测
      if (detectedLanguage == null) {
        for (final entry in languagePatterns.entries) {
          final pattern = RegExp(entry.key, caseSensitive: false);
          if (pattern.hasMatch(fullString.toLowerCase())) {
            detectedLanguage = entry.value;
            break;
          }
        }
      }
      
      // 格式化输出
      final summary = StringBuffer('字幕轨道 #$i: ');
      
      if (subtitleTitle != null) {
        summary.write('[$subtitleTitle] ');
      }
      
      summary.write('语言: ${detectedLanguage ?? "未知"}, ');
      summary.write('编码: ${track.codec.toString().split(',').first.split('(').last.trim()}');
      
      //debugPrint(summary.toString());
    }
  }
} 