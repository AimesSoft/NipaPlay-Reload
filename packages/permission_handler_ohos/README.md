## ohos权限配置参考

### [声明权限](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/security/AccessToken/declare-permissions.md)

应用在申请权限时，需要在项目的配置文件中，逐个声明需要的权限，否则应用将无法获取授权。

---
### [权限列表](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/security/AccessToken/permissions-for-all.md)
#### 对所有应用开放
在申请目标权限前，建议开发者先阅读申请应用权限，对权限的工作流程有基本了解后，再结合列表中权限字段的具体说明，判断应用能否申请目标权限，提高开发效率。

---
### 注意事项

    申请权限需要在ohos/entry/src/main/module.json5中声明
