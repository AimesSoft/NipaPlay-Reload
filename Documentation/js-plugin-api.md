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
  minHostVersion: '1.11.0',
  description: '内置常用敏感词与辱骂词，启用后自动屏蔽命中的弹幕。',
  author: 'NipaPlay Team',
  github: 'https://github.com/xxx/xxx', // 可选
  permissions: ['danmaku.modify'] // 可选，权限声明
};
```

字段说明：

- `id`：必填，唯一标识，非空字符串。
- `name`：必填，展示名，非空字符串。
- `version`：必填，版本号，非空字符串。
- `minHostVersion`：必填，插件要求的宿主（NipaPlay）最低版本，格式为 `主版本.次版本.修订号`（如 `1.11.0`）。若宿主版本低于此值，插件将被标记为不兼容。
- `description`：选填，描述字符串。
- `author`：选填，作者字符串。
- `github`：选填，GitHub 链接字符串，可为空。
- `permissions`：选填，权限字符串数组。

若 `id/name/version/minHostVersion` 任一为空，插件会被判定为无效。

#### 权限列表

| 权限 ID | 说明 |
|---------|------|
| `player.control` | 控制播放器（播放/暂停/跳转） |
| `danmaku.modify` | 修改弹幕显示和过滤规则 |
| `library.read` | 读取媒体库信息 |
| `library.write` | 修改媒体库内容 |
| `ui.dialog` | 显示弹窗和提示信息 |
| `settings.read` | 读取应用设置 |
| `settings.modify` | 修改应用设置 |
| `storage` | 使用本地存储 |
| `system.override` | 覆盖系统级设置（如解锁下载器） |

权限声明示例：

```js
const pluginManifest = {
  id: 'com.example.myplugin',
  name: '我的插件',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '描述',
  author: '作者',
  permissions: [
    'player.control',
    'danmaku.modify',
    'ui.dialog'
  ]
};
```

### 3.2 `pluginBlockWords`（可选）

用于弹幕过滤词库。必须是字符串数组；非数组时按空数组处理。

```js
const pluginBlockWords = [
  '示例词1',
  '示例词2',
  '规则名/正则表达式/'
];
```

每项支持两种格式：

- **纯文本**：直接进行子串匹配（`content.contains(word)`）。
- **正则表达式**：格式为 `名称/正则表达式/`，宿主会按 `/` 分隔提取正则部分，对弹幕文本执行 `RegExp.hasMatch`。名称部分用于展示，正则部分用于匹配。

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
- `enabled`：可选，布尔值。当提供时，宿主在设置页中渲染开关（`Switch`）而非普通点击项，用户可通过开关切换状态。点击开关后宿主会调用 `pluginHandleUIAction(entry.id)`，插件在回调中切换自身逻辑并返回结果。
- `textSetting`：可选，对象。当提供时（且 `enabled` 未设置），宿主在设置页中渲染文本输入框，用于收集用户自由输入的配置项。输入值由宿主持久化存储，插件可通过 `settings.getText(entry.id)` 读取。

`textSetting` 对象字段：

- `hintText`：可选，文本框占位提示。
- `default`：可选，字符串，默认值。用户首次看到文本框时的初始内容。

```js
const pluginUIEntries = [
  {
    id: 'api_url',
    title: 'API 地址',
    description: '输入远程接口地址',
    textSetting: { hintText: 'https://example.com/api', default: '' }
  },
  {
    id: 'max_retries',
    title: '最大重试次数',
    description: '请求失败时的重试次数（0-10）',
    textSetting: { hintText: '3', default: '3' }
  }
];
```

> `enabled` 与 `textSetting` 同时存在时，`enabled` 优先（渲染为开关）。两者都不存在时渲染为普通点击项。

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
- 返回 `null/undefined`（或等效空值）会被视为”无结果”。
- 目前仅支持 `type: 'text'`。
- 对象字段：
  - `type`：必填，当前只支持 `text`
  - `title`：必填，非空
  - `content`：可为空字符串

重要行为：`pluginHandleUIAction` 执行完毕后，宿主会自动重新读取 JS 运行时中的 `pluginBlockWords` 和 `pluginUIEntries` 变量。这意味着插件可以在回调中动态修改这两个变量（例如切换规则启用状态），宿主会即时同步更新弹幕过滤词库和 UI 入口列表。

### 3.5 `pluginOnEvent(event)`（可选）

监听应用事件。

```js
function pluginOnEvent(event) {
  console.log('事件:', event.name, event.data);
  
  if (event.name === 'play') {
    ui.showToast('视频开始播放');
  }
}
```

支持的事件：

| 事件名 | 说明 | `event.data` 内容 |
|--------|------|------------------|
| `videoLoaded` | 视频加载完成 | 视频信息对象 |
| `play` | 开始播放 | 视频信息对象 |
| `pause` | 暂停播放 | 视频信息对象 |
| `seek` | 进度跳转 | `{ time: 当前时间, duration: 总时长 }` |
| `danmakuShow` | 弹幕显示 | 弹幕对象 |
| `settingsChanged` | 设置变更 | `{ key: 设置键, value: 新值 }` |
| `appResumed` | 应用恢复 | 空对象 |
| `appPaused` | 应用暂停 | 空对象 |

### 3.6 生命周期函数（可选）

插件可以声明以下生命周期钩子：

```js
function pluginOnInitialize() {
  // 插件启用时调用
  ui.showToast('插件已启用');
}

