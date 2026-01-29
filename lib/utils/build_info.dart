export 'build_info_types.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import 'build_info_types.dart';

const String _buildInfoAssetPath = 'assets/build_info.json';
const String _notSet = '未注入';

Future<List<BuildInfoSection>> loadBuildInfoSections() async {
  final data = await _loadBuildInfoJson();
  return [
    BuildInfoSection(
      title: '构建信息',
      entries: [
        BuildInfoEntry('构建时间', _readBuildTime(data)),
        BuildInfoEntry('处理器', _readString(data, 'cpu')),
        BuildInfoEntry('内存', _readMemory(data)),
        BuildInfoEntry('操作系统', _readString(data, 'os')),
        BuildInfoEntry('架构', _readString(data, 'arch')),
      ],
    ),
  ];
}

Future<Map<String, dynamic>> _loadBuildInfoJson() async {
  try {
    final raw = await rootBundle.loadString(_buildInfoAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } catch (_) {}
  return <String, dynamic>{};
}

String _readBuildTime(Map<String, dynamic> data) {
  final direct = _readString(data, 'build_time', fallback: '');
  if (direct.isNotEmpty) {
    return direct;
  }
  final epochValue = data['build_time_epoch'];
  final epoch = _tryParseInt(epochValue);
  if (epoch != null && epoch > 0) {
    final milliseconds = epoch < 100000000000 ? epoch * 1000 : epoch;
    return _formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    );
  }
  return _notSet;
}

String _readMemory(Map<String, dynamic> data) {
  final bytes = _tryParseInt(data['memory_bytes']);
  if (bytes != null && bytes > 0) {
    return _formatBytes(bytes);
  }
  final fallback = _readString(data, 'memory', fallback: '');
  if (fallback.isNotEmpty) {
    return fallback;
  }
  return _notSet;
}

String _readString(
  Map<String, dynamic> data,
  String key, {
  String fallback = _notSet,
}) {
  final value = data[key];
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return fallback;
}

int? _tryParseInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String _formatBytes(int bytes) {
  const double kb = 1024;
  const double mb = kb * 1024;
  const double gb = mb * 1024;

  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _formatDateTime(DateTime time) {
  final utc = time.toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second UTC';
}
