# Codex 项目指引

本文件适用于仓库根目录及其所有子目录。项目名为「模型之间」，是使用用户自有 API Key 的 Flutter 多模型聊天应用。

## 产品与当前范围

- 当前交付重点是 Android；保留 iOS 工程，并让应用内界面在 Android 与 iOS 使用同一套 iOS 风格组件。不要按运行平台切换两套页面。
- 已实现文本聊天、流式回复、Markdown 回复、多话题、模型服务预设、自定义 API、表单、JSON 与扫码导入配置，以及全局和单模型提示词。
- 当前协议是 OpenAI 兼容 Chat Completions 和 Claude Messages。新增平台时先判断能否复用协议适配器，再增加专用实现。
- 尚未实现图片/文件发送、工具调用、同步、历史导入导出和正式发布签名。不要把 Android 构建成功写成 iOS 或商店发布成功。
- 产品功能路线与 RikkaHub 对照来源见 `TODO.md`；实施前重新核对现状与参考项目的最新说明。

## 代码地图

- `lib/main.dart`：应用入口、聊天状态、发送与流式回复、聊天页。
- `lib/chat_more_menu.dart`：聊天页右上角“更多”操作表，包含新对话、切换模型和模型服务。
- `lib/chat_model_title.dart`：聊天页顶部当前服务与模型标题，可点按切换模型。
- `lib/topic_screen.dart`：左侧会话抽屉，以及话题重命名、删除；底部设置入口。
- `lib/chat_model_selector.dart`：聊天页统一的服务与模型选择，支持最近使用、服务端列表和手动 ID。
- `lib/chat_scroll.dart`：流式回复时的底部跟随，用户滑离底部后保留阅读位置。
- `lib/chat_message_meta.dart`：气泡下的模型、耗时、Token 与字数展示。
- `lib/chat_loading_status.dart`：回复生成时的菊花与毫秒计时；计时器只更新状态行。
- `lib/provider_badge.dart`：服务预设图标与自定义服务字母徽标，在服务列表、聊天标题和消息信息中复用。
- `lib/message_copy.dart`：复制 Markdown 原文或包含 HTML 与纯文本的格式化内容；Android/iOS 原生剪贴板通道负责富文本。
- `lib/model_picker.dart`：聊天与服务配置共用的可搜索模型列表；大列表按 `平台/模型` 或 `家族-型号` 前缀折叠分组。
- `lib/settings_screen.dart`：模型设置、语言、换肤、关于及开源许可入口。
- `lib/app_preferences.dart`：本地语言、白天/黑夜/跟随系统和主题色偏好、界面文案翻译。
- `lib/provider_screen.dart`：服务预设、自定义服务、表单/JSON 编辑和模型列表。
- `lib/provider_qr_scanner.dart`：完整配置 JSON 二维码自动导入，以及纯 API Key 字符串扫码填入。
- `lib/prompt_screen.dart`：全局与单模型提示词设置。
- `lib/privacy_screen.dart`：本地数据与第三方请求说明、清空本地数据入口。
- `lib/ios_style.dart`：跨平台共用的 iOS 风格颜色、导航栏、分组行、主按钮。
- `lib/assistant_markdown.dart`：模型回复的 Markdown 展示。
- `lib/data.dart`：服务配置、话题、消息模型；SQLite 和密钥存储。
- `assets/provider_icons/`：本地服务图标及 Lobe Icons 的许可文件。
- `lib/api_client.dart`：HTTP 请求、SSE 解析和协议适配。
- `lib/voice_client.dart`：云端语音识别和合成的 OpenAI 兼容、MiMo、豆包语音协议适配；不得使用系统 ASR/TTS 代替。
- `lib/voice_settings_screen.dart`：独立语音提供商、文字服务密钥复用、识别/朗读选择、转写后自动发送和自动朗读设置。
- `lib/voice_recording_overlay.dart`：手机按住录音时的全屏浮层、实时振幅波纹和计时。
- `lib/watch_settings_screen.dart`：手机端的手表模型与播报开关。
- `lib/watch_chat.dart`：手机后台 Flutter 入口，把所选服务配置发给手表，执行手机优先的无落库语音/模型/朗读请求，并将手表离线问答同步进手机会话库；保留旧版手表的手机处理路径。
- `android/wear/`：独立 Wear OS APK，负责录音、路由选择、手表独立请求、展示回复和音频播放；`WatchPhoneRelay.kt` 处理手机网络路径，`WatchNetworkSelector.kt` 指定手表 Wi-Fi/蜂窝网络，所选密钥用 Android Keystore 加密保存。
- `android/app/.../MainActivity.kt` 与 `android/wear/.../WatchActivity.kt`：手机和手表通过静态 capability 检查另一端安装状态，并向缺失设备发送商店安装页跳转；未上架的测试包仍需分别安装。
- `android/app/src/main/kotlin/com/example/mulit_ai_flutter/WatchRequestListener.kt` 与 `WatchRequestWorker.kt`：Data Layer 处理手表配置请求、手机网络路径与问答同步；兼容旧版录音请求。
- `lib/voice_catalog.dart` 与 `lib/voice_catalog_picker.dart`：语音模型/音色候选、兼容服务 `/models` 查询和选择界面；候选不表示账号权限。
- `test/`：协议、配置、Markdown 和界面行为测试。
- `android/app/src/main/AndroidManifest.xml` 与 `res/xml/network_security_config.xml`：网络权限与明文连接范围。

