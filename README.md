# 模型之间

一个使用自有 API Key 的本地优先聊天应用。当前版本面向 Android；应用内页面在 Android 和 iOS 共用同一套 iOS 风格界面。iOS 工程尚未构建或设备验证。

## 已实现

- 19 个服务预设，覆盖 OpenAI、Claude、Gemini、DeepSeek、GLM、千问、豆包、Kimi、MiniMax、百度千帆、腾讯混元、OpenRouter 等；按国内、国际、聚合与推理平台分组。选平台、粘贴密钥即可接入；地址和模型均可修改。
- 自定义 API：支持 OpenAI 兼容 Chat Completions 和 Claude Messages 两种协议。
- 服务配置同时支持表单与完整 JSON 导入，支持按服务端模型列表选择模型，也能手填模型 ID。
- 多话题聊天：新建、切换、重命名、删除；每个话题可选择服务与模型。
- 流式回复、停止生成、Markdown 回复渲染（标题、列表、表格、代码块等）、链接打开与原文复制。聊天记录保存在设备 SQLite 数据库；API Key 保存在系统安全存储中，不写入聊天数据库。
- iOS 风格的聊天页、话题页和服务配置页，Android 与 iOS 复用相同页面组件。
- 全局提示词和按「服务 + 模型 ID」设置的模型提示词。发送时先应用全局内容，再追加当前模型的内容；提示词不会显示在聊天记录中。

## 运行

```bash
flutter pub get
flutter run
```

首次进入时点「接入模型服务」，选择预设并填入对应平台的 API Key。然后创建新对话并发送消息。请求由手机直接发送到配置的 API 地址，不经过本项目的服务器。部分服务可能因账户权限、地域和模型可用性返回错误；可在服务配置中手动调整模型 ID。

提示词入口：聊天页右上角「模型服务」→「提示词」。全局提示词对所有模型生效；单模型提示词只对选定服务及模型 ID 生效。切换话题中的服务或模型后，会使用新组合对应的提示词。两者都保存在本机 SQLite，修改后从下一次发送开始生效。

自定义服务的 JSON 格式：

```json
{
  "name": "我的服务",
  "protocol": "openai_chat",
  "baseUrl": "https://api.example.com/v1",
  "model": "my-model",
  "apiKey": "my-key"
}
```

`protocol` 也可以填 `anthropic_messages`。`baseUrl` 是根地址，应用会追加 `/chat/completions` 或 `/messages`。默认要求 HTTPS；Android 模拟器访问宿主机时可用 `http://10.0.2.2:端口`。编辑现有服务时，`apiKey` 留空表示保留原密钥。

## 数据与当前边界

话题与正文以明文存于本机 SQLite；卸载应用会删除本地记录。Android 备份已关闭。密钥通过 `flutter_secure_storage` 写入系统安全存储。配置的服务地址能收到你发送的上下文与密钥，因此只应接入可信的服务。

服务图标来自 [Lobe Icons](https://github.com/lobehub/lobe-icons)，随应用本地打包；许可见 [assets/provider_icons/LICENSE](assets/provider_icons/LICENSE)。预设地址和模型随第三方服务变化，实际可用性以服务商及账户为准；没有真实 API Key 的平台不视为已实测。

当前版本仅发送文字消息，模型回复可以显示 Markdown，但尚不支持公式、HTML、图片上传或文件上传。工具调用、用量统计、历史导入导出及多设备同步尚未实现。iOS 工程保留，但尚未构建或设备测试。Android 发布包签名与商店上架不在当前版本范围内。

## 开发验证

```bash
flutter analyze
flutter test
flutter build apk --debug
```
