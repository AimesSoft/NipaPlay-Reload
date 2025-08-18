# 4. 代码风格指南

为了让 NipaPlay-Reload 的代码库保持整洁、可读和易于维护，我们约定了一些简单的代码风格规则。当你贡献代码时，请尽量遵守这些指南。

好消息是，你不需要手动记住所有规则。Flutter 自带了强大的工具来帮助我们自动格式化代码和检查问题。

## 首要原则：自动化工具优先

我们强烈依赖自动化工具来保证代码风格的一致性。

### 1. 使用 `flutter format`

在你提交代码之前，请务必在项目根目录运行以下命令：

```bash
flutter format .
```

这个命令会自动格式化你所有的 Dart 代码文件，使其符合官方推荐的风格。这包括处理缩进、空格、逗号等所有细节。

**与 AI 协作时的技巧**: 当 AI 生成了大量代码后，你可能会发现代码的格式有点乱。别担心，直接运行 `flutter format .`，所有问题都会迎刃而解。

### 2. 关注 `flutter analyze`

除了格式化，我们还使用静态分析工具来捕捉潜在的代码问题。运行以下命令：

```bash
flutter analyze
```

这个工具会检查你的代码，并报告任何警告或错误，比如未使用的变量、不符合规范的命名等。在提交 Pull Request 之前，请尽量确保这个命令没有报告任何新的问题。

## 核心编码约定

虽然自动化工具能解决大部分问题，但还有一些约定需要我们共同遵守。

### 1. 命名规范

清晰的命名是代码可读性的关键。

*   **文件名**: 使用 `snake_case` (小写字母和下划线)。例如：`user_profile_page.dart`。
*   **类名、枚举名**: 使用 `UpperCamelCase` (大驼峰命名法)。例如：`class UserProfile`。
*   **变量名、函数名、参数名**: 使用 `lowerCamelCase` (小驼峰命名法)。例如：`String userName`，`void getUserProfile()`。
*   **常量**: 使用 `lowerCamelCase`。例如：`const int maxRetryCount = 3`。

**示例**:
```dart
// 好例子
class UserProfilePage extends StatelessWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  Future<void> fetchUserData() async {
    // ...
  }
}

// 坏例子
class user_profile_page extends StatelessWidget { // 应该用 UpperCamelCase
  String User_Id; // 应该用 lowerCamelCase

  void Get_User_Data(){ // 应该用 lowerCamelCase
    // ...
  }
}
```

### 2. 注释

代码本身应该尽可能地自解释。但对于复杂的逻辑，注释是必要的。

*   **为什么这么做，而不是在做什么**: 好的注释解释的是代码背后的“为什么”，而不是简单地复述代码“在做什么”。
*   **使用 `//` 进行单行注释**。
*   **使用 `///` 为公共 API (类、函数) 编写文档注释**。

**示例**:
```dart
// 坏例子: 这个注释是多余的
// 增加计数器的值
counter++;

// 好例子: 解释了为什么需要这个检查
// 我们需要在这里检查用户是否为空，
// 因为用户数据可能在另一个异步操作中被清除了。
if (user != null) {
  // ...
}

/// 获取指定用户的个人资料。
///
/// 如果用户不存在，会抛出一个 [UserNotFoundException]。
Future<User> getUserById(String id) async {
  // ...
}
```

### 3. 代码结构

*   **保持函数短小**: 一个函数应该只做一件事情。如果一个函数过于庞大，考虑将它拆分成几个更小的、逻辑清晰的辅助函数。
*   **优先使用 `const`**: 如果一个变量或组件在编译时其值就是确定的，请务必使用 `const` 关键字。这有助于提升应用的性能。Flutter 的分析工具通常会提示你这样做。

## 让 AI 帮你遵守规范

当你使用 AI 生成代码时，可以主动提出要求，让它遵守我们的代码风格。

**示例提示**:

> “请帮我创建一个 Flutter 页面，用于显示用户列表。请确保所有变量和函数都使用 `lowerCamelCase` 命名，并为主要的类和函数添加文档注释。”

通过在提示中加入风格要求，你可以从一开始就获得更高质量、更符合项目规范的代码。

## 总结

遵守代码风格指南有助于我们共同维护一个健康的代码库。记住，最重要的两点是：

1.  在提交前运行 `flutter format .`。
2.  尽量解决 `flutter analyze` 报告的问题。

感谢你为保持 NipaPlay-Reload 代码的优雅和清晰所做的努力！

---

**⬅️ 上一篇: [3. 贡献代码的标准流程](03-How-To-Contribute.md)** | **➡️ 下一篇: [5. 实战教程：添加一个“贡献者名单”页面](05-Example-Add-A-New-Page.md)**
