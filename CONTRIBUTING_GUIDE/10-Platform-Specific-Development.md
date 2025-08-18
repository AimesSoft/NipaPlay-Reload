# 10. (进阶) 如何进行平台特定开发

NipaPlay-Reload 是一个跨平台应用，这意味着我们的代码需要能够优雅地处理不同操作系统（Windows, macOS, Linux, Android, iOS, Web）的特性和差异。本章将指导你如何编写平台特定的代码，以及如何只在特定设备上测试这些功能。

## 平台特定代码的核心技术

在 Flutter 中，我们有多种方法来处理平台差异。以下是项目中最常用的几种技术，从简单到复杂排序。

### 方法一：使用 `Platform` 类和 `kIsWeb`

这是最常用、最直接的方法，用于在运行时检查当前平台。

*   **对于原生平台 (PC/Mobile)**: Flutter 的 `dart:io` 库提供了一个 `Platform` 类，你可以通过它来判断当前的操作系统。
    *   `Platform.isWindows`
    *   `Platform.isMacOS`
    *   `Platform.isLinux`
    *   `Platform.isAndroid`
    *   `Platform.isIOS`

*   **对于 Web 平台**: 由于 `dart:io` 在 Web 环境中不可用，Flutter 提供了一个全局常量 `kIsWeb` (来自 `foundation.dart`) 来进行判断。

**代码示例**：假设我们要创建一个根据不同平台显示不同文本的 Widget。

```dart
import 'dart:io'; // 导入 Platform 类
import 'package:flutter/foundation.dart' show kIsWeb; // 导入 kIsWeb

Widget buildPlatformSpecificWidget() {
  String platformText;

  if (kIsWeb) {
    platformText = "你好，网页用户！";
  } else if (Platform.isWindows) {
    platformText = "你好，Windows 用户！";
  } else if (Platform.isAndroid) {
    platformText = "你好，安卓用户！";
  } else {
    platformText = "你好，其他平台的用户！";
  }

  return Text(platformText);
}
```

### 方法二：条件导入 (Conditional Import)

当你需要在一个文件中根据平台导入不同的依赖时，条件导入就派上用场了。一个典型的场景是，你的代码同时需要支持Web和原生平台，但其中一部分功能依赖于 `dart:io`（Web不支持）。

**工作原理**: 你可以创建一个主文件，然后根据条件导入两个不同的实现文件。

1.  **创建一个接口文件 (`*.dart`)**:
    ```dart
    // a_feature.dart
    abstract class Feature {
      void doSomething();
    }
    
    // 这个工厂方法会根据平台返回不同的实例
    Feature getFeature();
    ```
2.  **创建一个原生实现 (`*_io.dart`)**:
    ```dart
    // a_feature_io.dart
    import 'dart:io';
    import 'a_feature.dart';

    class FeatureIO implements Feature {
      @override
      void doSomething() {
        print("在原生平台上运行: ${Platform.operatingSystem}");
      }
    }

    Feature getFeature() => FeatureIO();
    ```
3.  **创建一个Web存根 (Stub) 实现 (`*_web.dart`)**:
    ```dart
    // a_feature_web.dart
    import 'a_feature.dart';

    class FeatureWeb implements Feature {
      @override
      void doSomething() {
        print("在Web平台上运行");
      }
    }

    Feature getFeature() => FeatureWeb();
    ```
4.  **在主文件中使用条件导入**:
    ```dart
    // main_logic.dart
    import 'a_feature.dart'
      if (dart.library.io) 'a_feature_io.dart' // 如果 dart:io 存在 (非Web)，则导入这个文件
      if (dart.library.html) 'a_feature_web.dart'; // 如果 dart:html 存在 (Web)，则导入这个文件

    void myAppLogic() {
      final feature = getFeature();
      feature.doSomething();
    }
    ```
    现在，当你调用 `myAppLogic()` 时，它会在原生平台上打印操作系统，在Web上打印另一条信息，而你的主逻辑代码完全不需要 `if/else` 判断。

### 方法三：平台通道 (Platform Channels) - 最高级

