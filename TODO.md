# 产品待办

本清单记录「AI Link」与 RikkaHub 功能清单的差距及拟定顺序。手机端界面继续使用 Android/iOS 共用的 Flutter 组件。勾选前以代码、测试和实际运行结果核实，不将参考项目 README 的声明视为本项目的实现证明。

## Apple 平台验证与手表独立能力

- [x] **Debug 完整 Xcode 构建**：2026-10-03 已在 Xcode 27.0 构建 iOS Runner 与嵌入的 `AILinkWatch`，修复单目标 watchOS 配置及后台 Flutter 引擎初始化顺序；两端配对模拟器启动及配置同步通过。发布签名仍待验证。
- [ ] **配对设备端到端验证**：配对模拟器已验证两页界面和配置摘要同步；在 iPhone 与 Apple Watch 配对真机验证录音权限、WAV 传输、转写确认、流式回答、音频播放、手机后台唤醒、断连重试和历史入库。手表版目前通过 iPhone 执行请求，后台执行时间受系统限制。
- [ ] **Apple Watch 独立网络**：手机只负责配置；在手表 Keychain 保存必要凭据，直接调用支持的语音和文字协议。手机可达时优先手机网络，明确网络故障再切手表网络；手机不可达时独立请求。需先解决服务能力、密钥同步、上下文和离线同步，避免重复计费。参考 [Apple WatchConnectivity 官方说明](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) 与 [独立 watchOS 应用说明](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/)。
- [ ] **Apple 发布准备**：核对 Apple Developer 签名、App Store Connect、手表截图及线上隐私政策对 Apple Watch 数据流的描述。细节见 [Apple 平台说明](doc/ios/README.md)。

## 优先：聊天核心体验

- [ ] **图片与文件发送**：先支持图片，再支持常用文档。按协议分别构造多模态请求；文件需要区分可直接发送给模型、需要提取文本、以及不支持的情况。选择文件时验证类型和大小，发送前明确告知内容会直发所选 API 服务商。
- [ ] **模型能力提示**：为模型记录图片、文件等能力信息，支持服务端信息、已知预设和用户手动修正；能力未知时明确提示，不仅凭模型 ID 推断。接入不支持的模型时给出可操作的错误信息。
- [ ] **二维码导出服务配置**：与现有扫码导入格式兼容。默认导出不含 API Key 的配置；若用户主动选择包含密钥，明确提示二维码持有者可使用密钥，且不把二维码原文额外落库。
- [ ] **丰富回复渲染**：在现有 Markdown 标题、列表、表格和代码块基础上，增加数学公式、代码高亮和 Mermaid。验证长内容、深色模式、复制原文与格式化内容的表现。

## 其次：接入能力与进阶聊天

- [ ] **协议与请求配置**：评估 Google Gemini 原生协议适配；为自定义服务提供受控的请求头和请求体扩展，保持 API Key 安全存储及日志脱敏。
- [ ] **自定义智能体**：在现有全局及单模型提示词之外，提供可选择的角色配置；明确角色、模型和提示词之间的优先级。
- [ ] **工具、MCP 与联网搜索**：先完成工具调用和权限确认，再评估 MCP 及 Exa、Tavily 等搜索服务；在聊天记录中区分模型回复与工具结果。
- [ ] **跨会话记忆与 Prompt 变量**：跨会话记忆由用户主动开启，可查看、修改和删除；提示词变量可包含模型名称、时间等，并提供预览。不要将同一会话发送历史消息误称为跨会话记忆。

## 后续评估

- [ ] **AI 翻译**：明确是整段翻译、选中文本翻译还是聊天消息操作，再确定入口。
- [ ] **Web 访问**：评估账户、同步和密钥保护方案后再设计；当前应用只在设备本地存储聊天和密钥。
- [ ] **手机内 Linux 智能体工作区**：参考 RikkaHub 的 proot 工作区，待基础工具能力稳定后再判断产品价值与设备成本。

## 参考与现状

- [RikkaHub 中文 README](https://github.com/rikkahub/rikkahub/blob/master/README_ZH_CN.md)：以上参考功能来自其“功能特色”章节，核对日期为 2026-09-28；这是公开功能声明，并非逐项实测。
- 本项目现状以 [AGENTS.md](AGENTS.md)、[协议适配](lib/api_client.dart)、[Markdown 渲染](lib/assistant_markdown.dart) 和 [扫码导入](lib/provider_qr_scanner.dart) 为准。当前已支持两类聊天协议、文字流式回复、基本 Markdown、服务配置扫码导入、同一会话历史上下文、全局及单模型提示词；上述待办不重复这些基础能力。
- 语音第一版已接入云端识别与合成；仍需用真实服务账户和 Android 实机核验各服务的权限、音色和录音体验，尤其豆包资源 ID 的实际开通情况。
