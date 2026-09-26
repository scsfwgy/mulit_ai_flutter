# 模型之间

一个使用自有 API Key 的本地优先聊天应用。当前版本面向 Android，代码保留 Flutter 的其他平台工程，尚未验证 iOS。

## 已实现

- OpenAI、Claude、DeepSeek、GLM、千问预设：选平台、粘贴密钥即可接入；地址和模型均可修改。
- 自定义 API：支持 OpenAI 兼容 Chat Completions 和 Claude Messages 两种协议。
- 服务配置同时支持表单与完整 JSON 导入，支持按服务端模型列表选择模型，也能手填模型 ID。
- 多话题聊天：新建、切换、重命名、删除；每个话题可选择服务与模型。
- 流式回复、停止生成、复制回复。聊天记录保存在设备 SQLite 数据库；API Key 保存在系统安全存储中，不写入聊天数据库。

## 运行

```bash
flutter pub get
flutter run
```

首次进入时点「接入模型服务」，选择预设并填入对应平台的 API Key。然后创建新对话并发送消息。请求由手机直接发送到配置的 API 地址，不经过本项目的服务器。部分服务可能因账户权限、地域和模型可用性返回错误；可在服务配置中手动调整模型 ID。

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

当前版本支持纯文本对话。图片、文件、Markdown 富文本、工具调用、用量统计、历史导入导出及多设备同步尚未实现。iOS 工程保留，但尚未构建或设备测试。Android 发布包签名与商店上架不在当前版本范围内。

## 开发验证

```bash
flutter analyze
flutter test
flutter build apk --debug
```
