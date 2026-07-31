<p align="center">
  <h1 align="center"> <code>file_selector</code> </h1>
</p>

This project is based on [file_selector@1.0.1](https://pub.dev/packages/file_selector/versions/1.0.1).

## 1. Installation and Usage

### 1.1 Installation

Go to the project directory and add the following dependencies in pubspec.yaml

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

Execute Command

```bash
flutter pub get
```

<!-- tabs:end -->

### 1.2 Usage

For use cases [ohos/example](./example)

## 2. Constraints

### 2.1 Compatibility

This document is verified based on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
### 2.2 **Permission Requirements**

The following permissions include the `system_basic` permission, but the default application permission is `normal`. Only the `normal` permission can be used. Therefore, the error **9568289** may be reported during the installation of the HAP package. For details, see [Document](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/bm-tool-V5#EN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) Change the application level to `system_basic`.

####  2.2.1 **Add permissions to the module.json5 file in the entry directory.**

Open  `entry/src/main/module.json5` and add the following information:

```diff
"requestPermissions": [
      {
        "name": "ohos.permission.INTERNET",
        "reason": "$string:network_reason",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      },
    ]
```

#### 2.2.2 **Add the reason for applying for the preceding permission to the entry directory.**

Open  `entry/src/main/resources/base/element/string.json` and add the following information:

```diff
{
  "string": [
    {
      "name": "network_reason",
      "value": "use network"
    }
  ]
}
```

## 3. API

> [!TIP] If the value of **ohos Support** is **yes**, it means that the ohos platform supports this property; **no** means the opposite; **partially** means some capabilities of this property are supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name                                                         | return value                                          | Description                                                  | Type     | ohos Support |
| ------------------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------------------ | -------- | ------------ |
| openFile({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,})                                           | Future<XFile?> | Opens a file dialog for loading files and returns a list of file responses chosen by the user.                  | function | yes          |
| openFiles({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,})                                           | Future<List<XFile>> | Opens a file dialog for loading files and returns a list of file responses chosen by the user.                  | function | yes          |
| getDirectoryPath({String? initialDirectory, String? confirmButtonText,})                                           | Future<String?> | Opens a file dialog for loading directories and returns a directory paths.                  | function | no           |

### Parameters

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| acceptedTypeGroups  | a list of file type groups that can be selected in the dialog, How this is displayed depends on the pltaform .selection                                                                                                                                 | List<[XTypeGroup](#XTypeGroup)>?               | yes               |
| initialDirectory  | the full path to the directory that will be displayed when the dialog is opened. When not provided, the platform will pick an initial location.                                                                                                                                 | String?               | yes               |
| confirmButtonTex  | the text in the confirmation button of the dialog. When not provided, the default OS label is used (for example, "Open"). location.                                                                                                                                 | String?               | yes               |

### XTypeGroup

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| label  | The 'name' or reference to this group of types.                                                                                                                                 | String?               | yes               |
| extensions  | The extensions for this group.                                                                                                                                 | List<String>?               | yes               |
| mimeTypes  | The MIME types for this group.                                                                                                                                 | List<String>?               | yes               |
| uniformTypeIdentifiers  | The uniform type identifiers for this group                                                                                                                                 | List<String>?               | yes               |
| webWildCards  | The web wild cards for this group (ex: image/*, video/*).                                                                                                                                 | List<String>?               | yes               |


## 4. Known Issues

`getDirectoryPath` is not implemented by this plugin. HarmonyOS folder
selection is also limited by the device's system capabilities; applications
should not treat file selection support as folder-tree access.

## 5. Others

## 6. License

This project is licensed under [BSD-3-Clause](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/file_selector/file_selector_ohos/LICENSE).

> Template version: v0.0.1
