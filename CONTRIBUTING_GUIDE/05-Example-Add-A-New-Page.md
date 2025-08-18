# 5. 实战教程：添加一个“贡献者名单”页面

理论学完了，现在是动手实践的时候了！本章将通过一个完整的例子，手把手带你为 NipaPlay-Reload 添加一个全新的页面。

**我们的目标**: 创建一个名为“贡献者名单”的新页面，并在设置页面添加入口，点击后可以跳转到这个新页面。这个页面上会显示一份为项目做出贡献的人员列表。

我们将严格按照之前的流程，并重点展示如何与 AI 高效协作。

### 第 1 步：创建新分支

和之前一样，为我们的新功能创建一个描述清晰的分支。

```bash
git checkout -b feat/add-contributors-page
```

### 第 2 步：构思与规划 (与 AI 对话)

在开始写代码之前，我们可以先和 AI 沟通我们的想法，让它帮我们规划。

打开 Cursor，我们可以创建一个新的空白文件，或者在任意地方打开聊天窗口 (`Cmd/Ctrl + L`)，然后向 AI 提问：

> “你好，我正在为一个基于 Flutter 的项目 NipaPlay-Reload 贡献代码。我想添加一个名为‘贡献者名单’ (ContributorsPage) 的新页面。
>
> 页面要求如下：
> 1. 这是一个无状态的 `StatelessWidget`。
> 2. 页面顶部有一个标题，显示‘鸣谢’。
> 3. 页面主体是一个列表，用来显示贡献者的名字和他们的 GitHub 主页链接。
> 4. 现在，请先用一个硬编码的（写死的）贡献者列表作为示例数据，比如：
>    - 姓名: MCDFsteve, 链接: https://github.com/MCDFsteve
>    - 姓名: Contributor2, 链接: https://github.com/contributor2
> 5. 列表中的每一项都要美观，并且可以点击，点击后能在浏览器中打开对应的 GitHub 链接。
>
> 请帮我生成这个页面的完整 Dart 代码。请将代码放在一个名为 `contributors_page.dart` 的新文件里。另外，请使用 `url_launcher` 这个库来打开链接，如果代码中用到了，记得提醒我需要添加这个依赖。”

AI 会理解你的需求，并生成一份完整的代码文件。这比我们自己从零开始写要快得多。

### 第 3 步：创建文件并应用代码

1.  **创建文件**: 在 `lib/pages/settings/` 目录下，创建一个新文件，命名为 `contributors_page.dart`。
2.  **粘贴代码**: 将 AI 生成的代码完整地粘贴到这个新文件中。

AI 生成的代码可能类似这样：

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class Contributor {
  final String name;
  final String githubUrl;

  const Contributor({required this.name, required this.githubUrl});
}

class ContributorsPage extends StatelessWidget {
  const ContributorsPage({super.key});

  final List<Contributor> contributors = const [
    Contributor(name: 'MCDFsteve', githubUrl: 'https://github.com/MCDFsteve'),
    Contributor(name: 'Contributor2', githubUrl: 'https://github.com/contributor2'),
    // 在这里添加更多的贡献者
  ];

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('鸣谢'),
      ),
      body: ListView.builder(
        itemCount: contributors.length,
        itemBuilder: (context, index) {
          final contributor = contributors[index];
          return ListTile(
            title: Text(contributor.name),
            subtitle: Text(contributor.githubUrl),
            onTap: () => _launchURL(contributor.githubUrl),
            trailing: const Icon(Icons.open_in_new),
          );
        },
      ),
    );
  }
}
```

### 第 4 步：处理依赖

AI 提醒我们用到了 `url_launcher` 库。这是一个第三方库，需要先添加到项目中才能使用。

1.  **添加依赖**: 打开终端，运行以下命令：
    ```bash
    flutter pub add url_launcher
    ```
    这个命令会自动将 `url_launcher` 添加到你的 `pubspec.yaml` 文件中。

### 第 5 步：添加入口 (再次与 AI 协作)

新页面创建好了，但现在应用里还没有地方可以进入这个页面。我们需要在设置页面添加一个入口。

1.  **定位文件**: 打开 `lib/pages/settings/settings_page.dart` (或者类似的设置页面文件)。
2.  **向 AI 提问**: 选中整个文件的代码，按下 `Cmd/Ctrl + K`，然后输入：

    > “这是我的设置页面代码。请在‘关于’选项的旁边，添加一个新的列表项，文本是‘贡献者名单’。当用户点击这个列表项时，请导航到我们刚刚创建的 `ContributorsPage`。记得帮我导入 `contributors_page.dart` 文件。”

AI 会帮你找到合适的位置，并添加类似下面的代码：

```dart
// ... 在文件顶部，AI 会帮你添加导入语句
import 'contributors_page.dart';

// ... 在 build 方法的某个位置 ...
ListTile(
  leading: const Icon(Icons.people),
  title: const Text('贡献者名单'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ContributorsPage()),
    );
  },
),
ListTile( // 原有的“关于”选项
  leading: const Icon(Icons.info_outline),
  title: const Text('关于'),
  // ...
),
```

### 第 6 步：测试和格式化

1.  **运行应用**: 在终端运行 `flutter run`。
2.  **测试功能**: 导航到“设置”页面，你应该能看到新增的“贡献者名单”选项。点击它，应该能成功跳转到新页面。再点击页面上的任意一个贡献者，应该能用浏览器打开对应的 GitHub 链接。
3.  **格式化代码**: 在提交前，别忘了运行格式化命令。
    ```bash
    flutter format .
    ```

### 第 7 步：提交和创建 Pull Request

所有功能都正常工作后，我们就可以提交代码了。

1.  **暂存所有修改**:
    ```bash
    git add .
    ```
    (这里的 `.` 代表所有被修改过的文件)

2.  **提交**:
    ```bash
    git commit -m "feat: Add contributors page"
    ```

3.  **推送**:
    ```bash
    git push origin feat/add-contributors-page
    ```

4.  **创建 Pull Request**:
    去你的 GitHub Fork 仓库页面，点击 "Compare & pull request" 按钮，填写好标题和描述，然后提交。

## 总结

恭喜你！你刚刚独立（在 AI 的帮助下）为项目添加了一个完整的新功能！

通过这个例子，你可以看到，即使你不完全理解每一行代码的细节，只要你能清晰地向 AI 描述你的需求，就能完成很多有意义的贡献。随着你做得越来越多，你对代码的理解也会自然而然地加深。
