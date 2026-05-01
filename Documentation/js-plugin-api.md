# NipaPlay JS 插件接口文档

本文档说明当前版本 NipaPlay 的 JS 插件可用接口与约定（基于现有实现）。

## 1. 放置位置与加载范围

- 插件文件必须是 `.js`。
- 宿主会扫描两类来源：
  - 内置资产插件：`assets/plugins/builtin/`、`assets/plugins/custom/`
  - 外部导入插件：`<应用数据目录>/plugins/`
- 其中资产目录需已在 `pubspec.yaml` 的 `assets` 中声明。

## 2. 运行时与平台

- 非 Web 平台通过 `flutter_js` 执行插件。
- Web 平台当前不支持 JS 插件运行时（会抛出 `UnsupportedError`）。

## 3. 插件入口变量与函数

JS 插件通过以下全局符号与宿主交互。

### 3.1 `pluginManifest`（必需）

必须是对象，且字段要求如下：

```js
const pluginManifest = {
  id: 'builtin.cn_sensitive_danmaku_filter',
  name: '弹幕预设屏蔽词（中国大陆）',
  version: '1.1.0',
  description: '内置常用敏感词与辱骂词，启用后自动屏蔽命中的弹幕。',
  author: 'NipaPlay Team',
  github: 'https://github.com/xxx/xxx' // 可选
};
```

字段说明：

- `id`：必填，唯一标识，非空字符串。
- `name`：必填，展示名，非空字符串。
- `version`：必填，版本号，非空字符串。
- `description`：选填，描述字符串。
- `author`：选填，作者字符串。
- `github`：选填，GitHub 链接字符串，可为空。

若 `id/name/version` 任一为空，插件会被判定为无效。

### 3.2 `pluginBlockWords`（可选）

用于弹幕过滤词库。必须是字符串数组；非数组时按空数组处理。

```js
const pluginBlockWords = ['示例词1', '示例词2'];
```

宿主读取后会做：

- 每项转字符串并 `trim()`；
- 过滤空字符串；
- 仅在插件 `enabled && loaded` 时生效。

### 3.3 `pluginUIEntries`（可选）

用于在设置页生成“插件功能入口（扳手菜单）”。必须是数组。

```js
const pluginUIEntries = [
  {
    id: 'preview_words',
    title: '已生效词库预览',
    description: '查看当前生效词库' // 可选
  }
];
```

每个 entry 字段：

- `id`：必填，非空。
- `title`：必填，非空。
- `description`：可选。

无效 entry 会被跳过，不会导致整个插件失败。

### 3.4 `pluginHandleUIAction(actionId)`（可选）

当用户点击插件配置项后，宿主会调用此函数。

```js
function pluginHandleUIAction(actionId) {
  if (actionId === 'preview_words') {
    return {
      type: 'text',
      title: '已生效词库预览',
      content: '这里是要显示的文本'
    };
  }

  return {
    type: 'text',
    title: '插件操作',
    content: '不支持的操作。'
  };
}
```

返回值要求：

- 可以返回对象，也可以返回对象的 JSON 字符串。
- 返回 `null/undefined`（或等效空值）会被视为“无结果”。
- 目前仅支持 `type: 'text'`。
- 对象字段：
  - `type`：必填，当前只支持 `text`
  - `title`：必填，非空
  - `content`：可为空字符串

## 4. 宿主当前暴露能力（对 JS）

当前 JS 插件接口是“声明式变量 + action 回调”模型，不提供直接调用 Dart/Flutter API 的桥接对象。

即当前可用“接口”只有以下四项：

1. `pluginManifest`
2. `pluginBlockWords`
3. `pluginUIEntries`
4. `pluginHandleUIAction(actionId)`

未提供（当前版本）：

- 任意 Dart 方法直调
- 文件系统 API
- 网络 API 专用桥接
- 播放控制 API
- 设置读写 API

如果后续要做跨语言插件系统的“全量接口暴露”，建议新增一个受控桥接对象（例如 `pluginHost`），按 capability 白名单逐步开放。

## 5. 生命周期与状态

- 启动时扫描插件脚本并解析元数据。
- 启动时会同时扫描资产插件和应用数据目录中的外部插件。
- 插件启用后才会加载运行时并读取 `pluginBlockWords/pluginUIEntries`。
- 禁用插件会卸载运行时并清空该插件的生效屏蔽词。
- 启用状态持久化在 `SharedPreferences`：`plugin_enabled_ids`。

## 6. 与弹幕过滤的集成

- 所有已启用且已加载插件的 `pluginBlockWords` 会合并。
- 合并结果用于弹幕文本过滤。
- 同一词在多个插件重复出现时，当前实现不会去重（按合并结果原样参与匹配）。

## 7. 错误与兼容性

- 运行 JS 时报错会导致该插件 `loaded=false`，并记录错误信息到插件状态。
- 插件 UI 动作返回格式不符时会抛出格式错误（例如 `type` 不是 `text`）。
- Web 平台插件运行时未实现。

## 8. 最小可用插件模板

```js
const pluginManifest = {
  id: 'custom.example',
  name: '示例插件',
  version: '1.0.0',
  description: '一个最小可用插件',
  author: 'You'
};

const pluginBlockWords = ['示例屏蔽词'];

const pluginUIEntries = [
  {
    id: 'hello',
    title: '示例操作',
    description: '点击后显示文本'
  }
];

function pluginHandleUIAction(actionId) {
  if (actionId !== 'hello') {
    return { type: 'text', title: '示例插件', content: '未知动作' };
  }
  return {
    type: 'text',
    title: '示例插件',
    content: 'Hello from JS plugin.'
  };
}
```
