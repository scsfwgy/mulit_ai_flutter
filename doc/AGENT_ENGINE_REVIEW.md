# Agent 核心逻辑对照与修正

核对日期：2026-10-31。本次直接读取以下公开源码及协议文档，保留 Dart 单 Agent 循环，没有嵌入完整框架或新增运行时。首版主要依据协议文档，未逐项对照这些开源实现；这次补齐了这一步。

## 已读的实现与采用的规则

| 参考 | 观察到的处理 | AI Link 的对应做法 |
| --- | --- | --- |
| [DeepSeek Harness agent loop](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/core/agent-loop/src/agent.ts) | 将正常结束、输出上限、请求错误分开；工具执行失败仍结算已有调用 | 保留停止原因、已报告用量和检查点；截断结果不进入工具执行；待执行工具及关联结果持久化 |
| [Harness 请求重试](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/llm/llm-retry/src/index.ts) | 按错误类别决定是否重试，等待可取消 | 网络中断、429/5xx、服务端中断采用有限重试和可取消等待；400/鉴权等不会盲目循环 |
| [Harness 工具结果修剪](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/compaction/compaction-tool-result-pruner/src/index.ts) | 确定性地缩短过大工具正文，同时保留头尾和结构顺序 | 仅缩短请求副本的正文摘录，保留来源元数据、工具 ID/参数和原始本机记录；不声称做了模型总结 |
| [OpenCode 步数上限处理](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/runner/max-steps.ts)及[执行步骤](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/runner/step.ts) | 上限时停用工具、输出已有成果与未完成项；工具错误回传并结算 | 每次执行尽量保留最后一轮文字收尾，以协议 `tool_choice: none` 停用工具；标记阶段结果。无效工具参数作为关联工具错误回传供模型修正 |
| [OpenCode 输出预算](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/model-request.ts)、[重试策略](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/model-retry.ts) | 输出预算受窗口剩余空间约束，失败请求与成功结果分开 | 初始输出预留按窗口取 4K–16K；检测截断后在窗口允许范围内增至最多 64K，最多自动重试两次；所有尝试计入本次请求上限，未知用量不伪造 |
| [DeepSeek 思考与工具调用](https://api-docs.deepseek.com/guides/thinking_mode/)及[停止原因](https://api-docs.deepseek.com/api/create-chat-completion/) | 思考输出也占输出额度，工具请求需回放思考状态；有多类停止原因 | 保存原生 reasoning 字段、Claude 签名思考块；连续任务恢复同服务/同模型的状态。官方 DeepSeek 历史普通聊天若未采集思考状态，将已有回复作为原用户轮次里的引用资料，不伪造 reasoning |

以上为设计规则的借鉴和适配，不代表运行过这两个完整项目，也不代表采用其全部能力。

## 截图中的问题

1. `12/12` 是应用当时的任务累计硬上限，不是模型上下文上限。旧逻辑到上限直接失败，也无法继续。现改为每次手动执行最多 12 次请求、24 次工具尝试、5 分钟；接近次数上限尽量收尾，超时或待执行工具超额则暂停。继续执行获得新的本次额度，累计用量保留。
2. 旧“未返回完整有效调用或回答”覆盖了输出截断、网络错误、非预期停止原因与 HTTP 拒绝。截图无法反推出那一次的真实响应。固定 `max_tokens=4096` 对思考模型存在截断风险；现在分开处理，并记录 `finish_reason`、输出预算、HTTP 状态与已报告用量，不保存原始错误响应或凭据。
3. 输入“继续”原先会新建任务，只有聊天文本而没有前一任务的工具检查点。现对当前未完成任务的“继续/继续任务/continue/resume”直接恢复，不重复插入用户消息、重跑已完成工具或生成第二份文件。若上次已给出阶段回答，后续消息作为新一轮任务，沿用聊天中的阶段结论。

## 本次界面和配置

- 普通聊天和 Agent 的独立预算选择都增加 512K、1M。1M 表示 1,048,576 Token 的本地预算，服务端真实模型窗口及账号能力仍决定请求能否接受；不强制把默认 32K 改成 1M。
- 输入框下方改为 11px 的次要色功能提示，仅显示当前启用的联网搜索、可用的自动朗读、Agent、当前对话使用的全局记忆；全部关闭时不占高度。项目对话不显示全局记忆。
- 联网搜索开关同时约束普通聊天和 Agent。关闭后输入框不再显示搜索，Agent 也不再提供网页搜索；打开且已配置搜索服务时，由模型按需调用。任务管理通过消息设置/设置进入。

## 验证边界

实际验证记录见 [Agent 使用与验证](AGENT.md)。测试覆盖两类协议、输出截断与停止原因、工具参数修复、预算收尾、重复调用、旧任务恢复、签名与 reasoning 回放、独立 1M 预算和功能提示布局。没有使用真实服务商 Key，不能据此承诺所有模型的工具选择质量或真实站点效果。
