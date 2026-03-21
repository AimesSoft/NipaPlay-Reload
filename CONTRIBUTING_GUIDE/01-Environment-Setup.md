# 1. 准备你的开发环境

在开始为 NipaPlay-Reload 贡献代码之前，你需要先在你的电脑上搭建好开发环境。这个过程就像是为你盖房子前准备好工具和地基一样。别担心，我们会一步一步地指导你完成。

## 核心工具

无论你使用什么操作系统（Windows, macOS 或 Linux），以下这些工具都是必须安装的。

### 1.1 Git：代码的版本管理员

Git 是一个版本控制系统，你可以把它想象成一个可以记录你每一次代码修改的“时光机”。通过 Git，我们可以轻松地协作，合并不同人做的修改。

*   **如何安装**:
    *   **Windows**: 访问 [git-scm.com](https://git-scm.com/download/win) 下载安装包，然后按照默认设置一路点击“下一步”即可。
    *   **macOS**: 打开“终端”应用，输入 `git --version`。如果系统提示你安装命令行开发者工具，请点击“安装”按钮。或者，你也可以通过 [Homebrew](https://brew.sh/)（一个包管理器）来安装，命令是 `brew install git`。
    *   **Linux**: 打开你的终端，根据你的发行版使用相应的命令：
        *   Debian/Ubuntu: `sudo apt-get install git`
        *   Fedora: `sudo dnf install git`
        *   Arch Linux: `sudo pacman -S git`
*   **安装后的初始化**
    *   使用以下命令进行初始化，记得把[你的用户名]和[你的邮箱]替换成和你 GitHub 一致的信息
        ```
        git config --global user.name "[你的用户名]"
        git config --global user.email [你的邮箱]
        ```

### 1.1.1 (可选) 图形化工具：GitHub Desktop

对于不习惯使用命令行的朋友，GitHub Desktop 是一个不错的替代选择。

*   **下载地址**: [desktop.github.com](https://desktop.github.com/)
*   **优点**: 它提供了一个可视化的界面，让你可以通过点击按钮来完成克隆、提交、推送等操作，非常直观。
*   **为什么我们优先推荐命令行**: 学习使用命令行（终端）是程序员的一项基本功。它非常强大和灵活，并且是所有图形化 Git 工具的基础。掌握了命令行，你就能更深刻地理解 Git 的工作原理，并在遇到复杂情况时更好地解决问题。
*   **建议**: 你可以安装 GitHub Desktop 作为辅助，但在本指南中，我们所有的例子都将使用命令行来演示，以帮助你打下坚实的基础。

### 1.2 Flutter SDK：构建应用的工具箱

Flutter 是我们用来开发 NipaPlay-Reload 的框架，它允许我们用一套代码构建在不同平台（如手机、电脑、网页）上运行的应用。Flutter SDK (软件开发工具包) 就是包含了所有开发所需工具的集合。

*   **如何安装**:
    1.  访问 [Flutter 官网](https://flutter.dev/docs/get-started/install) 下载对应你操作系统的最新稳定版 SDK。
    2.  将下载的压缩包解压到一个你喜欢的位置，例如 `C:\flutter` (Windows) 或者 `~/development/flutter` (macOS/Linux)。**注意：不要把 Flutter SDK 放在需要管理员权限才能访问的目录**，比如 `C:\Program Files\`。
    3.  配置环境变量：这一步是为了让你的电脑能够在任何地方都能找到并使用 Flutter 的命令。
        *   **Windows**: 搜索“编辑系统环境变量”，打开后点击“环境变量”，在“用户变量”下的 "Path" 变量里，新建一个条目，值为你解压的 Flutter SDK 文件夹里的 `bin` 目录的完整路径 (例如 `C:\flutter\bin`)。
        *   **macOS/Linux**: 打开终端，编辑你的 shell 配置文件（通常是 `~/.zshrc`, `~/.bash_profile` 或 `~/.bashrc`）。在文件末尾添加一行：`export PATH="$PATH:[你解压的Flutter路径]/flutter/bin"`。保存文件后，执行 `source ~/.zshrc` (或者相应的配置文件) 来让改动生效。
    4.  运行 `flutter doctor`：打开一个新的终端窗口，输入 `flutter doctor` 命令。这个命令会检查你的环境是否完整，并告诉你还需要安装哪些依赖（比如 Android Studio 或者 Xcode）。根据它的提示完成剩余的设置。

### 1.3 一个好的代码编辑器：VS Code + Codex

代码编辑器是你编写和修改代码的地方。一个好的编辑器能让你事半功倍。对于 NipaPlay-Reload，我们现在最推荐的组合是 **Visual Studio Code (VS Code) + Codex**: VS Code 负责稳定、成熟的 Flutter 开发体验，Codex 负责帮助你理解项目、起草修改方案、解释报错和生成补丁。

*   **VS Code**:
    *   **下载地址**: [code.visualstudio.com](https://code.visualstudio.com/)
    *   **建议安装的扩展**:
        *   `Flutter`
        *   `Dart`
    *   **为什么推荐它**: Flutter 工具链兼容成熟，社区资料丰富，绝大多数贡献者都能快速对齐环境。

*   **Codex**:
    *   **官方文档**: [Codex IDE 文档](https://developers.openai.com/codex/ide)
    *   **使用说明**: [Codex 与 ChatGPT 账户说明](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
    *   **推荐用法**:
        1. 先让 Codex 帮你解释文件、梳理调用链，而不是一上来就“整仓库重写”。
        2. 明确告诉它你只想改哪些文件、达到什么效果、不要动哪些无关模块。
        3. 让它给出最小可行修改后，自己再检查 diff，并运行 `flutter analyze`、`flutter test`（如果有测试）或手动验证。

*   **一个适合新贡献者的 Codex 工作流**:
    1. 在 VS Code 中打开项目根目录。
    2. 安装并登录 Codex，然后先让它读几个关键文件，例如 `lib/main.dart`、`lib/utils/video_player_state.dart`、`lib/player_abstraction/player_factory.dart`。
    3. 先提理解型问题，例如：
        *   “请用中文总结这个项目的视频播放架构，重点解释 `VideoPlayerState` 和 `player_abstraction` 的关系。”
        *   “如果我要修改设置页面里的播放器选项，通常会涉及哪些文件？”
    4. 再提修改型问题，例如：
        *   “请只修改 `lib/themes/nipaplay/pages/settings/about_page.dart`，在版本号下面增加一行贡献者文本，并解释为什么这样改。”
    5. 最后自己运行项目，确认功能真的工作正常。

*   **其他选择**:
    *   如果你已经习惯 JetBrains 系列 IDE、VSCodium 或其他编辑器，也完全可以继续使用。
    *   但为了让文档、截图和协作方式更统一，本指南后续默认都以 **VS Code + Codex** 为例。

## 获取项目代码

环境准备好之后，最后一步就是把 NipaPlay-Reload 的代码克隆（下载）到你的本地电脑上。

1.  **Fork 项目**:
    *   首先，你需要在 GitHub 上有一个自己的账号。
    *   访问 [NipaPlay-Reload 的 GitHub 仓库页面](https://github.com/AimesSoft/NipaPlay-Reload)。
    *   点击页面右上角的 "Fork" 按钮。这会在你的 GitHub 账号下创建一个项目的完整副本。

2.  **克隆你的 Fork**:
    *   打开你的终端。
    *   导航到一个你希望存放项目的文件夹，例如 `cd ~/dev`。
    *   执行以下命令，记得把 `[你的GitHub用户名]` 替换成你自己的用户名：
        ```
        git clone https://github.com/[你的GitHub用户名]/NipaPlay-Reload.git
        ```
    *   然后进入项目目录：
        ```
        cd NipaPlay-Reload
        ```

## 总结

现在，你的电脑上已经拥有了开发 NipaPlay-Reload 所需的一切！你已经安装了 Git 和 Flutter，配置好了编辑器，并且下载了项目的代码。

在下一章节，我们将带你了解项目的代码结构，让你知道不同的功能分别是在哪些文件里实现的。

---

**⬅️ 上一篇: [欢迎来到 NipaPlay-Reload 贡献指南](00-Introduction.md)** | **➡️ 下一篇: [2. 探索项目结构](02-Project-Structure.md)**