## UI 约定

- 页面布局、导航、操作表和输入控件统一沿用 `ios_style.dart` 与 `Cupertino` 组件；`MaterialApp` 提供应用基础设施和 Markdown 所需的 Material 环境。避免在单个页面重新引入默认 Material 抽屉、列表项、浮动按钮或弹窗。
- 聊天页新对话先作为内存中的草稿显示；发送第一条消息时再将话题和消息一起写入 SQLite。切换草稿模型不应生成空白话题。网络失败后的“重试回复”只重新请求回复，不重复写入用户消息。
- 上次选中的文字服务 ID 和完整模型 ID 保存在本机 `settings` 表；冷启动恢复为新会话草稿，不自动创建话题。服务已删除时，从最近仍可用的话题或现有服务默认模型回退；手动输入的模型 ID 不依赖服务端列表验证。
- 首轮助手回复成功后，使用当前服务和模型发起一次短请求，根据首轮用户与助手内容生成会话标题；限制输入长度与输出 token，生成失败保留首条消息标题，且不得覆盖用户手动重命名。标题仅存本机 SQLite。输入框回车/发送键与发送按钮执行同一逻辑。
- 聊天页顶部保留左侧会话抽屉入口、可点按切换的当前服务与模型标题、右侧“更多”。边缘右滑也可打开会话列表；设置入口在抽屉右下角。“更多”放新对话、切换模型和模型服务，不重复放会话列表与设置。
- 服务端模型数量少时直接列出；大列表按 `平台/模型` 或 `家族-型号` 前缀分组，单独型号放“其他模型”；搜索仍覆盖完整列表，选中时保留完整模型 ID。
- 服务端模型列表按服务 ID 缓存在本机 SQLite `settings` 表中；进入选择页优先展示缓存，手动刷新成功后覆盖，刷新失败时保留旧列表。修改服务地址、协议或密钥后不得继续使用旧缓存，删除服务或清空本地数据时一并清除缓存。缓存包含模型 ID、接口地址、协议和更新时间，不含密钥。
- 新消息记录发送时的模型 ID；助手回复额外记录首段可见文字耗时、流式总耗时与服务端报告的输入/输出 Token。历史消息和未报告用量的服务保留空值，不推算为精确 Token。OpenAI 兼容流式请求可带 `stream_options.include_usage`，遇到明确不支持该字段的 400/422 响应时重试普通流式请求；Claude Messages 从 `message_start`/`message_delta` 读取用量。
- 新消息同时记录发送时的服务 ID、名称与图标预设，切换服务后仍按每条消息原来的服务展示；旧版本消息没有这些字段，不要用话题当前服务回填为确切来源。生成中隐藏气泡下的统计，回复结束后再展示。
- 气泡信息的五项显示开关存在 SQLite `settings` 表，只影响展示，不删除已保存的统计。输入 Token 指整次请求上下文，不是最后一条用户消息的 Token。复制原文保留 Markdown 标记；格式化复制提供 HTML 和可读纯文本，接收应用可自行选择粘贴格式。
- 语言、外观模式和主题色选择保存在 SQLite 的 `settings` 表。外观模式支持跟随系统、白天和黑夜；所有页面复用 `IosColors` 的动态语义色，不写死浅色背景与文字。新增可见文案时同步补充 `app_preferences.dart` 的英文翻译；模型 ID、用户内容和服务名称不要翻译。
- 先检查页面信息结构，再调整颜色与圆角。聊天、话题、服务配置都要保持同一视觉语言。
- Android 和 iOS 复用同一 widget 树；新增 UI 不使用 `Platform.isAndroid`、`Platform.isIOS` 等平台分支。系统状态栏、键盘、底部导航属于系统界面，可能不同。
- 改动 UI 后用 Android 模拟器截图检查欢迎页、已有聊天、话题页、服务列表和编辑页；检查长文本、Markdown 表格、键盘遮挡及返回路径。没有 iOS 构建或设备证据时明确说明。

## 数据和密钥

