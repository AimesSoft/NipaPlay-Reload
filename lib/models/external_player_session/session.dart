// lib/models/external_player_session/session.dart
// 外部播放器启动会话的公共接口

import 'package:nipaplay/constants/media_extensions.dart';
import 'package:flutter/foundation.dart';


/// 外部播放器启动后返回给调用方的公共会话接口
abstract interface class ExternalPlayerLaunchSession {

  ExternalPlayerType get type;

  String    get playerPath; // 外部播放器的可执行文件路径
  String    get mediaPath;  // 当前播放的媒体路径
  int       get processId;  // 外部播放器进程的 PID
  String?   get ipcPath;    // 外部播放器的 IPC 通信路径
  Duration  get duration;   // 外部播放器的总时长
  Duration? get position;   // 外部播放器的当前播放位置
  bool?     get isPaused;   // 外部播放器是否处于暂停状态
  double?   get fraction;   // 外部播放器的播放进度百分比
  bool      get isClosed;   // 外部播放器会话是否已关闭

  set duration(Duration  value); // 设置总时长
  set position(Duration? value); // 设置当前播放位置
  set isPaused(bool    ? value); // 设置是否处于暂停状态

  void terminate();
  void togglePause();
  void seekToFraction(double fraction);
  bool seekToPosition(Duration target);
  Future<bool> refreshDanmaku(String assPath, String luaPath);
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  void dispose();
}
