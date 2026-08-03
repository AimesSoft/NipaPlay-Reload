<p align="center">
  <h1 align="center"> <code>file_selector</code> </h1>
</p>

本项目基于 [file_selector@1.0.1](https://pub.dev/packages/file_selector/versions/1.0.1) 开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
...

dependencies:
  file_selector:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/file_selector/file_selector

...
```

执行命令

```bash
flutter pub get
```

<!-- tabs:end -->

### 1.2 使用案例

使用案例详见 [ohos/example](./example)

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 权限要求

以下权限中有`system_basic` 权限，而默认的应用权限是 `normal` ，只能使用 `normal` 等级的权限，所以可能会在安装hap包时报错**9568289**，请参考 [文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/bm-tool-V5#ZH-CN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) 修改应用等级为 `system_basic`

####  在 entry 目录下的module.json5中添加权限

打开 `entry/src/main/module.json5`，添加：

```yaml
...
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

####  在 entry 目录下添加申请以上权限的原因

打开 `entry/src/main/resources/base/element/string.json`，添加：

```
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name                                                         | return value                                          | Description                                                  | Type     | ohos Support |
| ------------------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------------------ | -------- | ------------ |
| openFile({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,})                                           | Future<XFile?> | 打开一个用于加载文件的文件对话框，并返回用户选择的文件响应列表。                  | function | yes          |
| openFiles({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,})                                           | Future<List<XFile>> | 打开一个文件对话框以加载文件，并返回用户选择的文件响应列表。                  | function | yes          |
| getDirectoryPath({String? initialDirectory, String? confirmButtonText,})                                           | Future<String?> | 打开一个文件对话框以选择目录，并返回所选的目录路径。                  | function | yes          |

### Parameters

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| acceptedTypeGroups  | 可以在对话框中选择的文件类型组列表，其显示方式取决于平台。                                                                                                                                 | List<[XTypeGroup](#XTypeGroup)>?               | yes               |
| initialDirectory  | 对话框打开时将显示的目录的完整路径。如果没有提供，平台将选择一个初始位置。                                                                                                                                | String?               | yes               |
| confirmButtonTex  | 对话框确认按钮上的文本。如果没有提供，将使用默认的操作系统标签（例如，“Open”）。                                                                                                                                 | String?               | yes               |

### XTypeGroup

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| label  | 这个类型组的“名称”或引用。                                                                                                                                 | String?               | yes               |
| extensions  | 这个组的文件扩展名                                                                                                                                 | List<String>?               | yes               |
| mimeTypes  | 这个组的 MIME 类型。                                                                                                                                 | List<String>?               | yes               |
| uniformTypeIdentifiers  | 这个组的统一类型标识符。                                                                                                                                 | List<String>?               | yes               |
| webWildCards  | 这个组的网络通配符（例如：image/*，video/*）。                                                                                                                                 | List<String>?               | yes               |

## 4. 遗留问题

## 5. 其他

## 6. 开源协议

本项目基于 [BSD-3-Clause](This project is licensed under [BSD-3-Clause](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/file_selector/file_selector_ohos/LICENSE).) ，请自由地享受和参与开源。

> 模板版本: v0.0.1