- 话题与消息正文保存在本机 SQLite，内容为明文；API Key 使用 `flutter_secure_storage`，不得写入 SQLite、源码、测试快照或日志。
- 提示词保存在 SQLite：全局一条，单模型按服务 ID 和模型 ID 区分。请求时全局内容在前、模型内容在后；OpenAI 兼容协议写入 system 消息，Claude Messages 写入顶层 system 字段。提示词不作为聊天消息落库。删除服务时同时删除该服务的模型提示词。
- 编辑已有服务时，空 `apiKey` 表示保留原密钥。表单与完整 JSON 两种模式都要可用，切换回表单时验证 JSON；空白自定义配置也必须能直接进入 JSON 导入。
- 扫码导入新服务时二维码必须包含非空 `apiKey`；复用 JSON 字段和 URL 校验，识别成功后直接保存。不要在日志、错误弹窗或测试快照中输出二维码原文。
- 平台预设的密钥输入框支持扫描仅包含 API Key 字符串的二维码，扫描结果先填入表单或 JSON 编辑框，用户保存后才持久化；不要把纯密钥二维码当作完整服务配置导入。
- 密钥说明要准确：应用不设中转服务器，不收集密钥到自有服务器；密钥仅在设备安全存储中持久化，但获取模型列表或聊天请求会将密钥直接发给用户配置的 API 服务商。不要使用“密钥绝不上传到任何地方”之类与实际请求流程冲突的文案。完整 JSON/二维码原文不持久化，非密钥配置字段写入本机 SQLite。
- 语音提供商的非密钥配置存在 SQLite `settings` 中，独立语音 API Key 存在安全存储；复用文字服务时只引用其服务 ID，不复制密钥。豆包语音与火山方舟文字聊天的密钥、资源权限不同，不自动复用。录音仅作临时文件，直接发给选定语音服务；转写结果默认直接发送，关闭 `voice_auto_send` 后等待用户确认；合成音频播放后删除。语音请求不得在重定向中转发密钥。
- 手机输入区左侧按钮切换文字与语音模式；语音模式中央按住录音，全局浮层显示音量波纹与时间，松开转写，上滑松开取消。手表也按住录音、松开转写。手机经配对 Data Layer 将所选文字和语音服务的配置与密钥发给手表；手表使用 Android Keystore 加密保存密钥。手机可达时优先由手机执行语音/模型/朗读请求，但不由手机后台落库；手机明确网络失败时，手表指定自身 Wi-Fi/蜂窝网络执行。手机不可达时先使用手表网络；期间手机恢复且手表网络失败时可再试手机。仅在无部分回答、失败可确认为网络故障时自动切换，超时状态不明或服务端配置错误不重发。自动发送关闭时手表先显示文字，确认后才请求模型。问答先保存在手表私有存储，重连后经 Data Layer 同步至手机 SQLite；无网络时明确失败，不声称跨账户云同步。手机数据清空不会自动清除离线手表数据。
- 手机检测到已连接但缺少应用的手表时，首次提示用户到手表设置页安装；用户选“稍后”后不针对同一节点重复弹窗，设置页仍可手动重查。手表启动或返回前台时检查配对手机应用；缺失时给出手机商店入口。商店跳转仅表示已发送打开请求，不代表安装成功；正式使用前两端仍需以相同应用 ID 和签名安装。
- 服务端错误展示须隐藏当前 API Key，并限制错误正文读取和展示长度；解析失败时不要直接显示可能包含密钥的原始响应。
- “清空所有本地数据”需经明确确认，并在模型回复或自动标题请求进行期间禁止执行；不得把清空入口的测试运行在含有用户数据的模拟器上。
- 非本机 API 地址使用 HTTPS。Android 模拟器访问宿主机服务用 `10.0.2.2`；`127.0.0.1` 和 `localhost` 指向运行应用的设备自身。这些本地地址可用于 HTTP 联调。网络请求直接从设备发到用户配置的服务。
- 模拟器可能已有用户的服务、密钥和聊天记录。不要用 `adb shell pm clear`、卸载应用或删除数据库作为常规测试步骤；只清理自己创建的临时服务和话题。

## 开发与验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
cd android && ./gradlew :wear:assembleDebug
```

有 Android 模拟器时可用 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 安装；重装不会清空应用数据。真实平台 API 请求必须区分于本地模拟接口验证，不要在没有真实密钥测试时宣称平台实测通过。

iOS 编译和设备验证需要完整 Xcode 与 CocoaPods；如果当前开发机只有 Xcode Command Line Tools，明确记录该限制，不要用 Android 构建结果代替 iOS 验证。

提交代码前先检查 `git status`、变更范围和 `git diff --check`。只提交本次工作涉及的文件；`build/`、`.dart_tool/` 等构建产物由 `.gitignore` 排除。

Git 提交信息统一使用简体中文。标题简明概括本次改动和新增内容；有需要注意的事项时，在正文中简要说明。不要写与实际变更无关的内容。
