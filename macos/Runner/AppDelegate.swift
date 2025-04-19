import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var uploadChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    print("[AppDelegate] applicationDidFinishLaunching")
    waitForFlutterViewControllerAndInitChannel()
    // 添加自定义菜单，target 设为 self
    if let mainMenu = NSApp.mainMenu {
      let customMenu = NSMenu(title: "播放器")
      let uploadItem = NSMenuItem(title: "上传视频", action: #selector(AppDelegate.uploadVideo(_:)), keyEquivalent: "u")
      uploadItem.keyEquivalentModifierMask = [.command]
      uploadItem.target = self // target 设为 self
      customMenu.addItem(uploadItem)
      let mainItem = NSMenuItem()
      mainItem.submenu = customMenu
      mainMenu.addItem(mainItem)
      print("[AppDelegate] 自定义菜单已添加")
    }
  }

  func waitForFlutterViewControllerAndInitChannel() {
    if let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController {
      self.uploadChannel = FlutterMethodChannel(name: "custom_menu_channel", binaryMessenger: controller.engine.binaryMessenger)
      print("[AppDelegate] MethodChannel 已初始化 (检测到FlutterViewController)")
    } else {
      print("[AppDelegate] FlutterViewController 未就绪，100ms后重试")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.waitForFlutterViewControllerAndInitChannel()
      }
    }
  }

  @objc func uploadVideo(_ sender: Any?) {
    print("[AppDelegate] 菜单栏上传视频被点击")
    uploadChannel?.invokeMethod("uploadVideo", arguments: nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
