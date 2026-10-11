import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay_core/player_abstraction/abstract_player.dart' as core;
import 'package:nipaplay/player_abstraction/lazy_player_delegate.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';

/// 内核身份与鸭子类型探测定义在真实 adapter 上；Player 包装层必须穿透
/// LazyPlayerDelegate 读取，否则 Media Kit 会被当成"未知"内核——字幕设置
/// 菜单塌缩成仅字号（supportsFullSubtitleStyle 判断 'Media Kit'）、
/// applySubtitleStylePreference 内核守卫早退、MDK 编码修复路径失效。
class _FakeMediaKitDelegate extends Fake implements MediaKitPlayerAdapter {}

class _RealizedLazyDelegate extends LazyPlayerDelegate {
  _RealizedLazyDelegate() : super(PlayerFactory());

  @override
  core.AbstractPlayer? get realized => _FakeMediaKitDelegate();
}

class _UnrealizedLazyDelegate extends LazyPlayerDelegate {
  _UnrealizedLazyDelegate() : super(PlayerFactory());
}

void main() {
  test('kernel name sees through a materialized lazy delegate', () {
    final player = Player.withDelegate(_RealizedLazyDelegate());
    expect(player.getPlayerKernelName(), 'Media Kit');
  });

  test('kernel name stays inert while the lazy delegate is unrealized', () {
    final player = Player.withDelegate(_UnrealizedLazyDelegate());
    expect(player.getPlayerKernelName(), '未知');
  });
}