function pluginOnDestroy() {
  // 插件禁用时调用
  ui.showToast('插件已禁用');
}

function pluginOnResume() {
  // 应用恢复到前台时调用
}

function pluginOnSuspend() {
  // 应用进入后台时调用
}
```

## 4. 宿主暴露的 API 桥接对象

宿主在插件运行时注入了以下全局桥接对象，插件可直接使用。

### 4.1 `plugin` 对象

包含插件元数据和权限检查：

```js
// 获取插件信息
console.log(plugin.id);
console.log(plugin.name);
console.log(plugin.version);

// 检查权限
if (plugin.hasPermission('player.control')) {
  // 有权限，执行操作
}

// 查看所有权限
console.log(plugin.permissions);
```

### 4.2 `player` 对象（需要 `player.control` 权限）

控制播放器：

```js
// 播放
player.play();

// 暂停
player.pause();

// 跳转进度（秒）
player.seek(120);

// 获取播放器状态
const state = player.getState();
console.log(state.playing);
console.log(state.currentTime);
console.log(state.duration);
```

### 4.3 `danmaku` 对象（需要 `danmaku.modify` 权限）

控制弹幕：

```js
// 显示弹幕
danmaku.show();

// 隐藏弹幕
danmaku.hide();

// 设置弹幕透明度（0.0 - 1.0）
danmaku.setOpacity(0.8);

// 添加弹幕过滤器
danmaku.addFilter('myFilter', '屏蔽词1');
danmaku.addFilter('myRegex', '规则名/正则表达式/');

// 移除弹幕过滤器
danmaku.removeFilter('myFilter');
```

### 4.4 `ui` 对象（需要 `ui.dialog` 权限）

显示 UI 元素：

```js
// 显示 Toast 提示
ui.showToast('提示信息');

// 显示对话框
const result = ui.showDialog('标题', '内容');

// 显示加载提示
ui.showLoading('加载中...');

// 隐藏加载提示
ui.hideLoading();
```

### 4.5 `storage` 对象（需要 `storage` 权限）

本地存储：

```js
// 存储数据
storage.set('key', 'value');
storage.set('number', 123);
storage.set('object', { a: 1 });

// 读取数据
const value = storage.get('key');
const number = storage.get('number');
const object = storage.get('object');

// 删除数据
storage.remove('key');

// 清空所有数据
storage.clear();
```

### 4.6 `dev` 对象

开发调试工具：

```js
// 输出日志
dev.log('调试信息');

// 输出错误
dev.logError('错误信息');
```

### 4.7 `settings` 对象

读写插件的文本配置项（即 `pluginUIEntries` 中声明了 `textSetting` 的条目）。宿主自动持久化，插件无需自行存储。

```js
// 读取配置值（返回字符串，未设置时返回空字符串 ''）
const apiUrl = settings.getText('api_url');

