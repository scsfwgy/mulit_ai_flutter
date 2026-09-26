# Codex 项目指引

本文件适用于仓库根目录及其所有子目录。项目名为「模型之间」，是使用用户自有 API Key 的 Flutter 多模型聊天应用。

## 产品与当前范围

- 当前交付重点是 Android；保留 iOS 工程，并让应用内界面在 Android 与 iOS 使用同一套 iOS 风格组件。不要按运行平台切换两套页面。
- 已实现文本聊天、流式回复、Markdown 回复、多话题、模型服务预设、自定义 API、表单与 JSON 配置，以及全局和单模型提示词。
- 当前协议是 OpenAI 兼容 Chat Completions 和 Claude Messages。新增平台时先判断能否复用协议适配器，再增加专用实现。
- 尚未实现图片/文件发送、工具调用、同步、历史导入导出和正式发布签名。不要把 Android 构建成功写成 iOS 或商店发布成功。

## 代码地图

- `lib/main.dart`：应用入口、聊天状态、发送与流式回复、聊天页。
- `lib/topic_screen.dart`：话题列表与重命名、删除。
- `lib/provider_screen.dart`：服务预设、自定义服务、表单/JSON 编辑和模型列表。
- `lib/prompt_screen.dart`：全局与单模型提示词设置。
- `lib/ios_style.dart`：跨平台共用的 iOS 风格颜色、导航栏、分组行、主按钮。
- `lib/assistant_markdown.dart`：模型回复的 Markdown 展示。
- `lib/data.dart`：服务配置、话题、消息模型；SQLite 和密钥存储。
- `assets/provider_icons/`：本地服务图标及 Lobe Icons 的许可文件。
- `lib/api_client.dart`：HTTP 请求、SSE 解析和协议适配。
- `test/`：协议、配置、Markdown 和界面行为测试。
- `android/app/src/main/AndroidManifest.xml` 与 `res/xml/network_security_config.xml`：网络权限与明文连接范围。

## UI 约定

- 页面布局、导航、操作表和输入控件统一沿用 `ios_style.dart` 与 `Cupertino` 组件；`MaterialApp` 提供应用基础设施和 Markdown 所需的 Material 环境。避免在单个页面重新引入默认 Material 抽屉、列表项、浮动按钮或弹窗。
- 先检查页面信息结构，再调整颜色与圆角。聊天、话题、服务配置都要保持同一视觉语言。
- Android 和 iOS 复用同一 widget 树；新增 UI 不使用 `Platform.isAndroid`、`Platform.isIOS` 等平台分支。系统状态栏、键盘、底部导航属于系统界面，可能不同。
- 改动 UI 后用 Android 模拟器截图检查欢迎页、已有聊天、话题页、服务列表和编辑页；检查长文本、Markdown 表格、键盘遮挡及返回路径。没有 iOS 构建或设备证据时明确说明。

## 数据和密钥

- 话题与消息正文保存在本机 SQLite，内容为明文；API Key 使用 `flutter_secure_storage`，不得写入 SQLite、源码、测试快照或日志。
- 提示词保存在 SQLite：全局一条，单模型按服务 ID 和模型 ID 区分。请求时全局内容在前、模型内容在后；OpenAI 兼容协议写入 system 消息，Claude Messages 写入顶层 system 字段。提示词不作为聊天消息落库。删除服务时同时删除该服务的模型提示词。
- 编辑已有服务时，空 `apiKey` 表示保留原密钥。表单与完整 JSON 两种模式都要可用，切换回表单时验证 JSON；空白自定义配置也必须能直接进入 JSON 导入。
- 非本机 API 地址使用 HTTPS。Android 模拟器访问宿主机服务用 `10.0.2.2`；`127.0.0.1` 和 `localhost` 指向运行应用的设备自身。这些本地地址可用于 HTTP 联调。网络请求直接从设备发到用户配置的服务。
- 模拟器可能已有用户的服务、密钥和聊天记录。不要用 `adb shell pm clear`、卸载应用或删除数据库作为常规测试步骤；只清理自己创建的临时服务和话题。

## 开发与验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

有 Android 模拟器时可用 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 安装；重装不会清空应用数据。真实平台 API 请求必须区分于本地模拟接口验证，不要在没有真实密钥测试时宣称平台实测通过。

iOS 编译和设备验证需要完整 Xcode 与 CocoaPods；如果当前开发机只有 Xcode Command Line Tools，明确记录该限制，不要用 Android 构建结果代替 iOS 验证。

提交代码前先检查 `git status`、变更范围和 `git diff --check`。只提交本次工作涉及的文件；`build/`、`.dart_tool/` 等构建产物由 `.gitignore` 排除。
