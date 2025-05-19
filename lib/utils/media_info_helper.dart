// import 'package:fvp/mdk.dart'; // Commented out old import
import '../../player_abstraction/player_abstraction.dart'; // <-- NEW IMPORT

class MediaInfoHelper {
  /// 分析并打印视频的媒体信息，特别是字幕轨道信息
  // The parameter type is now effectively PlayerMediaInfo due to the typedef in player_abstraction.dart
  static void analyzeMediaInfo(MediaInfo mediaInfo) { 
    try {
      // debugPrint('=== 视频媒体信息 ===');
      // debugPrint('格式: ${mediaInfo.format ?? "未知"}'); // PlayerMediaInfo doesn't have 'format' or 'startTime' or 'bitRate' directly
      // debugPrint('时长: ${_formatDuration(mediaInfo.duration)}'); // duration is fine
      // debugPrint('开始时间: ${_formatDuration(mediaInfo.startTime)}');
      // debugPrint('比特率: ${mediaInfo.bitRate} bps');
      
      final videoCount = mediaInfo.video?.length ?? 0;
      // debugPrint('=== 视频轨道 (${videoCount}) ===');
      
      // PlayerMediaInfo doesn't have 'audio' or 'chapters' directly yet.
      // final audioCount = mediaInfo.audio?.length ?? 0; 
      // debugPrint('=== 音频轨道 (${audioCount}) ===');
      
      final subtitleCount = mediaInfo.subtitle?.length ?? 0;
      // debugPrint('=== 字幕轨道 (${subtitleCount}) ===');
      
      if (subtitleCount > 0) {
        for (var i = 0; i < subtitleCount; i++) {
          final track = mediaInfo.subtitle![i]; // track is PlayerSubtitleStreamInfo
          // debugPrint('字幕轨道 #$i:');
          // PlayerSubtitleStreamInfo doesn't have a direct 'codec' field.
          // The raw representation is in track.rawRepresentation or its metadata.
          // debugPrint('  编解码器: ${track.codec}'); 
          // debugPrint('  完整数据: ${track.rawRepresentation}'); // This is good

          // The rest of the parsing logic might need adjustment based on track.rawRepresentation
          // or by accessing track.metadata or track.title, track.language
        }
      } else {
        // debugPrint('该视频没有字幕轨道');
      }
      
      // final chapterCount = mediaInfo.chapters?.length ?? 0;
      // debugPrint('=== 章节信息 (${chapterCount}) ===');
      
      identifySubtitleLanguages(mediaInfo);
      
    } catch (e) {
      // debugPrint('分析媒体信息时出错: $e');
    }
  }
  
  static String _formatDuration(int milliseconds) {
    // ... (this helper function is fine)
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final ms = duration.inMilliseconds.remainder(1000);
    
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }
  
  static void identifySubtitleLanguages(MediaInfo mediaInfo) {
    // ... (this logic needs to adapt to PlayerSubtitleStreamInfo)
    final subtitleCount = mediaInfo.subtitle?.length ?? 0;
    if (subtitleCount == 0) return;
    
    // debugPrint('=== 字幕轨道信息汇总 ===');
    
    final languageCodes = { /* ... */ };
    final languagePatterns = { /* ... */ };
    
    for (var i = 0; i < subtitleCount; i++) {
      final track = mediaInfo.subtitle![i]; // track is PlayerSubtitleStreamInfo
      // final fullString = track.rawRepresentation; // Use rawRepresentation or metadata
      String fullStringForGuessing = track.title ?? '';
      if (track.language != null && track.language != 'unknown') {
        fullStringForGuessing += ' ' + track.language!;
      }
      fullStringForGuessing += ' ' + track.metadata.toString();

      String? detectedLanguage = track.language;
      if (detectedLanguage == 'unknown') detectedLanguage = null;

      String? subtitleTitle = track.title;
      
      if (detectedLanguage == null) {
        for (final entry in languagePatterns.entries) {
          final pattern = RegExp(entry.key, caseSensitive: false);
          if (pattern.hasMatch(fullStringForGuessing.toLowerCase())) {
            detectedLanguage = entry.value;
            break;
          }
        }
      }
      
      final summary = StringBuffer('字幕轨道 #$i: ');
      if (subtitleTitle != null) {
        summary.write('[$subtitleTitle] ');
      }
      summary.write('语言: ${detectedLanguage ?? "未知"}, ');
      // PlayerSubtitleStreamInfo does not have a direct codec. This info might be in metadata or rawRepresentation.
      // For now, omitting codec info directly here as it was complex to parse before.
      // summary.write('编码: ${track.codec.toString().split(',').first.split('(').last.trim()}'); 
      // debugPrint(summary.toString());
    }
  }
} 