// 写入配置值（value 会自动转为字符串）
settings.setText('api_url', 'https://new-api.example.com');
```

典型用法：在 `pluginOnInitialize` 中读取用户之前填写的配置值，或在 `pluginHandleUIAction` 中修改配置。

> `settings` 对象不需要任何权限声明，始终可用。它仅操作插件自身的文本配置项，不同插件之间互不影响。

## 5. 宿主当前暴露能力（对 JS）

当前 JS 插件接口支持：

### 声明式变量与回调

1. `pluginManifest` - 插件元数据
2. `pluginBlockWords` - 弹幕屏蔽词
3. `pluginUIEntries` - UI 入口列表
4. `pluginHandleUIAction(actionId)` - UI 动作处理
5. `pluginOnEvent(event)` - 事件监听
6. `pluginOnInitialize()` - 初始化钩子
7. `pluginOnDestroy()` - 销毁钩子
8. `pluginOnResume()` - 恢复钩子
9. `pluginOnSuspend()` - 挂起钩子

### 桥接 API 对象

1. `plugin` - 插件元数据与权限检查
2. `player` - 播放器控制
3. `danmaku` - 弹幕控制
4. `ui` - UI 交互
5. `storage` - 本地存储
6. `dev` - 开发调试
7. `settings` - 读写插件文本配置项

## 6. 生命周期与状态

- 启动时扫描插件脚本并解析元数据。
- 启动时会同时扫描资产插件和应用数据目录中的外部插件。
- 插件启用后会：
  - 加载运行时
  - 调用 `pluginOnInitialize()`
  - 读取 `pluginBlockWords/pluginUIEntries`
- 禁用插件会：
  - 调用 `pluginOnDestroy()`
  - 卸载运行时
  - 清空该插件的生效屏蔽词
- 启用状态持久化在 `SharedPreferences`：`plugin_enabled_ids`。
- 非内置插件（外部导入）可在设置页中删除，删除前会自动禁用并卸载运行时。

## 7. 与弹幕过滤的集成

- 所有已启用且已加载插件的 `pluginBlockWords` 会合并。
- 合并结果用于弹幕文本过滤。
- 同一词在多个插件重复出现时，当前实现不会去重（按合并结果原样参与匹配）。

## 8. 错误与兼容性

- 运行 JS 时报错会导致该插件 `loaded=false`，并记录错误信息到插件状态。
- 插件 UI 动作返回格式不符时会抛出格式错误（例如 `type` 不是 `text`）。
- Web 平台插件运行时未实现。
- 权限检查失败时 API 调用会返回 `false` 或 `null`。

## 9. 最小可用插件模板

```js
const pluginManifest = {
  id: 'custom.example',
  name: '示例插件',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '一个最小可用插件',
  author: 'You',
  permissions: ['ui.dialog']
};

const pluginBlockWords = ['示例屏蔽词'];

const pluginUIEntries = [
  {
    id: 'hello',
    title: '示例操作',
    description: '点击后显示文本'
  }
];

function pluginOnInitialize() {
  ui.showToast('插件已启用');
}

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

## 10. 带开关切换的插件示例

以下示例展示如何使用 `enabled` 字段实现逐条规则的开关切换，以及动态更新 `pluginBlockWords` 和 `pluginUIEntries`。

```js
const pluginManifest = {
  id: 'custom.regex_filter',
  name: '正则过滤规则',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '可逐条开关的弹幕正则过滤规则',
  author: 'You',
  permissions: ['danmaku.modify']
};

var rules = [
  {
    id: 'repeat',
    name: '刷屏重复',
    desc: '重复字符、笑声刷屏',
    pattern: '[哈嘿]{7,}',
    enabled: true
  },
  {
    id: 'keyword',
    name: '纯关键词',
    desc: '"路过""打卡"等占位弹幕',
    pattern: '^(路过|打卡|签到)+$',
    enabled: true
  }
];

function buildBlockWords() {
  var result = [];
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].enabled) {
      result.push(rules[i].name + '/' + rules[i].pattern);
    }
  }
  return result;
}

function buildUIEntries() {
  var result = [];
  for (var i = 0; i < rules.length; i++) {
    result.push({
      id: rules[i].id,
      title: rules[i].name,
      description: rules[i].desc,
      enabled: rules[i].enabled
    });
  }
  return result;
}

var pluginBlockWords = buildBlockWords();
var pluginUIEntries = buildUIEntries();

function pluginHandleUIAction(actionId) {
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].id === actionId) {
      rules[i].enabled = !rules[i].enabled;
      pluginBlockWords = buildBlockWords();
      pluginUIEntries = buildUIEntries();
      return {
        type: 'text',
        title: rules[i].name,
        content: (rules[i].enabled ? '已启用' : '已禁用') + '「' + rules[i].name + '」'
      };
    }
  }
  return { type: 'text', title: '正则过滤', content: '未知操作。' };
}
```

