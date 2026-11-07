# 配置梨花

梨花由三部分组成：

| 组成 | 职责 |
|---|---|
| NipaPlay | 以工具形式提供媒体库、下载、播放、资料、设置等能力，执行工具调用并返回结果 |
| 运行器 | 与模型通信，把模型选择的工具调用交给 NipaPlay，管理对话上下文。默认为 DeepSeek Harness（DSH），可选 Codex |
| 模型 | 理解请求，决定调用哪些工具。由用户选择的服务商提供，需支持工具调用（function calling） |

梨花运行在桌面设备（macOS、Windows、Linux）和 [Linux 无界面版](../advanced/headless.md)上。iPhone、iPad、Apple TV 和鸿蒙设备使用其他设备上的梨花，见[多台设备](../use/devices.md#在手机平板和电视上使用梨花)。

## 推荐配置

| | DeepSeek V4.1 Flash（1017） | GLM-5.3 Flash |
|---|---|---|
| 设置页模板 | DeepSeek | 智谱 |
| 地址 | `https://api.deepseek.com` | `https://open.bigmodel.cn/api/paas/v4` |
| 模型（API 模型 ID） | `deepseek-flash` | `glm-5.3-flash` |
| 接口 | Responses | Chat Completions |
| 图片输入 | 支持 | 支持 |
| API key | [DeepSeek 开放平台](https://platform.deepseek.com/) | [智谱开放平台](https://open.bigmodel.cn/) |

「模型」一栏填写 API 模型 ID。DeepSeek V4.1 Flash 1017 是发布名称，官方 API 中对应的 ID 为 `deepseek-flash`。通过 OpenRouter 等中转服务接入时，模型 ID 由中转方规定，例如 `deepseek/deepseek-v4.1-flash`。

接口与地址对应：

- DeepSeek 官方 API 在同一地址上提供 Responses 和 Chat Completions。
- 智谱的 Chat Completions 地址为 `…/api/paas/v4`，Responses 地址为 `…/api/v1`；GLM-5.3 Flash 的官方文档对应 Chat Completions。

其他服务商需提供 OpenAI 兼容的 Responses 或 Chat Completions 接口，且模型支持工具调用。

## 1. 运行环境

1. 打开「设置」→「梨花」，或点顶栏的「设置梨花」。
2. 「运行器」选择 DeepSeek Harness。
3. 「运行环境」为「未下载」时点「下载」。NipaPlay 下载固定版本的 Node.js 和 DSH，状态依次为下载中、校验中、正在安装、已就绪。

| 状态 | 处理 |
|---|---|
| 没能下载 | 「重试」；网络受限时在「运行环境选项」中更换镜像，或用「使用指定的运行环境」指向已有安装 |
| 这个平台暂时没有 | 当前系统和架构没有预置运行环境；在其他桌面设备上运行梨花，通过[组网](../use/devices.md)使用 |

## 2. 模型

1. 点模板按钮「DeepSeek」或「智谱」，填入提供方、地址、模型、接口、思考强度和该服务商所需的兼容开关。
2. DeepSeek 模板使用 Responses；切换「接口」为 Chat Completions 时，兼容开关随之切换。智谱的 Responses 使用另一地址，切换接口时需同时修改地址。
3. 「API key」填入服务商平台创建的密钥。密钥保存在系统凭据保险库中，保存后输入框显示「已保存」。
4. 「思考」设定推理强度（关、低、中、高），强度越高，响应越慢、费用越高。模板填入「高」。
5. 「保存」，然后「测试连接」。

## 3. 测试连接

「测试连接」向填写的地址发送一次小请求，请求中声明测试工具 `nipaplay_connection_check`。

| 接口 | 检查内容 | 通过时说明 |
|---|---|---|
| Responses | 要求模型调用测试工具；服务商拒绝指定工具时改为自选，仍要求实际调用 | 地址、密钥、模型正确，模型发出了工具调用 |
| Chat Completions | 声明测试工具，不要求调用 | 地址、密钥、模型正确，服务端接受工具声明 |

通过时显示「可以用 · N ms」。失败时显示原因：「密钥无效或没有权限」「账户余额不足或额度已用完」「模型名不存在」「端点不支持 Responses 接口」「此模型不支持工具调用」「未通过工具调用检查」「连不上服务器」「服务器响应超时」。

测试连接不检查图片输入。

## 4. 对话验证

打开对话，发送以下两条：

| 请求 | 预期 |
|---|---|
| 「看看现在 NipaPlay 的情况，播放器在放什么？」 | 回答上方出现「看 NipaPlay 的情况」「查状态」等工作步骤，展开可见工具输出 |
| 粘贴一张截图，「图里是什么？」 | 描述图片内容；服务商不支持图片时，对话中显示服务商返回的错误 |

回答没有工作步骤时，模型未调用工具，见[常见问题](../help/faq.md#连接测试成功但梨花不调用工具)。

## 费用与数据

- 模型费用由服务商结算。一项任务通常包含多轮工具调用，token 用量高于普通聊天。
- 任务所需的对话内容、工具结果、文件名、路径和附件发送给模型服务商，适用该服务商的数据政策。

## Codex 运行器

「运行器」选择 Codex 时：

- 使用「系统里的 Codex」，或在 NipaPlay 中指定路径；
- 「导入 Codex 配置」导入本机 Codex 的模型配置；
- Codex 只支持 Responses 接口。

上下文预算、压缩和插件的配置见 [DSH 高级配置](../advanced/dsh-config.md)。

---

上一篇：[下载与开启](install.md) · 下一篇：[第一次使用](first-day.md)