当你需要调用原生平台的 API（比如获取 Android 的电池电量、调用 Windows 的一个特定 DLL 文件）时，就需要使用平台通道。

这是一个更高级的主题，它涉及到在 Dart 代码和原生代码（Kotlin/Java for Android, Swift/Objective-C for iOS, C++ for Windows/Linux）之间传递消息。

由于其复杂性，我们建议只有在非常必要的情况下才使用此方法。如果你需要实现这样的功能，请参考 Flutter 官方文档关于 [平台通道](https://flutter.cn/docs/platform-integration/platform-channels) 的详细教程。

## 实战：只在 Windows 平台添加一个“检查NVIDIA显卡”的按钮

让我们通过一个实例，来练习如何在设置页面中添加一个仅限 Windows 的功能。

### 第 1 步：定位并修改UI

1.  打开设置页面文件，例如 `lib/pages/settings/player_settings_page.dart`。
2.  找到你想要添加按钮的位置，比如在解码器设置旁边。
3.  使用 `Platform.isWindows` 来决定是否构建这个按钮。

    ```dart
    import 'dart:io';
    // ... 其他导入

    class PlayerSettingsPage extends StatelessWidget {
      // ...
      @override
      Widget build(BuildContext context) {
        return Scaffold(
          // ...
          body: ListView(
            children: [
              // ... 其他设置项 ...

              // 只在 Windows 平台上构建这个 ListTile
              if (Platform.isWindows)
                ListTile(
                  title: const Text('检查 NVIDIA 显卡'),
                  subtitle: const Text('调用原生命令检查GPU信息'),
                  onTap: () {
                    // 在点击时调用我们的平台特定逻辑
                    _showNvidiaGpuStatus(context);
                  },
                ),

              // ... 其他设置项 ...
            ],
          ),
        );
      }
      
      // ...
    }
    ```

### 第 2 步：实现平台特定逻辑

现在我们来实现 `_showNvidiaGpuStatus` 方法。我们将复用项目中已有的 `_checkForNvidiaGpu` 逻辑。

1.  假设 `_checkForNvidiaGpu` 定义在 `lib/utils/decoder_manager.dart` 中，并且可以被外部访问。
2.  在你的 `player_settings_page.dart` 中，实现 `_showNvidiaGpuStatus` 方法。

    ```dart
    // (接上文)
    
    // 假设 DecoderManager 是可以获取的实例
    final decoderManager = DecoderManager(); 

    void _showNvidiaGpuStatus(BuildContext context) {
      // 再次确认是 Windows 平台
      if (!Platform.isWindows) {
        return;
      }
      
      final hasNvidia = decoderManager.checkForNvidiaGpu(); // 调用已有逻辑
      final message = hasNvidia ? '检测到 NVIDIA 显卡。' : '未检测到 NVIDIA 显卡。';
      
      // 显示一个弹窗来展示结果
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('显卡检测结果'),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('好的'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
    ```

### 第 3 步：在特定设备上测试

现在代码已经写好了，但如何确保它只在 Windows 上运行且表现正常？

1.  **选择目标设备**: 在你的代码编辑器（如 VS Code 或 Android Studio）的右下角，有一个设备选择器。
2.  **启动 Windows 应用**: 点击设备选择器，选择 “Windows (desktop)”。
3.  **运行**: 按下 `F5` 或点击运行按钮。Flutter 会将你的应用编译并作为一个原生的 Windows 应用启动。
4.  **测试功能**: 在运行起来的 Windows 应用中，导航到设置页面，你应该能看到“检查 NVIDIA 显卡”按钮。点击它，应该能看到弹窗结果。
5.  **在其他平台验证**: 之后，将目标设备切换到“Chrome (web)”或一个安卓模拟器，再次运行应用。在这些平台上，设置页面中**不应该**出现那个按钮。

通过这种方式，你就可以有效地开发和测试平台专属的功能了。

---

**⬅️ 上一篇: [9. (进阶) 如何添加新的弹幕内核](09-Adding-a-New-Danmaku-Kernel.md)** | **➡️ 下一篇: [11. 非代码贡献：同样重要！](11-Non-Coding-Contributions.md)**
