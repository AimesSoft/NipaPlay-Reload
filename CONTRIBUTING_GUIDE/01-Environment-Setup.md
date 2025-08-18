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

### 1.3 一个好的代码编辑器

代码编辑器是你编写和修改代码的地方。一个好的编辑器能让你事半功倍。我们强烈推荐使用 **Cursor**，因为它深度集成了 AI 功能，可以极大地帮助你理解和编写代码。

*   **Cursor**:
    *   **下载地址**: [cursor.sh](https://cursor.sh/)
    *   **为什么推荐它**: Cursor 可以让你直接在编辑器里与 AI 对话，比如让它帮你解释一段代码、生成新的代码片段，或者帮你修复错误。这对于编程新手来说是极大的助力。
    *   **备选方案**: 如果你不想使用 Cursor，**Visual Studio Code (VS Code)** 也是一个非常优秀的选择。你可以通过安装 Flutter 和 Dart 插件来获得良好的开发体验。

## 获取项目代码

环境准备好之后，最后一步就是把 NipaPlay-Reload 的代码克隆（下载）到你的本地电脑上。

1.  **Fork 项目**:
    *   首先，你需要在 GitHub 上有一个自己的账号。
    *   访问 [NipaPlay-Reload 的 GitHub 仓库页面](https://github.com/MCDFsteve/NipaPlay-Reload)。
    *   点击页面右上角的 "Fork" 按钮。这会在你的 GitHub 账号下创建一个项目的完整副本。

2.  **克隆你的 Fork**:
    *   打开你的终端。
    *   导航到一个你希望存放项目的文件夹，例如 `cd ~/development`。
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
