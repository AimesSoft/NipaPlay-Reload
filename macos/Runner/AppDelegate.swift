import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 直接创建全局引用
  var uploadMenuItem: NSMenuItem?
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    print("[AppDelegate] 应用启动")
    
    // 创建菜单
    createUploadMenu()
  }
  
  // 创建上传菜单项 - 直接启用
  private func createUploadMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    
    let customMenu = NSMenu(title: "播放器")
    let uploadItem = NSMenuItem(title: "上传视频", action: #selector(uploadVideo(_:)), keyEquivalent: "u")
    uploadItem.keyEquivalentModifierMask = [.command]
    uploadItem.target = self
    uploadItem.isEnabled = true // 直接启用
    
    customMenu.addItem(uploadItem)
    let mainItem = NSMenuItem()
    mainItem.submenu = customMenu
    mainMenu.addItem(mainItem)
    
    uploadMenuItem = uploadItem
    print("[AppDelegate] 菜单已创建并启用")
  }
  
  // 处理菜单点击，直接获取FlutterViewController并创建通道
  @objc func uploadVideo(_ sender: Any?) {
    print("[AppDelegate] 菜单点击: 上传视频")
    
    // 获取控制器和创建通道
    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController else {
      print("[AppDelegate] 错误: 无法获取Flutter控制器")
      showSimpleAlert(message: "应用尚未准备好，请稍后再试")
      return
    }
    
    // 立即创建通道
    let channel = FlutterMethodChannel(name: "custom_menu_channel", binaryMessenger: controller.engine.binaryMessenger)
    
    // 调用方法
    print("[AppDelegate] 调用uploadVideo方法")
    channel.invokeMethod("uploadVideo", arguments: nil) { result in
      if let error = result as? FlutterError {
        print("[AppDelegate] 调用失败: \(error.message ?? "未知错误")")
        self.showSimpleAlert(message: "操作失败: \(error.message ?? "未知错误")")
      }
      else {
        print("[AppDelegate] 调用成功")
      }
    }
  }
  
  // 简化的警告显示
  private func showSimpleAlert(message: String) {
    DispatchQueue.main.async {
      if let window = NSApp.mainWindow {
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: window, completionHandler: nil)
      }
    }
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
