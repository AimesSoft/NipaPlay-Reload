# 3. 贡献代码的标准流程

现在，你已经准备好了一切，是时候开始动手贡献代码了！本章将详细介绍从开始修改到提交代码的完整流程。这个流程是开源社区的标准做法，掌握它对你未来参与任何开源项目都大有裨益。

我们将整个流程分为以下几个步骤：

0. Fork 仓库并克隆到本地（设置 upstream）
1. 创建并切换到一个新的分支 (Branch)
2. 编写代码（在 Codex 的帮助下）
3. 提交你的修改 (Commit)
4. 将你的分支推送到 GitHub (Push)
5. 创建一个拉取请求 (Pull Request)

听起来可能有点复杂，但别担心，我们会用一个具体的例子带你走完整个流程。

## 我们的任务：在“关于”页面添加你的名字

为了演示，我们来完成一个简单的任务：**在应用的“关于”页面里，加上一行“由 [你的名字] 贡献”的文本**。

### 第 0 步：Fork 并克隆仓库（一次性准备）

标准开源协作流程建议先 Fork 官方仓库到你的 GitHub 账号，然后克隆你的 Fork 到本地，并把官方仓库设置为 `upstream`：

1. 在 GitHub 上打开官方仓库：[AimesSoft/NipaPlay-Reload](https://github.com/AimesSoft/NipaPlay-Reload)
2. 点击右上角的 Fork，将其 Fork 到你的账号下。
3. 克隆你的 Fork 到本地，并进入项目目录：

    ```bash
    git clone https://github.com/<你的用户名>/NipaPlay-Reload.git
    cd NipaPlay-Reload
    ```

4. 添加官方仓库为上游（upstream）：

    ```bash
    git remote add upstream https://github.com/AimesSoft/NipaPlay-Reload.git
    git remote -v  # 可选：检查 remotes，通常 origin 指向你的 Fork，upstream 指向官方仓库
    ```

完成以上一次性准备后，后续开发都在你本地的这个仓库进行：`origin` 指你的 Fork，`upstream` 指官方仓库。

### 第 1 步：创建和切换分支

在动手修改代码之前，**永远不要直接在 `main` 或 `master` 分支上进行修改**。这是一个非常重要的原则。我们应该为每一个新功能或修复创建一个新的“分支”。

分支可以理解为代码库的一个独立副本，你在上面的修改不会影响到主干（`main` 分支）。

1. **确保你的本地代码是最新的**:
    在开始前，先从官方仓库同步最新的代码，确保你的 `main` 分支与 `upstream/main` 保持一致。

    ```bash
    # 首先，确保你在 main 分支
    git checkout main

    # 获取上游最新提交
    git fetch upstream

    # 将本地 main 同步到 upstream/main（二选一，推荐 rebase 保持线性历史）
    git rebase upstream/main
    # 或者
    # git merge upstream/main

    # 可选：把同步后的 main 推送回你的 Fork
    git push origin main
    ```

2. **创建新分支**:
    打开终端，在你的项目文件夹根目录下，运行以下命令：

    ```bash
    git checkout -b feat/add-contributor-name-to-about-page
    ```

    这条命令做了两件事：
    * `git checkout -b`: 创建一个新分支。
    * `feat/add-contributor-name-to-about-page`: 这是我们给新分支取的名字。一个好的分支名应该能清晰地描述这个分支是做什么的。

    现在，你已经在这个全新的分支上了，可以安全地进行修改了。

### 第 2 步：与 Codex 一起编写代码

现在，我们要找到“关于”页面的代码文件，并添加我们的文本。

1. **定位文件**:
    当前项目的设置页实现按主题组织。为了和下面的例子保持一致，我们先修改默认主题对应的关于页：`lib/themes/nipaplay/pages/settings/about_page.dart`。

2. **向 Codex 求助**:
    打开 `lib/themes/nipaplay/pages/settings/about_page.dart` 文件。现在，我们不需要自己去读懂所有代码。我们可以直接让 Codex 帮我们完成任务。
    在 VS Code 中打开 Codex 对话，把这个文件加入当前上下文，然后输入我们的需求：

    > “请在这个页面的 `build` 方法里，找到合适的位置，在应用版本号下面，添加一个 `Text` 组件，内容是‘由 [你的名字] 贡献’。请把 [你的名字] 替换成 MCDF。”

Codex 会分析代码，并在工作区里给出最小修改。一个合理的结果大概会像下面这样：

    ```dart
    // ... 原有的代码 ...
    Text('Version: ${packageInfo.version}'),
    const SizedBox(height: 8), // 可能会补一行间距
    const Text('由 MCDF 贡献'),
    // ... 其他原有代码 ...
    ```

3. **应用修改**:
    仔细看一下 Codex 的 diff，确认它只修改了目标文件、没有顺手改动无关内容；如果看起来没问题，再接受它。现在，你的代码就已经修改好了！

4. **运行和测试**:
    在终端里先运行 `flutter analyze`，确认静态检查没有明显问题；然后再运行 `flutter run`，启动应用，导航到“设置” -> “关于”页面，看看你的名字是不是已经显示在上面了。确认无误后，我们就可以进行下一步了。

### 第 3 步：提交你的修改 (Commit)

代码修改完成后，我们需要把它“提交”到我们本地的 Git 仓库里。Commit 可以理解为给你的代码拍一张快照，并附上一句说明。

1. **查看状态**:

    ```bash
    git status
    ```

    这个命令会告诉你哪些文件被修改了。你应该能看到 `lib/themes/nipaplay/pages/settings/about_page.dart` 出现在列表中。

2. **暂存文件**:

    ```bash
    git add lib/themes/nipaplay/pages/settings/about_page.dart
    ```

    这个命令告诉 Git，我们希望把这个文件的修改包含在下一次提交中。如果你修改了多个文件，可以多次使用 `git add`。

3. **提交**:

    ```bash
    git commit -m "feat: Add contributor name to about page"
    ```

    * `git commit`: 执行提交操作。
    * `-m`: 表示后面跟着的是提交信息。
    * `"feat: Add contributor name to about page"`: 这是提交信息，非常重要。一个好的提交信息应该清晰地描述这次提交做了什么。我们通常使用一种格式，比如 `feat:` 表示新增功能，`fix:` 表示修复 bug。
        >   更多有关提交信息的规范可以参考[约定式提交](https://www.conventionalcommits.org/zh-hans/v1.0.0/)

### 第 4 步：推送到 GitHub (Push)

现在，这个提交只存在于你的本地电脑上。我们需要把它推送到你在 GitHub 上的 Fork 仓库。

```bash
git push origin feat/add-contributor-name-to-about-page
```

*   `git push`: 执行推送操作。
*   `origin`: 代表你在 GitHub 上的 Fork 仓库。
*   `feat/add-contributor-name-to-about-page`: 我们要推送的分支名。

### 第 5 步：创建拉取请求 (Pull Request)

最后一步！Pull Request (PR) 是一个请求，请求项目维护者将你分支里的代码合并到主干（`main` 分支）里去。

1. 打开你在 GitHub 上的 Fork 仓库页面 (`https://github.com/[你的用户名]/NipaPlay-Reload`)。
2. GitHub 会自动检测到你刚刚推送了一个新分支，并显示一个黄色的提示条，上面有一个 "Compare & pull request" 按钮。点击它。
3. 在 PR 页面确认合并目标：
    * base repository：`AimesSoft/NipaPlay-Reload`，base：`main`
    * head repository：`[你的用户名]/NipaPlay-Reload`，compare：你刚推送的分支，例如 `feat/add-contributor-name-to-about-page`
4. 你会进入一个新的页面。请在这里填写 PR 的标题和描述。
    * **标题**: 通常使用你的 commit 信息即可，例如 "feat: Add contributor name to about page"。
    * **描述**: 详细说明你做了什么修改，为什么要做这个修改，以及你是如何验证它的。如果这个修改解决了某个 Issue，可以在这里链接它 (例如 `Closes #123`)。
    * **模板**: 仓库会自动带出 PR 模板。请尽量把“改了什么”“为什么改”“怎么验证”“是否有截图”这些部分写完整。
5. 点击 "Create pull request" 按钮。

## PR 规范（非常推荐遵守）

为了让维护者更容易审查，也让你的贡献更容易合并，我们建议每个 PR 都尽量遵守下面这些规则：

*   **一个 PR 尽量只做一件事**:
    *   比如“修一个播放器 bug”或“补一段文档”，而不是把 UI、重构、文档、格式化混在一起。
*   **PR 尽量小而明确**:
    *   小 PR 更容易 review，也更容易在出现问题时快速回退。
*   **标题要清楚**:
    *   推荐沿用 commit 风格，比如 `fix: correct subtitle toggle logic`、`docs: refresh bounty board`。
*   **描述里写清楚验证方式**:
    *   至少说明你跑了什么，例如 `flutter analyze`、`flutter test`（如果有）或手动验证步骤。
*   **涉及 UI 的 PR 尽量附截图或录屏**:
    *   这样维护者不用自己脑补页面变化。
*   **提交前先看一遍自己的 diff**:
    *   确认没有把无关改动、本地配置、临时文件一起带进来。
*   **注意 PR 校验结果**:
    *   当前仓库会自动运行 PR 校验流程；如果检查失败，请先根据日志修复，再继续请求 review。

## 恭喜你

你已经成功地提交了你的第一个代码贡献！现在，项目维护者会收到通知，他们会审查你的代码 (Code Review)，可能会提出一些修改建议。你可以和他们在 PR 页面进行讨论。一旦你的代码被批准，他们就会把它合并到主项目中。

这个流程一开始可能会觉得有些繁琐，但多操作几次就会变得非常熟悉。记住，大胆地去尝试，Codex 会是你非常得力的搭档，但最终把关人仍然是你自己。

---

**⬅️ 上一篇: [2. 探索项目结构](02-Project-Structure.md)** | **➡️ 下一篇: [4. 代码风格指南](04-Coding-Style.md)**