要点：

- `pluginUIEntries` 中每项可提供 `enabled: bool`，宿主会渲染为开关（`Switch`）。
- 开关切换时宿主调用 `pluginHandleUIAction(entry.id)`，插件在回调中切换 `rules[i].enabled`，然后重建 `pluginBlockWords` 和 `pluginUIEntries`。
- 回调执行完毕后宿主自动重新读取这两个变量，无需额外操作。
- `pluginBlockWords` 中的正则格式项（`名称/正则表达式/`）会被宿主识别并按正则匹配弹幕。

## 11. 事件监听插件示例

```js
const pluginManifest = {
  id: 'com.example.event_plugin',
  name: '事件监听插件',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '监听播放事件并提示',
  author: 'You',
  permissions: ['player.control', 'ui.dialog']
};

function pluginOnEvent(event) {
  switch (event.name) {
    case 'videoLoaded':
      dev.log('视频已加载: ' + event.data.title);
      break;
    case 'play':
      ui.showToast('开始播放');
      break;
    case 'pause':
      ui.showToast('已暂停');
      break;
    case 'seek':
      dev.log('跳转至: ' + event.data.time);
      break;
  }
}
```

## 12. 存储使用示例

```js
const pluginManifest = {
  id: 'com.example.storage_plugin',
  name: '存储示例',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '演示存储功能',
  author: 'You',
  permissions: ['storage', 'ui.dialog']
};

let counter = 0;

function pluginOnInitialize() {
  const savedCounter = storage.get('counter');
  if (savedCounter !== null) {
    counter = savedCounter;
  }
  ui.showToast('已启动 ' + counter + ' 次');
  counter++;
  storage.set('counter', counter);
}
```

## 13. 文本配置项示例

以下示例展示如何使用 `textSetting` 让用户在设置页填写配置，并在插件中读取。

```js
const pluginManifest = {
  id: 'custom.api_proxy',
  name: 'API 代理',
  version: '1.0.0',
  minHostVersion: '1.11.0',
  description: '通过配置的 API 地址获取弹幕数据',
  author: 'You',
  permissions: ['ui.dialog']
};

var pluginUIEntries = [
  {
    id: 'api_url',
    title: 'API 地址',
    description: '弹幕数据接口地址',
    textSetting: { hintText: 'https://example.com/danmaku', default: '' }
  },
  {
    id: 'token',
    title: '访问令牌',
    description: '接口鉴权令牌（可留空）',
    textSetting: { hintText: '输入 token', default: '' }
  },
  {
    id: 'enable_filter',
    title: '启用过滤',
    description: '是否过滤低质量弹幕',
    enabled: true
  }
];

function pluginOnInitialize() {
  var url = settings.getText('api_url');
  if (url) {
    ui.showToast('API 地址已配置: ' + url);
  }
}

function pluginHandleUIAction(actionId) {
  if (actionId === 'enable_filter') {
    // 切换开关逻辑（同开关型示例）
    // ...
  }
  return { type: 'text', title: 'API 代理', content: '操作完成' };
}
```

要点：

- `textSetting` 条目在设置页中渲染为标题 + 描述 + 文本输入框。
- 用户输入的值由宿主持久化保存，关闭再打开设置页后依然存在。
- 插件通过 `settings.getText(entryId)` 读取值，通过 `settings.setText(entryId, value)` 写入值。
- `textSetting` 与 `enabled` 可以在同一份 `pluginUIEntries` 中混合使用，各自独立渲染为文本框或开关。
- 底部会显示「保存并关闭」和「关闭」按钮，方便用户确认操作。
