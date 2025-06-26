import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 直接创建全局引用
  var uploadMenuItem: NSMenuItem?
  var mediaLibraryMenuItem: NSMenuItem?
  var newSeriesMenuItem: NSMenuItem?
  var settingsMenuItem: NSMenuItem?
  
  // 连接到xib中定义的菜单 - 使用不同名称避免与基类冲突
  @IBOutlet weak var playerMenu: NSMenu!
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    print("[AppDelegate] 应用启动")
    
    // 延迟更新菜单项，确保应用完全初始化
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.updateMenuItems()
    }
  }
  
  // 更新菜单项
  private func updateMenuItems() {
    print("[AppDelegate] 开始更新菜单项")
    
    // 直接使用已连接的playerMenu
    guard let menu = playerMenu else {
      print("[AppDelegate] 错误: playerMenu未连接")
      return
    }
    
    // 查找已有的上传视频菜单项
    var uploadItemExists = false
    for item in menu.items {
      if item.title == "上传视频" {
        uploadItemExists = true
        item.action = #selector(uploadVideo(_:))
        item.target = self
        uploadMenuItem = item
        break
      }
    }
    
    // 如果不存在，则添加上传视频菜单项
    if !uploadItemExists {
      let uploadItem = NSMenuItem(title: "上传视频", action: #selector(uploadVideo(_:)), keyEquivalent: "u")
      uploadItem.keyEquivalentModifierMask = [.command]
      uploadItem.target = self
      menu.addItem(uploadItem)
      uploadMenuItem = uploadItem
    }
    
    // 添加分隔线（如果不存在）
    var hasSeparator = false
    for (index, item) in menu.items.enumerated() {
      if item.isSeparatorItem && index > 0 {
        hasSeparator = true
        break
      }
    }
    
    if !hasSeparator {
      menu.addItem(NSMenuItem.separator())
    }
    
    // 添加或更新媒体库菜单项
    var hasMediaLibraryItem = false
    for item in menu.items {
      if item.title == "媒体库" {
        hasMediaLibraryItem = true
        item.action = #selector(openMediaLibrary(_:))
        item.target = self
        mediaLibraryMenuItem = item
        break
      }
    }
    
    if !hasMediaLibraryItem {
      let mediaLibraryItem = NSMenuItem(title: "媒体库", action: #selector(openMediaLibrary(_:)), keyEquivalent: "1")
      mediaLibraryItem.keyEquivalentModifierMask = [.command]
      mediaLibraryItem.target = self
      menu.addItem(mediaLibraryItem)
      mediaLibraryMenuItem = mediaLibraryItem
    }
    
    // 添加或更新新番更新菜单项
    var hasNewSeriesItem = false
    for item in menu.items {
      if item.title == "新番更新" {
        hasNewSeriesItem = true
        item.action = #selector(openNewSeries(_:))
        item.target = self
        newSeriesMenuItem = item
        break
      }
    }
    
    if !hasNewSeriesItem {
      let newSeriesItem = NSMenuItem(title: "新番更新", action: #selector(openNewSeries(_:)), keyEquivalent: "2")
      newSeriesItem.keyEquivalentModifierMask = [.command]
      newSeriesItem.target = self
      menu.addItem(newSeriesItem)
      newSeriesMenuItem = newSeriesItem
    }
    
    // 添加或更新设置菜单项
    var hasSettingsItem = false
    for item in menu.items {
      if item.title == "设置" {
        hasSettingsItem = true
        item.action = #selector(openSettings(_:))
        item.target = self
        settingsMenuItem = item
        break
      }
    }
    
    if !hasSettingsItem {
      let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings(_:)), keyEquivalent: "3")
      settingsItem.keyEquivalentModifierMask = [.command]
      settingsItem.target = self
      menu.addItem(settingsItem)
      settingsMenuItem = settingsItem
    }
    
    print("[AppDelegate] 菜单已更新: \(menu.items.count) 个项目")
  }
  
  // 处理菜单点击，直接获取FlutterViewController并创建通道
  @objc func uploadVideo(_ sender: Any?) {
    print("[AppDelegate] 菜单点击: 上传视频")
    invokeFlutterMethod("uploadVideo")
  }
  
  // 打开媒体库
  @objc func openMediaLibrary(_ sender: Any?) {
    print("[AppDelegate] 菜单点击: 媒体库")
    invokeFlutterMethod("openMediaLibrary")
  }
  
  // 打开新番更新
  @objc func openNewSeries(_ sender: Any?) {
    print("[AppDelegate] 菜单点击: 新番更新")
    invokeFlutterMethod("openNewSeries")
  }
  
  // 打开设置
  @objc func openSettings(_ sender: Any?) {
    print("[AppDelegate] 菜单点击: 设置")
    invokeFlutterMethod("openSettings")
  }
  
  // 封装调用Flutter方法的逻辑
  private func invokeFlutterMethod(_ method: String, arguments: Any? = nil) {
    // 获取控制器和创建通道
    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController else {
      print("[AppDelegate] 错误: 无法获取Flutter控制器")
      showSimpleAlert(message: "应用尚未准备好，请稍后再试")
      return
    }
    
    // 立即创建通道
    let channel = FlutterMethodChannel(name: "custom_menu_channel", binaryMessenger: controller.engine.binaryMessenger)
    
    // 调用方法
    print("[AppDelegate] 调用\(method)方法")
    channel.invokeMethod(method, arguments: arguments) { result in
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
  
  // 处理单个文件拖拽到Dock图标
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    print("[AppDelegate] 收到文件拖拽: \(filename)")
    handleOpenFile(filename)
    return true
  }
  
  // 处理多个文件拖拽到Dock图标
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    print("[AppDelegate] 收到多个文件拖拽: \(filenames)")
    // 处理第一个支持的视频文件
    for filename in filenames {
      if isSupportedVideoFile(filename) {
        handleOpenFile(filename)
        break
      }
    }
  }
  
  // 处理文件打开
  private func handleOpenFile(_ filename: String) {
    print("[AppDelegate] 处理文件: \(filename)")
    
    // 检查文件是否为支持的视频格式
    guard isSupportedVideoFile(filename) else {
      print("[AppDelegate] 不支持的文件格式: \(filename)")
      showSimpleAlert(message: "不支持的文件格式")
      return
    }
    
    // 如果应用未启动，保存文件路径供后续处理
    if !isFlutterReady() {
      print("[AppDelegate] Flutter未准备好，保存文件路径")
      pendingFilePath = filename
      
      // 延迟处理，等待Flutter初始化
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if let savedPath = self.pendingFilePath {
          self.sendFileToFlutter(savedPath)
          self.pendingFilePath = nil
        }
      }
    } else {
      sendFileToFlutter(filename)
    }
  }
  
  // 检查是否为支持的视频文件
  private func isSupportedVideoFile(_ filename: String) -> Bool {
    let supportedExtensions = ["mp4", "mkv", "avi", "mov", "webm", "wmv", "m4v", "3gp", "flv", "ts", "m2ts"]
    let fileExtension = (filename as NSString).pathExtension.lowercased()
    return supportedExtensions.contains(fileExtension)
  }
  
  // 检查Flutter是否准备好
  private func isFlutterReady() -> Bool {
    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return false
    }
    return controller.engine.binaryMessenger != nil
  }
  
  // 发送文件路径到Flutter
  private func sendFileToFlutter(_ filename: String) {
    print("[AppDelegate] 发送文件到Flutter: \(filename)")
    
    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController else {
      print("[AppDelegate] 错误: 无法获取Flutter控制器")
      return
    }
    
    let channel = FlutterMethodChannel(name: "drag_drop_channel", binaryMessenger: controller.engine.binaryMessenger)
    
    channel.invokeMethod("onFilesDropped", arguments: ["files": [filename]]) { result in
      if let error = result as? FlutterError {
        print("[AppDelegate] 发送文件到Flutter失败: \(error.message ?? "未知错误")")
      } else {
        print("[AppDelegate] 文件已发送到Flutter")
      }
    }
  }
  
  // 保存待处理的文件路径
  private var pendingFilePath: String?
}
