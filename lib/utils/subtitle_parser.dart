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
    'cp950',
    'big5-hkscs',
    'shift_jis',
    'euc-kr',
    'windows-1252',
    'iso-8859-1',
  ];
  static const List<String> _iconvEncodings = [
    'BIG5',
    'CP950',
    'BIG5-HKSCS',
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

      String? utf8Text;
      try {
        utf8Text = utf8.decode(bytes, allowMalformed: false);
      } catch (_) {}
      if (utf8Text != null) {
        final format = _detectFormat(utf8Text, filePath);
        if (allowUnknownFormat || format != SubtitleFormat.unknown) {
          return SubtitleDecodeResult(text: utf8Text, encoding: 'utf-8');
        }
      }

      final detectedEncoding = await _detectEncodingWithUchardet(filePath);
      if (detectedEncoding != null) {
        final detectedResult = await _decodeWithDetectedEncoding(
          bytes,
          filePath,
          detectedEncoding,
          allowUnknownFormat: allowUnknownFormat,
        );
        if (detectedResult != null) {
          return detectedResult;
        }
      }

      SubtitleDecodeResult? best;
      double bestScore = double.negativeInfinity;

      void considerCandidate(String text, String encoding) {
        if (text.isEmpty) return;
        if (!_looksLikeText(text)) return;
        final format = _detectFormat(text, filePath);
        if (!allowUnknownFormat && format == SubtitleFormat.unknown) return;
        final score = _scoreDecodedText(text, filePath, encoding, format);
        if (score > bestScore) {
          bestScore = score;
          best = SubtitleDecodeResult(text: text, encoding: encoding);
        }
      }

      if (utf8Text != null) {
        considerCandidate(utf8Text, 'utf-8');
      }

      final looksBinary = _looksBinary(bytes);
      if (looksBinary && !_looksLikeUtf16(bytes)) {
        return null;
      }

      final looksUtf16 = _looksLikeUtf16(bytes);
      final encodingCandidates = _buildEncodingCandidates(filePath)
        ..removeWhere(
            (encoding) => _isUtf16Encoding(encoding) && !looksUtf16);
      for (final encoding in encodingCandidates) {
        final decoded = await _decodeWithEncoding(bytes, encoding);
        if (decoded == null) continue;
        considerCandidate(decoded, encoding);
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final iconvCandidates = _buildIconvCandidates(filePath)
          ..removeWhere((encoding) =>
              _isUtf16Encoding(encoding) && !looksUtf16);
        for (final encoding in iconvCandidates) {
          final decoded = await _decodeWithIconv(filePath, encoding);
          if (decoded == null) continue;
          considerCandidate(decoded, encoding);
        }
      }

      final latin1Text = latin1.decode(bytes, allowInvalid: true);
      considerCandidate(latin1Text, 'latin1');

      if (best != null) {
        return best;
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

  static SubtitleFormat detectFormat(String content, String filePath) {
    return _detectFormat(content, filePath);
  }

  static List<String> _buildEncodingCandidates(String filePath) {
    final candidates = List<String>.from(_fallbackEncodings);
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.contains('big5') ||
        lowerPath.contains('繁体') ||
        lowerPath.contains('cht') ||
        lowerPath.contains('traditional')) {
      _promoteEncoding(candidates, 'big5');
      _promoteEncoding(candidates, 'cp950');
      _promoteEncoding(candidates, 'big5-hkscs');
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
      _promoteEncoding(candidates, 'CP950');
      _promoteEncoding(candidates, 'BIG5-HKSCS');
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

  static double _scoreDecodedText(
      String text, String filePath, String encoding, SubtitleFormat format) {
    final sample = text.length > 8192 ? text.substring(0, 8192) : text;
    int total = 0;
    int cjkCount = 0;
    int asciiCount = 0;
    int replacementCount = 0;
    int controlCount = 0;
    int punctCount = 0;
    int latin1SupplementCount = 0;

    for (final rune in sample.runes) {
      total++;
      if (rune == 0xFFFD) {
        replacementCount++;
      }
      if (rune < 0x09 || (rune > 0x0D && rune < 0x20)) {
        controlCount++;
      }
      if (rune >= 0x20 && rune <= 0x7E) {
        asciiCount++;
      }
      if (rune >= 0x00A1 && rune <= 0x00FF) {
        latin1SupplementCount++;
      }
      if (_isCjkRune(rune)) {
        cjkCount++;
      }
      if (_isCjkPunctuation(rune)) {
        punctCount++;
      }
    }

    if (total == 0) return double.negativeInfinity;

    final totalDouble = total.toDouble();
    final cjkRatio = cjkCount / totalDouble;
    final asciiRatio = asciiCount / totalDouble;
    final replacementRatio = replacementCount / totalDouble;
    final controlRatio = controlCount / totalDouble;
    final punctRatio = punctCount / totalDouble;
    final latin1Ratio = latin1SupplementCount / totalDouble;

    double score = 0;
    if (format != SubtitleFormat.unknown) {
      score += 5;
    } else {
      score -= 2;
    }

    score += cjkRatio * 8;
    score += asciiRatio * 2;
    score += punctRatio * 2;
    score -= replacementRatio * 20;
    score -= controlRatio * 12;
    if (latin1Ratio > 0.08 && cjkRatio < 0.02) {
      score -= (latin1Ratio - 0.08) * 40;
    }
    if (encoding.toLowerCase() == 'latin1' &&
        latin1Ratio > 0.06 &&
        cjkRatio < 0.02) {
      score -= 8;
    }
    score += _scoreEncodingHint(filePath, encoding);

    return score;
  }

  static double _scoreEncodingHint(String filePath, String encoding) {
    final lowerPath = filePath.toLowerCase();
    final lowerEncoding = encoding.toLowerCase();
    double score = 0;

    if (lowerPath.contains('big5') ||
        lowerPath.contains('繁体') ||
        lowerPath.contains('cht') ||
        lowerPath.contains('traditional')) {
      if (lowerEncoding.contains('big5')) {
        score += 1.5;
      }
    }

    if (lowerPath.contains('gbk') ||
        lowerPath.contains('gb2312') ||
        lowerPath.contains('gb18030') ||
        lowerPath.contains('简体') ||
        lowerPath.contains('chs')) {
      if (lowerEncoding.contains('gb')) {
        score += 1.5;
      }
    }

    return score;
  }

  static bool _isCjkRune(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF);
  }

  static bool _isCjkPunctuation(int rune) {
    return (rune >= 0x3000 && rune <= 0x303F) ||
        (rune >= 0xFF00 && rune <= 0xFFEF) ||
        rune == 0x201C ||
        rune == 0x201D ||
        rune == 0x2018 ||
        rune == 0x2019;
  }

  // 直接从文件解析ASS字幕
  static Future<List<SubtitleEntry>> parseAssFile(String filePath) async {
    try {
      final result = await parseSubtitleFile(filePath);
      return result.entries;
    } catch (e) {
      debugPrint('解析字幕文件出错: $e');
      return [];
    }
  }

  static Future<SubtitleParseResult> parseSubtitleFile(String filePath,
      {bool allowUnknownFormat = false}) async {
    try {
      final decoded = await decodeSubtitleFile(
        filePath,
        allowUnknownFormat: allowUnknownFormat,
      );
      if (decoded == null) {
        return const SubtitleParseResult(
          entries: [],
          format: SubtitleFormat.unknown,
          encoding: 'unknown',
        );
      }

      final format = _detectFormat(decoded.text, filePath);
      List<SubtitleEntry> entries;
      switch (format) {
        case SubtitleFormat.ass:
          entries = parseAss(decoded.text);
          break;
        case SubtitleFormat.srt:
          entries = parseSrt(decoded.text);
          break;
        case SubtitleFormat.subViewer:
          entries = parseSubViewer(decoded.text);
          break;
        case SubtitleFormat.microdvd:
          entries = parseMicrodvd(decoded.text);
          break;
        case SubtitleFormat.unknown:
          entries = [];
          break;
      }

      return SubtitleParseResult(
        entries: entries,
        format: format,
        encoding: decoded.encoding,
      );
    } catch (e) {
      debugPrint('解析字幕文件出错: $e');
      return const SubtitleParseResult(
        entries: [],
        format: SubtitleFormat.unknown,
        encoding: 'unknown',
      );
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

  static Future<String?> _detectEncodingWithUchardet(
      String filePath) async {
    if (!(Platform.isMacOS || Platform.isLinux)) {
      return null;
    }

    const commands = [
      '/opt/homebrew/bin/uchardet',
      '/usr/local/bin/uchardet',
      'uchardet',
    ];

    for (final command in commands) {
      try {
        final result = await Process.run(
          command,
          [filePath],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        final output = result.stdout.toString().trim();
        if (output.isEmpty) continue;
        final normalized = _normalizeEncodingName(output);
        if (normalized != null) {
          return normalized;
        }
      } catch (_) {}
    }

    return null;
  }

  static String? _normalizeEncodingName(String rawEncoding) {
    final lower = rawEncoding.trim().toLowerCase();
    if (lower.isEmpty) return null;
    if (lower.contains('unknown') || lower.contains('binary')) {
      return null;
    }

    if (lower == 'ascii') return 'utf-8';
    if (lower.startsWith('utf-8')) return 'utf-8';
    if (lower == 'utf8') return 'utf-8';
    if (lower == 'utf-16le' || lower == 'utf16le') return 'utf-16le';
    if (lower == 'utf-16be' || lower == 'utf16be') return 'utf-16be';

    if (lower == 'big5' || lower == 'big-5') return 'big5';
    if (lower == 'big5-hkscs' || lower == 'big5hkscs') {
      return 'big5-hkscs';
    }
    if (lower == 'cp950' || lower == 'windows-950') return 'cp950';

    if (lower == 'gb18030') return 'gb18030';
    if (lower == 'gbk' || lower == 'cp936' || lower == 'windows-936') {
      return 'gbk';
    }
    if (lower == 'gb2312') return 'gb18030';

    if (lower == 'shift_jis' ||
        lower == 'shift-jis' ||
        lower == 'sjis' ||
        lower == 'windows-31j') {
      return 'shift_jis';
    }
    if (lower == 'euc-kr' || lower == 'euckr') return 'euc-kr';

    if (lower == 'iso-8859-1' ||
        lower == 'iso_8859-1' ||
        lower == 'latin1') {
      return 'iso-8859-1';
    }
    if (lower == 'windows-1252' || lower == 'cp1252') {
      return 'windows-1252';
    }

    return null;
  }

  static String? _toIconvEncoding(String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf-8':
        return 'UTF-8';
      case 'utf-16le':
        return 'UTF-16LE';
      case 'utf-16be':
        return 'UTF-16BE';
      case 'big5':
        return 'BIG5';
      case 'cp950':
        return 'CP950';
      case 'big5-hkscs':
        return 'BIG5-HKSCS';
      case 'gb18030':
        return 'GB18030';
      case 'gbk':
        return 'GBK';
      case 'shift_jis':
        return 'SHIFT_JIS';
      case 'euc-kr':
        return 'EUC-KR';
      case 'iso-8859-1':
        return 'ISO-8859-1';
      case 'windows-1252':
        return 'WINDOWS-1252';
    }
    return null;
  }

  static Future<SubtitleDecodeResult?> _decodeWithDetectedEncoding(
    Uint8List bytes,
    String filePath,
    String detectedEncoding, {
    bool allowUnknownFormat = false,
  }) async {
    final normalized =
        _normalizeEncodingName(detectedEncoding) ?? detectedEncoding;
    if (normalized.isEmpty) return null;
    if (_isUtf16Encoding(normalized) && !_looksLikeUtf16(bytes)) {
      return null;
    }

    String? decoded;
    final iconvEncoding = _toIconvEncoding(normalized);
    if (iconvEncoding != null && (Platform.isMacOS || Platform.isLinux)) {
      decoded = await _decodeWithIconv(filePath, iconvEncoding);
    }

    decoded ??= await _decodeWithEncoding(bytes, normalized);
    if (decoded == null || decoded.isEmpty) return null;
    if (!_looksLikeText(decoded)) return null;

    final format = _detectFormat(decoded, filePath);
    if (!allowUnknownFormat && format == SubtitleFormat.unknown) return null;

    return SubtitleDecodeResult(text: decoded, encoding: normalized);
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
    const commands = [
      '/usr/bin/iconv',
      '/opt/homebrew/opt/libiconv/bin/iconv',
      'iconv',
    ];
    for (final command in commands) {
      try {
        final result = await Process.run(
          command,
          ['-f', encoding, '-t', 'utf-8', filePath],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        final output = result.stdout;
        if (output is String && output.isNotEmpty) {
          return output;
        }
      } catch (_) {}
    }
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

  static bool _isUtf16Encoding(String encoding) {
    final lower = encoding.toLowerCase();
    return lower == 'utf-16le' || lower == 'utf-16be';
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
