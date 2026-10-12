import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'erika_nipa_adapter.dart';

/// TV 版内核：**仅 Erika**（用户要求，为控制安装包体积）。
///
/// 阶段一为 core 定义了统一 [NipaPlayer] 接口；TV 侧只实现并打包 Erika 一个内核，
/// media_kit(libmpv) / MDK / video_player 的适配器已从 TV 工程移除。
/// 若将来需要换内核，只需新增一个 [NipaPlayer] 实现并在此登记。
enum TvPlayerKernel {
  erika('Erika', 'Erika — 自研内核，支持 Android/tvOS/桌面/OHOS');

  const TvPlayerKernel(this.label, this.description);
  final String label;
  final String description;
}

/// TV 内核注册表（单内核版本，保留接口以便将来扩展）。
class TvPlayerKernelRegistry {
  TvPlayerKernelRegistry._();

  static const _prefKey = 'tv.player_kernel';

  static final Map<TvPlayerKernel, PlayerFactory> _factories = {
    TvPlayerKernel.erika: const ErikaNipaFactory(),
  };

  static NipaTargetPlatform get currentPlatform {
    if (Platform.isAndroid) return NipaTargetPlatform.android;
    if (Platform.isIOS) return NipaTargetPlatform.ios;
    if (Platform.isWindows) return NipaTargetPlatform.windows;
    if (Platform.isMacOS) return NipaTargetPlatform.macos;
    if (Platform.isLinux) return NipaTargetPlatform.linux;
    return NipaTargetPlatform.android;
  }

  static bool supports(TvPlayerKernel kernel, [NipaTargetPlatform? platform]) =>
      _factories[kernel]!.supportsPlatform(platform ?? currentPlatform);

  static List<TvPlayerKernel> available() =>
      TvPlayerKernel.values.where((k) => supports(k)).toList();

  static Future<TvPlayerKernel> loadSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    final match = TvPlayerKernel.values
        .where((k) => k.name == stored && supports(k))
        .toList();
    if (match.isNotEmpty) return match.first;
    return available().first;
  }

  static Future<void> saveSelected(TvPlayerKernel kernel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, kernel.name);
  }

  static NipaPlayer create(TvPlayerKernel kernel) =>
      _factories[kernel]!.create();
}

/// 统一渲染入口：core 的 [NipaPlayerSurface] 只是描述符，Widget 由 TV 侧构造。
Widget buildKernelSurface(TvPlayerKernel kernel, NipaPlayer player,
    {BoxFit fit = BoxFit.contain}) {
  return (player as ErikaNipaAdapter).buildSurface(fit: fit);
}

Duration kernelDuration(TvPlayerKernel kernel, NipaPlayer player) =>
    (player as ErikaNipaAdapter).duration;

bool kernelIsPlaying(TvPlayerKernel kernel, NipaPlayer player) =>
    (player as ErikaNipaAdapter).isPlaying;

/// 画面超分设置（仅 Erika 支持；其它内核 no-op）。
Future<void> kernelSetUpscaler(NipaPlayer player, String mode) async {
  await (player as ErikaNipaAdapter).setUpscaler(mode);
}

bool kernelIsInitialized(TvPlayerKernel kernel, NipaPlayer player) =>
    (player as ErikaNipaAdapter).isInitialized;
