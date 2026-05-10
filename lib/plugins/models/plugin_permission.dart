enum PluginPermission {
  playerControl('player.control', '播放器控制', '允许控制播放器的播放、暂停、跳转等操作'),
  danmakuModify('danmaku.modify', '弹幕修改', '允许修改弹幕显示和过滤规则'),
  libraryRead('library.read', '媒体库读取', '允许读取媒体库信息'),
  libraryWrite('library.write', '媒体库写入', '允许修改媒体库内容'),
  uiDialog('ui.dialog', '弹窗显示', '允许显示弹窗和提示信息'),
  settingsRead('settings.read', '设置读取', '允许读取应用设置'),
  settingsModify('settings.modify', '设置修改', '允许修改应用设置'),
  storage('storage', '数据存储', '允许插件使用本地存储'),
  systemOverride('system.override', '系统覆盖', '允许覆盖系统级设置（如解锁下载器）');

  const PluginPermission(
    this.id,
    this.name,
    this.description,
  );

  final String id;
  final String name;
  final String description;

  static PluginPermission? fromId(String id) {
    for (final permission in values) {
      if (permission.id == id) {
        return permission;
      }
    }
    return null;
  }
}