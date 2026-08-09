// lib/models/external_player_session/session.dart
// 外部播放器启动会话的公共接口

import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:flutter/foundation.dart';


/// 外部播放器启动后返回给调用方的公共会话接口
abstract interface class ExternalPlayerLaunchSession extends ChangeNotifier {

  ExternalPlayerType get type;

  String    get playerPath;
  String    get mediaPath;
  int       get processId;
  String?   get ipcPath;
  Duration  get duration;
  Duration? get position;
  bool?     get isPaused;
  double?   get fraction;
  bool      get isClosed;

  // 生命周期管理
  // ---------------------------------------------------------------------------
  Future<void> launch();    // 启动外部播放器
  void terminate(); // 终止外部播放器

  // 播放器操控相关
  // ---------------------------------------------------------------------------
  void togglePause();
  void seekToFraction(double fraction);
  bool seekToPosition(Duration target);

  // 弹幕操控相关
  // ---------------------------------------------------------------------------
  Future<bool> refreshDanmaku(DanmakuItemSet danmakuSet, DanmakuStyle style);
}
