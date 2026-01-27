import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:charset_converter/charset_converter.dart';

class SubtitleDecodeResult {
  final String text;
  final String encoding;

  const SubtitleDecodeResult({
    required this.text,
    required this.encoding,
  });
}

class SubtitleParseResult {
  final List<SubtitleEntry> entries;
  final SubtitleFormat format;
  final String encoding;

  const SubtitleParseResult({
    required this.entries,
    required this.format,
    required this.encoding,
  });
}

enum SubtitleFormat {
  ass,
  srt,
  subViewer,
  microdvd,
  unknown,
}

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
  static final RegExp _assEventHeaderPattern =
      RegExp(r'^\s*\[Events\]\s*$', multiLine: true);
  static final RegExp _assDialoguePattern =
      RegExp(r'^\s*Dialogue:', multiLine: true);
  static final RegExp _srtTimePattern = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})\s*-->\s*'
    r'(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})',
  );
  static final RegExp _subViewerTimePattern = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})\s*,\s*'
    r'(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})',
  );
  static final RegExp _microdvdPattern =
      RegExp(r'^\s*\{(\d+)\}\{(\d+)\}', multiLine: true);

  static const List<String> _fallbackEncodings = [
    'utf-16le',
    'utf-16be',
    'gb18030',
    'gbk',
    'big5',
    'shift_jis',
    'euc-kr',
    'windows-1252',
    'iso-8859-1',
  ];
  static const List<String> _iconvEncodings = [
    'BIG5',
    'GB18030',
    'GBK',
    'SHIFT_JIS',
    'EUC-KR',
    'UTF-16LE',
    'UTF-16BE',
  ];

  static Future<SubtitleDecodeResult?> decodeSubtitleFile(
      String filePath, {bool allowUnknownFormat = false}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return const SubtitleDecodeResult(text: '', encoding: 'utf-8');
      }

      final bomEncoding = _detectBomEncoding(bytes);
      if (bomEncoding != null) {
        final decoded = await _decodeWithEncoding(bytes, bomEncoding,
            stripBom: true);
        if (decoded != null) {
          return SubtitleDecodeResult(text: decoded, encoding: bomEncoding);
        }
      }

      try {
        final text = utf8.decode(bytes, allowMalformed: false);
        return SubtitleDecodeResult(text: text, encoding: 'utf-8');
      } catch (_) {}

      final looksBinary = _looksBinary(bytes);
      if (looksBinary && !_looksLikeUtf16(bytes)) {
        return null;
      }

      final encodingCandidates = _buildEncodingCandidates(filePath);
      for (final encoding in encodingCandidates) {
        final decoded = await _decodeWithEncoding(bytes, encoding);
        if (decoded == null) continue;
        final format = _detectFormat(decoded, filePath);
        if (_looksLikeText(decoded) &&
            (allowUnknownFormat || format != SubtitleFormat.unknown)) {
          return SubtitleDecodeResult(text: decoded, encoding: encoding);
        }
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final iconvCandidates = _buildIconvCandidates(filePath);
        for (final encoding in iconvCandidates) {
          final decoded = await _decodeWithIconv(filePath, encoding);
          if (decoded == null) continue;
          final format = _detectFormat(decoded, filePath);
          if (_looksLikeText(decoded) &&
              (allowUnknownFormat || format != SubtitleFormat.unknown)) {
            return SubtitleDecodeResult(text: decoded, encoding: encoding);
          }
        }
      }

      final latin1Text = latin1.decode(bytes, allowInvalid: true);
      final format = _detectFormat(latin1Text, filePath);
      if (_looksLikeText(latin1Text) &&
          (allowUnknownFormat || format != SubtitleFormat.unknown)) {
        return SubtitleDecodeResult(text: latin1Text, encoding: 'latin1');
      }
    } catch (e) {
      debugPrint('解析字幕文件出错: $e');
    }

    return null;
  }

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

  static List<SubtitleEntry> parseSrt(String content) {
    final entries = <SubtitleEntry>[];
    final blocks = content.split(RegExp(r'\r?\n\r?\n+'));

    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n'));
      if (lines.isEmpty) continue;

      int timeLineIndex = 0;
      if (lines.isNotEmpty && RegExp(r'^\s*\d+\s*$').hasMatch(lines[0])) {
        timeLineIndex = 1;
      }
      if (timeLineIndex >= lines.length) continue;

      final match = _srtTimePattern.firstMatch(lines[timeLineIndex]);
      if (match == null) continue;

      final startTimeMs = _parseTimeToMs(match.group(1) ?? '');
      final endTimeMs = _parseTimeToMs(match.group(2) ?? '');
      if (endTimeMs <= startTimeMs) continue;

      final contentLines = lines.sublist(timeLineIndex + 1);
      final text = contentLines.join('\n').trim();
      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        content: text,
      ));
    }

    entries.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    return entries;
  }

  static List<SubtitleEntry> parseSubViewer(String content) {
    final entries = <SubtitleEntry>[];
    final lines = LineSplitter.split(content).toList();

    int index = 0;
    while (index < lines.length) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        index++;
        continue;
      }

      final match = _subViewerTimePattern.firstMatch(line);
      if (match == null) {
        index++;
        continue;
      }

      final startTimeMs = _parseTimeToMs(match.group(1) ?? '');
      final endTimeMs = _parseTimeToMs(match.group(2) ?? '');
      index++;

      final buffer = <String>[];
      while (index < lines.length && lines[index].trim().isNotEmpty) {
        buffer.add(lines[index]);
        index++;
      }

      final text = buffer.join('\n').trim();
      if (text.isNotEmpty && endTimeMs > startTimeMs) {
        entries.add(SubtitleEntry(
          startTimeMs: startTimeMs,
          endTimeMs: endTimeMs,
          content: text,
        ));
      }
    }

    entries.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    return entries;
  }

  static List<SubtitleEntry> parseMicrodvd(String content,
      {double defaultFps = 23.976}) {
    final entries = <SubtitleEntry>[];
    final lines = LineSplitter.split(content);
    double? fps;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match =
          RegExp(r'^\{(\d+)\}\{(\d+)\}(.*)$').firstMatch(line);
      if (match == null) continue;

      final startFrame = int.tryParse(match.group(1) ?? '') ?? 0;
      final endFrame = int.tryParse(match.group(2) ?? '') ?? 0;
      final payload = (match.group(3) ?? '').trim();

      if ((startFrame == 0 && endFrame == 0) ||
          (startFrame == 1 && endFrame == 1)) {
        final parsedFps =
            double.tryParse(payload.replaceAll(',', '.'));
        if (parsedFps != null && parsedFps > 1) {
          fps = parsedFps;
          continue;
        }
      }

      final usedFps = fps ?? defaultFps;
      if (usedFps <= 0) continue;

      final startTimeMs = ((startFrame / usedFps) * 1000).round();
      final endTimeMs = ((endFrame / usedFps) * 1000).round();
      if (endTimeMs <= startTimeMs) continue;

      final text = payload
          .replaceAll('|', '\n')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .trim();
      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        content: text,
      ));
    }

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
    final normalized = timeStr.replaceAll(',', '.');
    List<String> parts = normalized.split(':');
    
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
  
  static SubtitleFormat _detectFormat(String content, String filePath) {
    if (_assEventHeaderPattern.hasMatch(content) ||
        _assDialoguePattern.hasMatch(content)) {
      return SubtitleFormat.ass;
    }
    if (_srtTimePattern.hasMatch(content)) {
      return SubtitleFormat.srt;
    }
    if (_subViewerTimePattern.hasMatch(content)) {
      return SubtitleFormat.subViewer;
    }
    if (_microdvdPattern.hasMatch(content)) {
      return SubtitleFormat.microdvd;
    }

    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.ass') || lowerPath.endsWith('.ssa')) {
      return SubtitleFormat.ass;
    }
    if (lowerPath.endsWith('.srt')) {
      return SubtitleFormat.srt;
    }

    return SubtitleFormat.unknown;
  }

  static List<String> _buildEncodingCandidates(String filePath) {
    final candidates = List<String>.from(_fallbackEncodings);
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.contains('big5') ||
        lowerPath.contains('繁体') ||
        lowerPath.contains('cht') ||
        lowerPath.contains('traditional')) {
      _promoteEncoding(candidates, 'big5');
    }

    if (lowerPath.contains('gbk') ||
        lowerPath.contains('gb2312') ||
        lowerPath.contains('gb18030') ||
        lowerPath.contains('简体') ||
        lowerPath.contains('chs')) {
      _promoteEncoding(candidates, 'gb18030');
      _promoteEncoding(candidates, 'gbk');
    }

    return candidates;
  }

  static List<String> _buildIconvCandidates(String filePath) {
    final candidates = List<String>.from(_iconvEncodings);
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.contains('big5') ||
        lowerPath.contains('繁体') ||
        lowerPath.contains('cht') ||
        lowerPath.contains('traditional')) {
      _promoteEncoding(candidates, 'BIG5');
    }

    if (lowerPath.contains('gbk') ||
        lowerPath.contains('gb2312') ||
        lowerPath.contains('gb18030') ||
        lowerPath.contains('简体') ||
        lowerPath.contains('chs')) {
      _promoteEncoding(candidates, 'GB18030');
      _promoteEncoding(candidates, 'GBK');
    }

    return candidates;
  }

  static void _promoteEncoding(List<String> candidates, String encoding) {
    final index = candidates.indexOf(encoding);
    if (index > 0) {
      candidates.removeAt(index);
      candidates.insert(0, encoding);
    }
  }

  // 直接从文件解析ASS字幕
  static Future<List<SubtitleEntry>> parseAssFile(String filePath) async {
    try {
      final decoded = await decodeSubtitleFile(filePath);
      if (decoded == null) {
        return [];
      }

      final format = _detectFormat(decoded.text, filePath);
      switch (format) {
        case SubtitleFormat.ass:
          return parseAss(decoded.text);
        case SubtitleFormat.srt:
          return parseSrt(decoded.text);
        case SubtitleFormat.subViewer:
          return parseSubViewer(decoded.text);
        case SubtitleFormat.microdvd:
          return parseMicrodvd(decoded.text);
        case SubtitleFormat.unknown:
          return [];
      }
    } catch (e) {
      debugPrint('解析字幕文件出错: $e');
      return [];
    }
  }

  static String? _detectBomEncoding(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16be';
    }
    return null;
  }

  static Future<String?> _decodeWithEncoding(
      Uint8List bytes, String encoding,
      {bool stripBom = false}) async {
    try {
      final data = stripBom ? bytes.sublist(encoding == 'utf-8' ? 3 : 2) : bytes;
      if (encoding == 'utf-8') {
        return utf8.decode(data, allowMalformed: false);
      }
      return await CharsetConverter.decode(encoding, data);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _decodeWithIconv(
      String filePath, String encoding) async {
    try {
      final result = await Process.run(
        'iconv',
        ['-f', encoding, '-t', 'utf-8', filePath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        return null;
      }
      final output = result.stdout;
      if (output is String && output.isNotEmpty) {
        return output;
      }
    } catch (_) {}
    return null;
  }

  static bool _looksBinary(Uint8List bytes) {
    if (bytes.isEmpty) return false;

    int zeroCount = 0;
    int controlCount = 0;
    for (final b in bytes) {
      if (b == 0) zeroCount++;
      if (b < 0x09 || (b > 0x0D && b < 0x20)) {
        controlCount++;
      }
    }

    final length = bytes.length;
    if (length == 0) return false;

    final zeroRatio = zeroCount / length;
    final controlRatio = controlCount / length;

    return zeroRatio > 0.1 || controlRatio > 0.3;
  }

  static bool _looksLikeUtf16(Uint8List bytes) {
    if (bytes.length < 4) return false;
    int evenZeros = 0;
    int oddZeros = 0;
    int evenCount = 0;
    int oddCount = 0;

    for (int i = 0; i < bytes.length; i++) {
      if (i.isEven) {
        evenCount++;
        if (bytes[i] == 0) evenZeros++;
      } else {
        oddCount++;
        if (bytes[i] == 0) oddZeros++;
      }
    }

    final evenRatio = evenCount == 0 ? 0 : evenZeros / evenCount;
    final oddRatio = oddCount == 0 ? 0 : oddZeros / oddCount;
    return evenRatio > 0.6 || oddRatio > 0.6;
  }

  static bool _looksLikeText(String text) {
    if (text.isEmpty) return true;
    final sample = text.length > 2048 ? text.substring(0, 2048) : text;
    int controlCount = 0;
    for (int i = 0; i < sample.length; i++) {
      final codeUnit = sample.codeUnitAt(i);
      if (codeUnit == 0xFFFD ||
          codeUnit < 0x09 ||
          (codeUnit > 0x0D && codeUnit < 0x20)) {
        controlCount++;
      }
    }
    return controlCount / sample.length < 0.05;
  }
}
