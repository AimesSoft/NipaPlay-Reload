# 5. 实战教程：添加一个“贡献者名单”页面

理论学完了，现在是动手实践的时候了！本章将通过一个完整的例子，手把手带你为 NipaPlay-Reload 添加一个全新的页面。

**我们的目标**: 创建一个名为“贡献者名单”的新页面，并在设置页面添加入口，点击后可以跳转到这个新页面。这个页面上会显示一份为项目做出贡献的人员列表。

我们将严格按照之前的流程，并重点展示如何与 Codex 高效协作。这里特别说明一下：**现在更符合实际的工作流，是让 Codex 直接在工作区里创建文件、修改现有文件、给出 diff，然后由你审查并验证，而不是让你手动复制粘贴整段代码。**

### 第 1 步：创建新分支

和之前一样，为我们的新功能创建一个描述清晰的分支。

```bash
git checkout -b feat/add-contributors-page
```

### 第 2 步：构思与规划 (与 Codex 对话)

在开始写代码之前，我们可以先和 Codex 沟通我们的想法，让它帮我们规划。

打开 VS Code，在 Codex 对话中描述需求，然后向它提问：

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
> 请直接在工作区里完成实现，不要只返回代码片段。请：
> - 在 `lib/themes/nipaplay/pages/settings/` 下创建 `contributors_page.dart`
> - 在 `lib/themes/nipaplay/pages/settings_page.dart` 增加入口
> - 如果发现依赖缺失，请明确告诉我需要补什么
> - 修改尽量小，并在完成后总结改了哪些文件、为什么这样改。”

Codex 会理解你的需求，并直接在工作区里修改文件。这比“先让助手生成整段代码，再手动搬运到编辑器里”更接近现在的真实协作方式。

### 第 3 步：审查 Codex 的改动，而不是手动粘贴

当 Codex 完成修改后，不要直接盲目接受。更推荐你做下面几件事：

1.  **看它改了哪些文件**:
    *   这次合理的结果通常是：
        *   新增 `lib/themes/nipaplay/pages/settings/contributors_page.dart`
        *   修改 `lib/themes/nipaplay/pages/settings_page.dart`
2.  **看 diff 是否足够小**:
    *   如果你只是想加一个页面入口，但 Codex 一口气改了很多无关文件，就应该让它收缩范围。
3.  **确认它没有“只给建议不落地”**:
    *   真正符合现在工作流的结果，是工作区里已经有了实际改动，而不是聊天框里一大段让你复制粘贴的代码。

一个合理的结果大概会长这样：

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

你不需要自己手动新建文件再把这些代码贴进去。更理想的方式是：**Codex 帮你把文件改好，你负责审查这些改动是否靠谱。**

### 第 4 步：处理依赖

Codex 可能会提醒我们用到了 `url_launcher` 库。这个项目当前已经依赖了它，所以通常不需要额外安装；如果你引入了新的第三方库，再去更新 `pubspec.yaml`。

1.  **先确认依赖是不是真的缺失**: 打开 `pubspec.yaml`，确认 `url_launcher` 是否已经存在；不要一看到提示就盲目添加。
2.  **只有在确实缺失时再安装**:
    ```bash
    flutter pub add url_launcher
    ```

### 第 5 步：如果第一次结果不理想，继续让 Codex 收敛修改

真实协作里，第一次结果不一定完美。如果你发现 Codex 的修改有点跑偏，可以继续这样约束它：

> “请只保留与贡献者页面有关的最小修改，不要顺手重构设置页。”

或者：

> “请解释你为什么修改了这两个文件，并确认没有改动其他主题页面。”

这一步很重要，因为好的协作不是“让 Codex 一次性全做完”，而是你逐步把它引导到更符合仓库风格的结果。

### 第 6 步：测试和格式化

1.  **先做静态检查**: 在提交前先运行：
    ```bash
    flutter analyze
    ```
2.  **运行应用**: 在终端运行 `flutter run`。
3.  **测试功能**: 导航到“设置”页面，你应该能看到新增的“贡献者名单”选项。点击它，应该能成功跳转到新页面。再点击页面上的任意一个贡献者，应该能用浏览器打开对应的 GitHub 链接。
4.  **格式化代码**: 在提交前，别忘了运行格式化命令。
    ```bash
    dart format .
    ```

### 第 7 步：提交和创建 Pull Request

所有功能都正常工作后，我们就可以提交代码了。

1.  **暂存相关修改**:
    ```bash
    git add lib/themes/nipaplay/pages/settings/contributors_page.dart
    git add lib/themes/nipaplay/pages/settings_page.dart
    ```
    如果这次修改还涉及 `pubspec.yaml` 或其他明确相关的文件，再把它们一并 `git add`。

2.  **提交**:
    ```bash
    git commit -m "feat: Add contributors page"
    ```

3.  **推送**:
    ```bash
    git push origin feat/add-contributors-page
    ```

4.  **创建 Pull Request**:
    去你的 GitHub Fork 仓库页面，点击 "Compare & pull request" 按钮，按照模板填写标题、改动说明、验证方式；如果页面有变化，尽量附上截图，然后提交。

## 总结

恭喜你！你刚刚独立（在 Codex 的帮助下）为项目添加了一个完整的新功能！

通过这个例子，你可以看到，即使你不完全理解每一行代码的细节，只要你能清晰地向 Codex 描述你的需求，并养成“限制改动范围 -> 看 diff -> 跑校验 -> 手动验证”的习惯，就能完成很多有意义的贡献。随着你做得越来越多，你对代码的理解也会自然而然地加深。

---

**⬅️ 上一篇: [4. 代码风格指南](04-Coding-Style.md)** | **➡️ 下一篇: [6. 常见问题解答 (FAQ)](06-FAQ.md)**
