# JS 插件目录说明

插件文件放在以下目录，扩展名必须是 `.js`：

- `assets/plugins/builtin/`：内置插件（随应用发布）
- `assets/plugins/custom/`：自定义插件（项目内打包）

## 插件脚本规范

每个插件 JS 文件需要至少导出两个全局变量：

```js
const pluginManifest = {
  id: 'example.unique_plugin_id',
  name: '插件名称',
  version: '1.0.0',
  description: '插件描述',
  author: '作者名',
  github: 'https://github.com/your/repo' // 可选
};

const pluginBlockWords = [
  '词1',
  '词2',
  '规则名/正则表达式/' // 支持正则格式
];
```

`pluginBlockWords` 每项支持两种格式：

- **纯文本**：直接进行子串匹配。
- **正则表达式**：格式为 `名称/正则表达式/`，宿主提取 `/` 之间的正则部分执行匹配。

插件可选地暴露插件专属 UI 动作（用于设置页中的扳手按钮）：

```js
const pluginUIEntries = [
  {
    id: 'preview_words',
    title: '已生效词库预览',
    description: '查看当前插件词库'
  }
];

function pluginHandleUIAction(actionId) {
  if (actionId === 'preview_words') {
    return {
      type: 'text',
      title: '已生效词库预览',
      content: pluginBlockWords.join('、')
    };
  }
  return null;
}
```

`pluginHandleUIAction` 的返回值目前支持：

- `type: 'text'`
- `title: string`
- `content: string`

## 字段说明

- `pluginManifest.id`：插件唯一 ID，必须全局唯一。
- `pluginManifest.name`：展示名称。
- `pluginManifest.version`：版本号（字符串）。
- `pluginManifest.description`：描述文本（可留空）。
- `pluginManifest.author`：作者名（可留空）。
- `pluginManifest.github`：项目链接（可选）。
- `pluginBlockWords`：弹幕屏蔽词数组；启用插件后会并入弹幕过滤词库。
- `pluginUIEntries`：插件可选 UI 入口数组；会显示在插件开关右侧扳手按钮中。
- `pluginHandleUIAction(actionId)`：插件可选 UI 动作处理函数。

## 合规建议

- 敏感词建议在 JS 内采用 base64 保存，在运行时再解码为 `pluginBlockWords`。
- 建议同时提供 `atob` 与 `Buffer` 两种解码分支，提升运行时兼容性。

## 外部脚本与弹幕渲染器

插件可在 `pluginManifest.requires` 中声明 HTTPS 外部脚本。依赖只会在插件已启用、渲染器已被用户选中时下载并加载：

```js
const pluginManifest = {
  // ...常规清单字段
  permissions: ['script.external', 'danmaku.renderer'],
  requires: [
    {
      id: 'engine',
      url: 'https://example.com/engine.js',
      sha256: '<64位十六进制摘要>',
    },
  ],
};
```

清单必须同时申请 `script.external` 与 `danmaku.renderer` 权限。当前 WebView 渲染宿主只在 Android 与 iOS 显示插件引擎；外部脚本仅允许 HTTPS，按声明顺序加载，单文件上限 32 MB。省略 SHA-256 可以运行，但发布插件时强烈建议固定摘要。

`pluginDanmakuRenderers` 可通过 `requires: ['engine']` 选择清单中的依赖。`bootstrap` 是轻量适配层；它应创建 `window.NipaDanmakuRenderer.handle(message)`。宿主发送以下消息：

- `initialize`：宿主 API 版本与插件/渲染器 ID。
- `load`：标准化弹幕列表及列表版本。
- `settings`：可见性、透明度、字号、显示区域、滚动时长、屏蔽项及时间偏移。
- `clock`：播放位置、播放态、倍速和 seek 版本；目前最多每 100 ms 推送一次。
- `dispose`：释放引擎、DOM 与监听器。

渲染页可通过 `NipaDanmakuHost.postMessage(JSON.stringify(...))` 返回 `ready`、`log` 或 `error`。完整 Titan 适配示例见 `assets/plugins/builtin/titan_danmaku_renderer.js`。

## 冲突策略

- 如果出现重复 `id`，后加载到的插件会被忽略，并打印日志。
- 插件脚本加载失败时不会导致应用崩溃，设置页会显示加载失败信息。
