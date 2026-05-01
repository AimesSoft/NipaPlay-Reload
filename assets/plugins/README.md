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
];
```

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

## 冲突策略

- 如果出现重复 `id`，后加载到的插件会被忽略，并打印日志。
- 插件脚本加载失败时不会导致应用崩溃，设置页会显示加载失败信息。
