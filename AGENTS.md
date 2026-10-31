# Codex 项目指引

本文件适用于仓库根目录及其所有子目录。项目名为「AI Link」，是使用用户自有 API Key 的 Flutter 多模型聊天应用。

## 产品与当前范围

- Android 与 iOS 手机端共用 Flutter 的 iOS 风格页面，不按运行平台切换两套页面；Wear OS 与 Apple Watch 使用各自的原生界面。macOS、Windows 与 Linux 共用桌面分栏。Apple 平台代码待完整 Xcode 构建及配对设备验证；Windows 尚未在 Windows 机器上运行过。
- 已实现文本聊天、流式回复、Markdown 回复、多话题、模型服务预设、自定义 API、表单、JSON 与扫码导入配置，以及全局和单模型提示词。
- 当前协议是 OpenAI 兼容 Chat Completions 和 Claude Messages。新增平台时先判断能否复用协议适配器，再增加专用实现。
- 已实现手机/桌面的图片、拍照入口（手机）和文件发送：图片/PDF 按协议直发，UTF-8 文本本地读取，其它格式不限后缀并原样发送，是否支持由模型或接口决定。不在本地解析 Office 文档。手机/桌面已提供默认关闭的 Agent 任务工具调用；MCP、跨设备云同步和历史导入导出尚未实现。附件流程与验证边界见 `doc/CHAT_ATTACHMENTS.md`。正式上传签名已在本机配置，但尚未在 Play Console 注册或上架；不要把 Android 构建成功写成 iOS 或商店发布成功。
- 产品功能路线与 RikkaHub 对照来源见 `TODO.md`；实施前重新核对现状与参考项目的最新说明。

## 代码地图

`lib/` 按功能域分目录，每个目录内聚一个功能：`core/` 基础设施与共享模型、`api/` 网络与协议、`chat/` 聊天主流程、`provider/` 服务配置、`voice/` 语音链路、`search/` 联网搜索、`watch/` 手表联动、`settings/` 设置与其它页面、`ui/` 通用 UI 基元。`lib/main.dart` 只保留入口与应用外壳。新增文件放进对应功能域；只有跨功能域复用才放 `ui/` 或 `core/`。`lib/` 内部导入统一写 `package:mulit_ai_flutter/<路径>.dart`，不用相对路径。

### 入口与外壳

- `lib/main.dart`：`main()`、手表后台入口 `watchBackgroundMain()` 与 `MaterialApp` 外壳；必须留在 `lib/` 根目录（`FLUTTER_TARGET`）。`main()` 在读取语言偏好之前调用 `configureDesktopSqlite()`。
- `lib/core/app_platform.dart`：`isDesktopApp`、`supportsApplePurchases`、`supportsWatchCompanion`、`supportsQrScan` 等平台能力判断；UI 不用 `Platform.isAndroid/isIOS` 分支。`supportsQrScan` 仅 Android、iOS、macOS 为真，Windows 与 Linux 不显示扫码入口，也不打开 `MobileScanner`。
- `lib/core/sqlite_desktop.dart`：Windows 与 Linux 在打开数据库前把 sqflite 换成 `sqflite_common_ffi`，并将数据库固定到 `getApplicationSupportDirectory()/databases`；`main()` 必须 await 初始化，不能使用依赖当前工作目录的 FFI 默认路径。原生 SQLite 由传递依赖 `sqlite3` 的 Dart build hooks 打进安装包，不要再加已经空转的 `sqlite3_flutter_libs`。单元测试不要调用 `configureDesktopSqlite()`，否则会换掉测试用的 method channel 工厂；路径与持久化测试使用独立的 `createDesktopDatabaseFactory()`。macOS 继续用 `sqflite_darwin`。

### 聊天（chat/）

- `lib/chat/chat_home.dart`：聊天页 `ChatHome` 与状态机；持有会话列表、发送与流式回复、录音与朗读状态。
- `lib/chat/incoming_share.dart`：Android/iOS 原生分享队列与附件批次导入；文字/链接作为文本附件，新对话默认不归属项目，已有草稿先确认，接收不发送也不创建话题。iOS 分享扩展仅保存至专用 App Group，用户打开主应用后接收，不主动唤起主应用；配置与验证见 `doc/INCOMING_SHARES.md`。
- `lib/chat/widgets/chat_welcome.dart`：空会话欢迎页。
- `lib/chat/widgets/chat_error_card.dart`：错误卡片与 `ChatErrorAction` 枚举。
- `lib/chat/widgets/message_bubble.dart`：单条消息气泡，含正文、搜索来源与气泡下统计。
- `lib/chat/widgets/chat_composer.dart`：底部输入区，语音/文字切换、按住说话与发送按钮。
- `lib/chat/widgets/desktop_attachment_drop.dart`：桌面聊天投递区与悬停反馈，忙碌或被页面遮挡时禁用；桌面「＋」直开文件选择器，macOS 拖入文件在私有复制期间临时开启并释放 security-scoped access。
- `lib/chat/widgets/chat_attachments.dart`：草稿和历史附件卡片、移除、图片缩放及文本预览；PDF 显示文件说明，不内置页面阅读器。
- `lib/chat/chat_more_menu.dart`：聊天页右上角“更多”操作表，包含新对话、切换模型、添加到项目（已有归属时为移动到项目）、消息设置和设置，不显示标题。
- `lib/chat/chat_model_title.dart`：聊天页顶部当前服务与模型标题，可点按切换模型。
- `lib/chat/topic_screen.dart`：会话抽屉/桌面侧栏、本地标题正文搜索、消息定位、置顶、项目筛选与会话移动，以及重命名、删除；底部设置入口。项目筛选由 ChatHome 持有并传入，不能仅放在抽屉的 State 中，抽屉关闭销毁后也要保留。选项目须同步未发送草稿归属；查看其它项目的旧会话时切换项目进入新草稿，不移动旧聊天。侧栏、更多和桌面快捷键新建均沿用当前项目筛选，首条发送与归属一起保存。列表分组标题直接显示当前筛选（全部对话/未归属项目/项目名），可点按切换；不再显示“最近”或搜索框下方的重复筛选行。
- `lib/chat/project_screen.dart`：项目选择与管理、独立说明/手动记忆、UTF-8 知识文件导入和笔记；手机/桌面复用。桌面路由使用 ChatHome 的详情导航器，保留会话侧栏。
- `lib/chat/widgets/knowledge_sources.dart`：展示实际提供给模型的文件与分段快照，不声称模型必然引用。
- 手表参与过的话题通过本机 `settings` 中的手表会话映射识别，侧栏显示手表图标；普通对话显示消息气泡。对话中有已保存的搜索来源时，在主图标右下角显示地球角标，不随当前搜索开关变化；手机和手表都参与过时保留手表图标。设置入口贴在抽屉左下角。
- `lib/chat/chat_model_selector.dart`：聊天页统一的服务与模型选择，支持最近使用、服务端列表和手动 ID。
- `lib/chat/chat_scroll.dart`：流式回复时的底部跟随，用户滑离底部后保留阅读位置。
- `lib/chat/chat_streaming_reply.dart`：生成中气泡独立订阅文本更新，避免每段流式文本重建聊天页与历史列表。
- `lib/chat/memory_coordinator.dart`：跨会话记忆任务的串行排队、分批总结、权限检查、超时和释放；`memory_profile.dart` 保留资料总结的纯函数。写回时在 SQLite 事务内校验开关、资料版本和话题存在性。
- `lib/chat/chat_context.dart` 与 `lib/chat/chat_context_screen.dart`：手机和桌面的上下文估算预算、最近完整轮次选择、超限提示与设置；不删除本机历史，规则和验证见 `doc/CHAT_CONTEXT.md`。
- `lib/chat/chat_message_meta.dart`：气泡下的模型、耗时、Token 与字数展示；同时定义 `SpeechPlaybackState`。
- `lib/chat/chat_loading_status.dart`：回复生成时的菊花与毫秒计时；计时器只更新状态行。
- `lib/chat/message_copy.dart`：复制 Markdown 原文或包含 HTML 与纯文本的格式化内容；Android/iOS 原生剪贴板通道负责富文本。
- `lib/chat/model_picker.dart`：聊天与服务配置共用的可搜索模型列表；大列表按 `平台/模型` 或 `家族-型号` 前缀折叠分组。
- `lib/chat/assistant_markdown.dart`：模型回复的 Markdown 展示。
- `lib/chat/desktop_chat.dart`：桌面分栏布局与键盘快捷键外壳。macOS 用 Command，Windows 与 Linux 用 Control。侧栏和聊天顶栏共用 `desktopToolbarHeight`；桌面聊天及会话行的更多操作通过 `ui/desktop_popup_menu.dart` 显示锚定按钮的小菜单，手机仍用操作表。Windows 原生 File 菜单只在点击时调用 `between_models/desktop_menu`，菜单文字里写着 Ctrl+N 与 Ctrl+,，但不注册 Win32 加速键，避免和 Flutter 快捷键各触发一次。格式化复制在 Windows 写入 CF_UNICODETEXT 与 `HTML Format`；通道失败时退回纯文本。窗口标题为 AI Link，默认 1100×760，最小 600×500。

### Agent（agent/）

- `lib/agent/agent_screen.dart`：设置开关默认关闭；管理页提供开关、独立上下文预算和任务记录；消息设置显示当前状态并跳转管理。开启后手机/桌面聊天直接使用 Agent，进度、暂停/继续和文件在 `chat_agent_card.dart` 展示；手表不自动变为 Agent。
- `lib/agent/agent_runner.dart`：单 Agent 工具循环，每次执行最多 12 轮/24 次工具尝试/5 分钟，累计额度不阻止手动继续；接近上限停用工具收尾、重复调用提前收尾，截断增输出预算及临时故障有限重试；请求诊断不保存原始响应或密钥；切换对话或关闭开关时暂停，返回手动继续。息屏和离开应用不暂停：Android 以前台服务保住进程，iOS 申请系统后台时间；系统挂起进程后回到前台会接着执行，不因此记成暂停。购买及服务地区规则仍适用。
- `lib/agent/agent_policy.dart`：本次额度、输出预留、重复调用检测和继续指令；`chat_feature_hints.dart` 在输入框上方只显示当前开启的功能小字。未完成任务发送“继续”复用原任务，不重复保存用户消息。源码参考与适配见 `doc/AGENT_ENGINE_REVIEW.md`。
- `lib/agent/agent_store.dart`：任务以 `agent_task:<UUID>` JSON 保存到既有 settings 表；成果在私有附件目录的 agent_artifacts 子目录，不进入普通附件孤儿清理；删除任务、关联对话或清空数据同步删除文件；关联对话的最终回复和任务状态在同一事务内保存，避免重复回复。
- `lib/agent/agent_context.dart`：Agent 独立预算键 `agent_context_window_tokens`，默认 32K、最高 1M；仅在请求副本中缩短工具正文摘录、移除较早完整对话轮次，保留工具 ID/参数/签名及完整落库记录。预算仍不足时暂停，可调预算后继续，不消耗本地失败轮次。聊天历史和附件按原协议临时组装，不把附件 Base64 写入任务记录。
- `lib/api/tool_call.dart` 与 `ModelApiClient.toolTurn()`：两类协议的完整非流式工具回合与关联结果；截断/无效调用不执行，保留协议续传字段。`lib/agent/web_reader.dart` 限制公开 HTTPS，检查并固定 DNS 地址以避免访问私网。范围和验证见 `doc/AGENT.md`。

### 核心数据（core/）

- `lib/core/project.dart`、`project_store.dart`：SQLite v7 项目/知识文档/分段、会话项目关联与置顶、标题正文搜索、本地中英文关键词检索。项目说明和记忆仅在手机/桌面的项目对话中使用，不读取或总结到全局记忆；移动/删除项目推进旧历史的记忆游标。知识正文和引用快照是本机明文；命中资料只发当前模型，不发向量服务或搜索服务。容量、迁移与验证见 `doc/PROJECT_SPACES.md`。

- `lib/core/data.dart`：服务配置、话题、消息模型；SQLite 和密钥存储。`database_migrations.dart` 按实际表结构补齐缺失列，迁移建表/建索引须可重复执行；旧构建可能降低版本标记而保留新表，不能只看版本号就无条件重建或加列。明确拒绝降级打开较新数据库，不清空或覆盖用户数据。
- `lib/core/chat_attachment.dart` 与 `lib/core/attachment_store.dart`：附件元数据与私有文件管理，SQLite v6 只新增可空 `attachments` 列；附件正文不写 Base64 入库。类型由文件内容识别：已知图片、PDF 与合法 UTF-8 文本按类型发送，其它非空文件原样保存为通用文件，是否支持由模型或接口返回决定；相册和拍照仍只接受 JPEG、PNG、GIF、WebP。每条图片与文件合计最多 9 个，单个附件 30 MB（图片按压缩后计算），单条消息与已选请求上下文总计 90 MB；相册在选择时按剩余数量限制，不支持限量的系统使用单选累加，图片统一参考 Luban 压缩。取消草稿、删除话题、清空数据及启动时孤儿清理须同步处理文件，不能删除用户选择的原文件。
- `lib/core/app_preferences.dart`：本地语言、白天/黑夜/跟随系统和主题色偏好；语言枚举与文案表已迁到 `lib/i18n/`，此处仅 re-export 保持旧导入路径可用。
- `lib/core/apple_purchases.dart`：Apple 内购状态与刷新。

### 本地化（i18n/）

- `lib/i18n/app_language.dart`：`AppLanguage` 枚举（`system`/`zh`/`zh-TW`/`en`），`code` 同时作为资源文件名与持久化值；`resolve()` 按系统 locale 解析（zh-Hant/HK/MO → zhTW），`languageSelfName()` 提供语言自名。
- `lib/i18n/strings.dart`：文案表载入与查表。启动时 `I18n.load()` 一次性读入全部语言；`T(key)`/`F(key, args)` 同步查内存表，回退链为「当前语言 → 简体中文 → key 本身」。`T` 具备幂等性：非 key 文本原样返回，因此上游已翻译的文本可安全再次经过 `T`。
- `assets/i18n/zh.json`、`en.json`、`zh-TW.json`：每语言一份独立配置，key 统一 `i18n.` 前缀，带参数文案写成 `{0}`、`{1}` 模板。
- **新增语言的完整步骤**：① 在 `AppLanguage` 增加枚举项（`code` 即文件名）；② 在 `assets/i18n/` 放入同名 JSON；③ 在 `I18n.languages` 预载列表登记。第 ③ 步可选，未登记则不会在启动时载入。
- **新增文案**：三份 JSON 同时补齐同名 key，源码里用 `T('i18n.x')` / `F('i18n.x', [...])`；模型 ID、用户内容、服务名称和品牌名不翻译。`assets/i18n/` 已加入 `pubspec.yaml` 的 assets。
- **文案表必须在首帧之前就绪**：`lib/main.dart` 的 `main()` 是 `async`，在 `runApp` 之前 `await AppPreferences.instance.loadLocalization()`。启动页（`lib/settings/startup_screen.dart`）在 `AppPreferences.load` 完成前就会渲染，若资源未载入会直接显示裸 key（减少动画时尤其明显）。该页用 `I18n.loaded` 守卫标语（`Visibility` + `maintainSize` 保留占位高度），`main()` 的预载是第二道防线。
- **后台 FlutterEngine 必须自行载入文案，且要随手机语言变化刷新**：`lib/watch/watch_chat.dart` 的 `startWatchWorker()` 在 `ready` 之前调用 `_refreshLanguage()`，并在**每次 `process` 请求前**再调一次。iOS `FlutterEngine.run(withEntrypoint:)` 与 Android `DartExecutor` 都会新建独立 engine，前台的静态文案表（`I18n._tables`）不共享过去；不加载就会把手表错误文案回传成裸 key。而 iPhone 的 `AppleWatchBridge` 启动后会**长期复用同一个 engine**，只在启动时读一次语言会让「先以英文启动、再把手机切成中文」之后的错误文案一直停留在英文，所以刷新必须按请求做。两端原生都只在收到 `ready` 后才下发请求（Android 侧有 20 秒超时），因此等待不会丢请求。
- **`supportedLocales` 必须登记全部繁体 locale**：`AppPreferences.supportedLocales = [Locale('zh'), zh_Hant_TW, zh_Hant_HK, zh_Hant_MO, Locale('en')]`，`AppPreferences.locale` 在繁体模式返回 `zh_Hant_TW`。只登记 `Locale('zh')` 时 `basicLocaleListResolution` 会把 `zh-Hant-TW` 归一到 `zh`，框架内置控件（复制/取消等）退回简体。注意解析顺序是「三位全匹配 → `lang_script` → `lang_country` → `lang`」：`zh_Hant_TW` 的 `countryCode` 为 `TW`，会先命中 `lang_country`，所以 `Locale('zh','TW')` 不能省略；澳门同理。澳门还有一个额外坑：框架 `getMaterialTranslation` 对**没有脚本标签**的 `zh` 只在国家为 HK/TW 时返回繁体，裸 `zh-MO` 会落到简体（复制按钮显示「复制」），必须靠带 `Hant` 的 `zh_Hant_MO` 接住——`lang_country` 匹配只比较 `languageCode` 与 `countryCode`，所以登记 `zh_Hant_MO` 即可同时命中 `zh-MO` 与 `zh-Hant-MO`。此约定与「手表只支持简中/英文」无关：`_syncWatchLanguage` 仍把繁体上报为 `zh`。
- **`presetForProvider` 需兼容历史服务名**：`ProviderPreset.name` 现在是翻译 key，但旧配置的 `name` 存的是当时语言下的译文（如 `GLM 智谱`）。`presetForProvider` 在 `presetId` 与 `baseUrl` 都匹配后，用 `I18n.lookupIn` 遍历 `I18n.languages` 把各语言译文还原回 key 再比对，否则这些配置会失去预设图标与新消息的预设元数据。

### 网络与协议（api/）

- `lib/api/api_client.dart`：HTTP 请求、SSE 解析和协议适配。

### 服务配置（provider/）

- `lib/provider/provider_screen.dart`：服务预设、自定义服务、表单/JSON 编辑和模型列表。
- `lib/provider/provider_badge.dart`：服务预设图标与自定义服务字母徽标，在服务列表、聊天标题和消息信息中复用。
- `lib/provider/api_key_help.dart`：文本和语音服务的官方密钥入口、三类教程链接及外部浏览器打开失败时的复制入口；自定义地址不冒用其他平台的密钥指引。
- `lib/provider/provider_qr_scanner.dart`：完整配置 JSON 二维码自动导入，以及纯 API Key 字符串扫码填入。

### 语音（voice/）

- `lib/voice/voice_client.dart`：云端语音识别和合成的 OpenAI 兼容、MiMo、豆包语音协议适配；保留云端协议；iPhone 可选择苹果系统识别与朗读，新安装默认系统语音，自动朗读默认关闭。`voice_selection.dart` 管理选择与默认值；系统音色 ID 保存在 `system_tts_voice_id` 并同步到 Watch，手表可本地覆盖，指定音色不可用时使用默认音色。`system_voice.dart` 和 iOS `SystemVoiceBridge.swift` 提供原生桥接。已有云端选择和明确关闭朗读的设置不得被覆盖。
- `lib/voice/voice_settings_screen.dart`：独立语音提供商、文字服务密钥复用、识别/朗读选择和自动朗读设置；发送或确认由录音手势决定。
- `lib/voice/voice_recording_overlay.dart`：手机按住录音时的全屏浮层、实时振幅波纹和计时。
- `lib/voice/voice_catalog.dart` 与 `lib/voice/voice_catalog_picker.dart`：语音模型/音色候选、兼容服务 `/models` 查询和选择界面；候选不表示账号权限。

### 联网搜索（search/）

- `lib/search/search_service.dart`：搜索请求与 `SearchSource` 模型。
- `lib/search/search_sources.dart`：气泡下的来源列表展示。
- `lib/search/search_settings_screen.dart`：搜索服务、开关与密钥设置。

### 手表联动（watch/）

- `lib/watch/watch_chat.dart`：手机后台 Flutter 入口，把所选服务配置发给手表，为 Wear OS 手机优先、Apple Watch 网络兜底执行无落库语音/模型/朗读请求，并将手表离线问答同步进手机会话库；保留旧版手表的手机处理路径。原生按顶层函数名 `watchBackgroundMain` 唤起后台 isolate，与文件路径无关，移动本文件不影响该入口。
- `lib/watch/watch_settings_screen.dart`：手机端的手表模型与播报开关。

### 设置与其它页面（settings/）

- `lib/settings/settings_screen.dart`：手机与桌面共用的设置页，包含模型设置、语言、换肤、关于及开源许可入口；桌面保留会话侧栏，不另建设置侧栏；设置内按与手机一致的层级进入 `ModelSettingsScreen` 等子页并逐级返回。设置一级页的「通用」统一收纳数据与隐私、语言、换肤和关于；数据与隐私在通用内独立成组，不在关于、模型设置或服务列表重复放置。
- `lib/settings/resource_library_screen.dart`：按本地日期列出各话题消息上已保存的附件；图片可预览，长按可定位到原消息或分享。手机用底部操作表，桌面用贴在文件旁的小菜单，并可在访达、资源管理器或文件管理器中打开该文件。模型回复目前不落附件，库里只出现消息上已有的文件。
- `lib/settings/prompt_screen.dart`：全局与单模型提示词设置。
- `lib/settings/memory_settings_screen.dart`：模型设置中独立的跨会话记忆入口，管理总开关、对话默认使用、资料编辑及清空；不归属提示词设置。
- `lib/settings/privacy_screen.dart`：本地数据与第三方请求说明、清空本地数据入口。
- `lib/settings/purchase_screen.dart`：内购页面。
- `lib/settings/startup_screen.dart`：共用 Flutter 动画启动页。

### 通用 UI（ui/）

- `lib/ui/ios_style.dart`：跨平台共用的 iOS 风格颜色、导航栏、分组行、主按钮。

- `assets/provider_icons/`：本地服务图标及 Lobe Icons 的许可文件。
- `android/wear/`：独立 Wear OS APK，负责录音、路由选择、手表独立请求、展示回复和音频播放；`WatchPhoneRelay.kt` 处理手机网络路径，`WatchNetworkSelector.kt` 指定手表 Wi-Fi/蜂窝网络，所选密钥用 Android Keystore 加密保存。
- `ios/AILinkWatch/`：SwiftUI Apple Watch 配套应用；系统识别模式使用 `TextFieldLink` 的系统听写/键盘输入并确认发送，系统朗读使用手表本地 `AVSpeechSynthesizer`，两者无需语音服务密钥但仍需文字模型配置。云端识别模式长按录音、松手发送、左上滑取消、右上滑转文字后确认，显示最近问答和可选的模型语音播放；语言跟随手机 App，外观跟随手表系统。经 WatchConnectivity 同步所选服务配置，密钥仅在手表 Keychain 保存；优先使用 URLSession 直接请求，手表网络明确不可用且手机可达时复用配对 iPhone 无落库接口。`WatchNetworkClient.swift` 适配文字与语音协议，`WatchPhoneRelay.swift` 关联请求阶段，`WatchNetworkConfiguration.swift` 管理安全配置、路由与确认同步；真实服务及 Wi-Fi/蜂窝待真机验证。
- `ios/Runner/AppleWatchBridge.swift`：iPhone 端 WatchConnectivity 与后台 Flutter worker 桥接；沿用 `WatchChatProcessor` 云端识别、聊天、可选合成及 SQLite 入库。Apple 平台待 Xcode 编译、后台唤醒和配对设备验证，不能仅凭 Swift 语法检查声明可运行。
- `ios/AILinkWatchWidgets/` 与 `ios/AILinkWatchShared/`：表盘复杂功能和智能叠放入口。2026-10-03 曾因账号及扩展签名未就绪暂关；2026-10-07 用户确认开发者账号已申请后恢复构建依赖和嵌入，并实现思考时的问题摘要、最近手表回复摘要与回答/语音状态。仅通过专用 Keychain Sharing 组共享状态、最多 141 字符摘要、语言和更新时间，Debug/Profile 与 Release 分组；原有凭据的应用私有组必须保留在 entitlements 第一项，扩展不得获得该组权限。不使用 App Groups，不分享完整服务配置或录音，不从扩展请求网络。流式更新按 5 秒合并请求，实际刷新由系统调度；中间状态过期后提示打开查看，不保证表盘实时滚动或应用后台持续运行。签名及设备验证范围见 `doc/ios/README.md`。
- 手表应用是手机应用的功能子集，界面语言跟随手机 App，支持中文和英文。手机选“跟随系统”时，同步手机实际使用的语言，不能改为跟随手表系统语言；手机切换语言、冷启动和恢复前台时发送最新设置。Wear OS 用持久化 DataItem，Apple Watch 用 applicationContext；手表离线保留最后收到的语言，重连补同步。外观仍跟随手表自身日夜模式。手机端的繁體中文不在手表支持范围内，`_syncWatchLanguage` 会按「非英文即中文」上报为 `zh`，手表显示简体中文；新增手表语言需同步改这里与两端原生资源。
- 手表按住录音时使用全屏浮层中的圆形录音弹窗，显示实时音量波形、计时和松开提示；左上滑时变红并在松手后取消，右上滑时显示转文字状态并在转写后等待确认，原位松手直接转写并发送。浮层只负责显示，不抢占聊天区域的长按手势。
- 两端手表设置提供本地保存的「新手模式 / 简洁模式」，默认新手模式。新手录音界面保留方向提示、波形、计时与松开提示，避免重复说明；简洁录音界面仅显示一个大语音图标及音量呼吸环，取消变红、转文字变绿。两种模式只改变录音反馈，长按、滑动、松手、0.6 秒误触过滤和转写确认行为完全相同。
- 两端手表双击聊天进入设置，双击设置返回聊天；设置页也可横向右滑返回，竖向滑动继续滚动内容。顶部只显示设置标题和返回手势说明，底部保留可点按的「返回聊天」入口。录音模式选项下用中英文解释显示内容的区别及手势相同。
- 手机（Android/iOS）和手表（Wear OS/Apple Watch）录音不足 0.6 秒视为误触：松开后静默忽略、清理临时录音并恢复输入状态，不显示录音太短提示、不请求转写或模型；达到 0.6 秒才进入正常流程。时长从实际开始录音计算，不包含权限弹窗或启动录音的等待。
- `android/app/.../MainActivity.kt` 与 `android/wear/.../WatchActivity.kt`：手机和手表通过静态 capability 检查另一端安装状态，并向缺失设备发送商店安装页跳转；未上架的测试包仍需分别安装。
- `android/app/src/main/kotlin/com/maxhall/ailink/WatchRequestListener.kt` 与 `WatchRequestWorker.kt`：Data Layer 处理手表配置请求、手机网络路径与问答同步；兼容旧版录音请求。
- `test/`：协议、配置、Markdown 和界面行为测试。测试全部用 `package:mulit_ai_flutter/<路径>.dart` 导入，因此 `lib/` 目录调整后测试也会一并编译校验。
- `test/flutter_test_config.dart`：`flutter test` 的全局钩子，在整套测试运行前注入文案表。**刻意不调用 `TestWidgetsFlutterBinding.ensureInitialized()`**：该 binding 会把 `HttpOverrides.global` 换成「所有 HTTP 请求返回 400」的桩，而本仓库大量协议测试依赖真实回环 `HttpServer`，提前初始化会让它们全部失败。文案表由 `test/i18n_assets.dart` 直接读 `assets/i18n/*.json`（不走 `rootBundle`，因此不需要 binding）。
- `test/translation_coverage_test.dart`：基于 Dart AST 的文案守卫。校验三份 JSON 的 key 集合一致、无空值与重复 key、源码 `T`/`F` 引用的 key 全部存在、界面中不再有未本地化的中文字面量、`T`/`F` 幂等性、`AppLanguage` 解析与扫描器自测。扫描器已知盲区：字符串插值内部的字面量无法用 AST 精确归属，需人工检查。
- `test/i18n_leak_test.dart` 与 `test/sqflite_stub.dart`：渲染级守卫，逐页断言界面不会直接显示 `i18n.*` key。`IosRow`/`IosSection`/`iosAppBar` 内部会对 title/subtitle/footer 调用 `T`，所以经它们传入的 key 安全；风险点在 `Text`、`SelectableText`、`CupertinoTextField.placeholder` 与 `TextEditingController` 的初始文本。`sqflite_stub.dart` 提供空数据库桩，让依赖 `ChatStore` 的页面渲染出空状态。
- `test/i18n_locale_test.dart`：用 `basicLocaleListResolution` 断言 `zh-TW`/`zh-HK`/`zh-MO` 解析到显式 `Hant` locale，简中与英文不受影响；并端到端 `await GlobalMaterialLocalizations.delegate.load(resolved)` 断言台/港/澳的 `copyButtonLabel` 都是「複製」、简体是「复制」。同时校验 `AppPreferences.locale` 与 `supportedLocales` 对齐、`AppLanguage` 持久化值可往返。
- `test/watch_worker_i18n_test.dart`：验证手表后台 worker 在发出 `ready` 之前已载入文案表，且**每次请求前会重新读取手机语言**。**必须用纯 `test()`，不能用 `testWidgets()`**——`testWidgets` 运行在 FakeAsync 中，平台通道的真实异步回调不会被推进，`ready` 永远等不到而挂起。`flutter_test_config.dart` 注入的文案表不覆盖此场景：测试内先 `I18n.resetForTesting()`，再断言 worker 自行载入后 `I18n.loaded` 为 true。向 worker 投递请求用 `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(channel.name, StandardMethodCodec().encodeMethodCall(MethodCall('process', args)), (_) {})`；用 `kind: 'bogus'` 触发「请求无效」分支即可观察当前语言，无需网络与凭据。`test/sqflite_stub.dart` 的 `installEmptyDatabaseStub(settings: {...})` 按引用持有 Map，测试中途改它即模拟「手机改了设置」。
- `android/app/src/main/AndroidManifest.xml` 与 `res/xml/network_security_config.xml`：网络权限与明文连接范围。
- `release.sh`、`android/key.properties.example`、`android/key.test.properties`、`localConfig/ai-link-test.jks`、`doc/google_play/`：本地正式/测试签名打包和 Google Play 上架资料。测试签名及配置允许入库，其密码视为公开信息；正式 `android/key.properties`、`localConfig/ai-link-upload.jks`、正式密码和构建产物绝对不得提交。正式手机和手表使用包名 `com.maxhall.ailink`；普通 Debug 与 `--test` 包使用 `com.maxhall.ailink.debug`、名称「AI Link Debug」和同一测试签名，可与正式包并存；同一套手机与手表包必须共用包名和签名；`./release.sh` 出正式 AAB，`./release.sh --test` 出测试 APK。
- 官方网站为 `https://www.tools24.uk/app/ai-link`，公开隐私政策为 `https://www.tools24.uk/app/ai-link/privacy`；上架前核对线上政策与最终安装包行为一致。

## UI 约定

- 手机启动时先显示与品牌图标一致的原生启动画面，再显示 `lib/settings/startup_screen.dart` 的共用 Flutter 动画页；设置读取与聊天初始加载在此期间执行，完成后淡出进入聊天。遵循本地外观偏好与系统减少动画设置，不在恢复前台时重复显示闪屏。
- 页面布局、导航、操作表和输入控件统一沿用 `ios_style.dart` 与 `Cupertino` 组件；`MaterialApp` 提供应用基础设施和 Markdown 所需的 Material 环境。避免在单个页面重新引入默认 Material 抽屉、列表项、浮动按钮或弹窗。
- 聊天页新对话先作为内存中的草稿显示；发送第一条消息时再将话题和消息一起写入 SQLite。切换草稿模型不应生成空白话题。网络失败后的“重试回复”只重新请求回复，不重复写入用户消息。
- 上次选中的文字服务 ID 和完整模型 ID 保存在本机 `settings` 表；冷启动恢复为新会话草稿，不自动创建话题。服务已删除时，从最近仍可用的话题或现有服务默认模型回退；手动输入的模型 ID 不依赖服务端列表验证。
- 首轮助手回复成功后，使用当前服务和模型发起一次短请求，根据首轮用户与助手内容生成会话标题；限制输入长度与输出 token，生成失败保留首条消息标题，且不得覆盖用户手动重命名。标题仅存本机 SQLite。输入框回车/发送键与发送按钮执行同一逻辑。
- 聊天页顶部保留左侧会话抽屉入口、可点按切换的当前服务与模型标题、右侧“更多”。边缘右滑也可打开会话列表；设置入口在抽屉左下角。“更多”放新对话、切换模型、添加到项目（已有归属时为移动到项目）、消息设置和设置，不显示标题；当前对话的记忆开关放在消息设置中，同一页可进入跨会话记忆的全局设置。
- 服务端模型数量少时直接列出；大列表按 `平台/模型` 或 `家族-型号` 前缀分组，单独型号放“其他模型”；搜索仍覆盖完整列表，选中时保留完整模型 ID。
- 服务端模型列表按服务 ID 缓存在本机 SQLite `settings` 表中；进入选择页优先展示缓存，手动刷新成功后覆盖，刷新失败时保留旧列表。修改服务地址、协议或密钥后不得继续使用旧缓存，删除服务或清空本地数据时一并清除缓存。缓存包含模型 ID、接口地址、协议和更新时间，不含密钥。
- 新消息记录发送时的模型 ID；助手回复额外记录首段可见文字耗时、流式总耗时与服务端报告的输入/输出 Token。历史消息和未报告用量的服务保留空值，不推算为精确 Token。OpenAI 兼容流式请求可带 `stream_options.include_usage`，遇到明确不支持该字段的 400/422 响应时重试普通流式请求；Claude Messages 从 `message_start`/`message_delta` 读取用量。
- 新消息同时记录发送时的服务 ID、名称与图标预设，切换服务后仍按每条消息原来的服务展示；旧版本消息没有这些字段，不要用话题当前服务回填为确切来源。生成中隐藏气泡下的统计，回复结束后再展示。
- 气泡信息的五项显示开关存在 SQLite `settings` 表，只影响展示，不删除已保存的统计。输入 Token 指整次请求上下文，不是最后一条用户消息的 Token。复制原文保留 Markdown 标记；格式化复制提供 HTML 和可读纯文本，接收应用可自行选择粘贴格式。
- 语言、外观模式和主题色选择保存在 SQLite 的 `settings` 表。外观模式支持跟随系统、白天和黑夜；所有页面复用 `IosColors` 的动态语义色，不写死浅色背景与文字。新增可见文案时在 `assets/i18n/` 的三份 JSON 同时补 key，并在源码里写 `T('i18n.x')`；模型 ID、用户内容和服务名称不要翻译。枚举字段、Map 值、默认参数等「数据载体」可以保存 key，但消费点必须再经过 `T`——`IosRow`/`IosSection`/`iosAppBar` 会自动翻译，其余渲染点需显式调用，`test/i18n_leak_test.dart` 会拦截漏翻译。
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
- 语音提供商的非密钥配置存在 SQLite `settings` 中，独立语音 API Key 存在安全存储；复用文字服务时只引用其服务 ID，不复制密钥。豆包语音与火山方舟文字聊天的密钥、资源权限不同，不自动复用。录音仅作临时文件，直接发给选定语音服务；手机与新版手表的松手动作决定转写后直接发送还是等待确认；`voice_auto_send` 仅保留供旧版手表协议兼容，不再提供设置开关；合成音频播放后删除。语音请求不得在重定向中转发密钥。
- 手机输入区左侧按钮切换文字与语音模式；语音模式中央按住录音，全局浮层显示音量波纹与时间，左滑松手取消、右滑松手转文字后等待编辑确认、原位松手转写后直接发送。手表长按聊天区域录音，左上滑松手取消、右上滑松手转文字后确认、原位松手转写后直接发送；返回起点恢复直接发送。手机经配对 Data Layer 将所选文字和语音服务的配置与密钥发给手表；手表使用 Android Keystore 加密保存密钥。手机可达时优先由手机执行语音/模型/朗读请求，但不由手机后台落库；手机明确网络失败时，手表指定自身 Wi-Fi/蜂窝网络执行。手机不可达时先使用手表网络；期间手机恢复且手表网络失败时可再试手机。仅在无部分回答、失败可确认为网络故障时自动切换，超时状态不明或服务端配置错误不重发。手表选择右上滑时先显示识别文字，确认后才请求模型。问答先保存在手表私有存储，重连后经 Data Layer 同步至手机 SQLite；无网络时明确失败，不声称跨账户云同步。手机数据清空不会自动清除离线手表数据。
- Android Keystore 和强制指定 Wi-Fi/蜂窝规则专指 Wear OS。Apple Watch 用 Keychain 保存所选服务凭据，URLSession 路由由 watchOS 自行选择（可能经过 iPhone 代理），不使用低层接口强制选网。Wear OS 手机优先，Apple Watch 手表请求优先、手机网络兜底；Apple 请求超时、连接状态不明、权限错误或部分回答不自动换路。问答由手表保存并按最早待同步序号传至手机；SQLite 幂等保存后确认，重连不重复入库。手机清空数据不自动清理手表；Apple 可在手表设置明确确认清除配置、密钥和问答，清除后须手动同步配置。每次启动尝试同步手机配置，等待 WatchConnectivity 激活后发送；同步失败保留上次 Keychain 缓存，手动同步立即发起新请求，不被正在进行的自动同步阻挡。有效空配置表示撤销服务，不继续使用旧密钥。录音与合成音频是临时文件，用后删除。普通构建与本地接口测试不能替代独立 Wi-Fi/蜂窝、真实服务和后台运行的配对真机验证。
- 手机端首次安装或启动时不主动提醒安装手表应用；用户进入「设置 → 手表」后可手动检查安装状态并打开安装入口。手表依赖手机端完成配置，启动或返回前台时检查配对手机应用；缺失时提醒安装，Wear OS 提供手机商店入口，Apple Watch 提示在 iPhone 安装并打开 AI Link。商店跳转仅表示已发送打开请求，不代表安装成功；正式使用前两端仍需以相同应用 ID 和签名安装。
- 服务端错误展示须隐藏当前 API Key，并限制错误正文读取和展示长度；解析失败时不要直接显示可能包含密钥的原始响应。
- “清空所有本地数据”需经明确确认，并在模型回复或自动标题请求进行期间禁止执行；不得把清空入口的测试运行在含有用户数据的模拟器上。
- 非本机 API 地址使用 HTTPS。Android 模拟器访问宿主机服务用 `10.0.2.2`；`127.0.0.1` 和 `localhost` 指向运行应用的设备自身。这些本地地址可用于 HTTP 联调。网络请求直接从设备发到用户配置的服务。
- 模拟器可能已有用户的服务、密钥和聊天记录。不要用 `adb shell pm clear`、卸载应用或删除数据库作为常规测试步骤；只清理自己创建的临时服务和话题。
- 从旧包名 `com.example.mulit_ai_flutter` 改到 `com.maxhall.ailink` 会产生新的应用沙盒；重装新包不能自动迁移旧 SQLite 和安全存储。测试时保留旧包及其数据。

## Firebase 统计

- Android/iOS 正式手机版使用原生 Firebase Analytics 自动事件；Android 禁用广告 ID 收集并移除广告标识符权限，iOS 使用 SPM 的 `FirebaseAnalyticsCore`，不链接 IdentitySupport。Debug/Profile 和 Android `--test` 停用统计；手表不接入。
- Firebase 客户端配置位于 `android/app/google-services.json` 与 `ios/Runner/GoogleService-Info.plist`，可入库；服务账号私钥不可入库。新增埋点不得携带聊天、提示词、API Key、录音、模型服务地址或错误响应原文。更新统计范围时同步应用内及官网中英文隐私说明，不把构建通过写成 Firebase 控制台收数成功。

## 开发与验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
cd android && ./gradlew :wear:assembleDebug
```

有 Android 模拟器时可用 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 安装；重装不会清空应用数据。真实平台 API 请求必须区分于本地模拟接口验证，不要在没有真实密钥测试时宣称平台实测通过。

iOS Debug 使用 `com.maxhall.ailink.debug` 和「AI Link Debug」，watchOS Debug 使用 `com.maxhall.ailink.debug.watchkitapp` 并关联 Debug iPhone；Release 保留正式标识。iOS/watchOS 编译和设备验证需要完整 Xcode 与 Apple 平台 SDK，并完成 Flutter 插件依赖集成；如果当前开发机只有 Xcode Command Line Tools，明确记录该限制，不要用 Swift 语法检查或 Android 构建结果代替 Apple 平台验证。

发布构建运行 `./release.sh`，会先分析和测试，再从未入库的 `android/key.properties` 使用同一个上传密钥生成手机和手表 APK/AAB；无参数时同时构建 Android、macOS 和 iOS/Apple Watch，本机没有 iOS 分发证书就跳过 iOS 并继续（显式 `--platform ios` 才当错误），结束时打印各平台成功/失败/跳过与本地产物路径的汇总。`--platform android|ios|macos|windows|mobile|all` 可只构建所需平台（`mobile` 为 Android + iOS，不含 macOS）。`all` 不含 Windows：Flutter 不能从 macOS 交叉编译 Windows，`--platform windows` 只在 Windows 主机上执行 `flutter build windows --release` 并归档 zip。本地测试运行 `./release.sh --test`，用 `android/key.test.properties` 生成两端 APK。不要把本机 Dart 测试通过写成 Windows 应用已经跑起来。默认仅本地归档；`--push-website` 上传正式 APK 到 OSS 并同步 HomeTools 的 `/api/v1/ai-link/release`，`--push-android` 同时同步官网和 Google Play，`--push-ios` 用 `scripts/appstore_upload.py`（Xcode 自带 `altool`）把正式 IPA 上传 App Store Connect 供 TestFlight 使用、不自动提审。`--push-mobile` 等价于 `--push-android --push-ios`：同步官网，并上传 Google Play 与 App Store Connect。`--push-all` 构建 Android、iOS、macOS 和 GitHub Actions Windows，把手机/Wear OS APK、macOS DMG 与 Windows 安装包上传 OSS，并把下载地址写入官网；同时上传 Google Play 与 App Store Connect。未指定 `--platform` 时按发布开关推导要构建的平台：`--push-android`/`--push-website` 取 Android，`--push-ios` 取 iOS，`--push-mobile` 或两者同时给出取 `mobile`，`--push-all` 取全端。只发布 APK 会整份替换官网发布记录，电脑端地址需用 `--push-all` 重新写入。官网须先接受 `macosDownloadUrl` 与 `windowsDownloadUrl`。App Store Connect 凭据放 `localConfig/appstore-connect.env`（模板 `scripts/appstore_connect.env.example`），上传前会联网校验凭据并核对 IPA 内手机与手表标识和版本；`altool` 走系统网络设置，不读 `http_proxy`。AI Link 发布信息使用独立 Redis key，不覆盖 Tools24；发布 Token 与 OSS 凭据保存在忽略的 `localConfig` 中。APK/AAB 分别保存签名校验、R8 映射和 Dart 符号。正式版与测试版使用不同包名和签名，可同时安装且数据独立；普通 Debug 与 `--test` 共用测试包名和签名，可覆盖更新。旧包数据不自动迁移，不得通过卸载或清空用户数据强行切换。密钥和密码必须离线备份，不使用 debug 签名冒充发布包。Google Play 隐私政策、Data safety、AI 内容举报流程、真实截图和设备测试见 `doc/google_play/README.md`，未完成项不能写成已上架。

桌面联合归档用 `./release.sh --platform desktop`：本机 macOS 与 GitHub Actions Windows 使用相同提交、版本、构建号及 Flutter 版本，产物统一保存在本次归档目录。`scripts/windows_remote_release.py` 要求干净且已推送的分支、`gh` 已登录及默认分支已有 `.github/workflows/ai-link-windows.yml`；不自动提交或推送。Windows 产物下载后校验元数据及 ZIP 内容，任务失败则本次构建失败，已归档的 macOS 产物保留。`all` 保持原有范围，联合桌面构建需显式指定 `desktop`。

独立构建参数：`./release.sh --github-windows` 只调用 GitHub Actions 构建 Windows 并下载 ZIP；`./release.sh --build-all` 在 Mac 上构建 Android 手机/Wear OS、iOS/Apple Watch、macOS 和远程 Windows，统一归档与校验和。`--build-all` 缺少 iOS 分发签名时必须报错，不能跳过 iOS。两个参数互斥，不能与 `--platform` 或 `--test` 同用；不带上传开关时不发布到官网或商店。原有默认构建、`--platform all` 及单平台行为保持不变。

Windows 安装包：`scripts/package_windows.ps1` 调用 Inno Setup 编译 `windows/installer/ai-link.iss`，生成 `AI-Link-Setup-<版本>+<构建号>.exe`，与完整 ZIP 一起归档及计算校验和。GitHub 工作流自动安装 Inno Setup，本机构建需自行安装。微软 VC++ 运行库从官方地址下载并校验 Authenticode 签名后封装进安装包；安装需要管理员权限。安装 AppId 固定为 `com.maxhall.ailink.windows`，升级复用安装位置，卸载不删除用户数据库和密钥目录。安装包自身没有代码签名。下载脚本必须同时核对元数据、完整 ZIP 和带版本号 EXE，不能将缺失安装包的构建写成成功。

最终分发包须集中复制到每次归档目录根目录，命名统一为 `AI-Link-<phone|wear|macos|windows|ios>-<版本号>-<提交哈希>+<构建号>.<格式>`；macOS/Windows/iOS 子目录原始包继续保留。`archive_final_package` 负责复制及加入根目录产物清单，`SHA256SUMS` 与结束汇总引用该清单，App Store 上传引用根目录 IPA。Windows 根目录 `.exe` 是安装包，子目录仍使用 `AI-Link-Setup-<版本号>+<构建号>.exe` 原名。

发布汇总须打印从脚本启动开始的总耗时（时分秒及总秒数），包括远程构建等待和上传；`print_summary` 同时将 `elapsedSeconds` 写入 `release-info.txt`，保持一次性打印/写入。Android 官网与 Google Play 发布参数统一为 `--push-android`，`--push-mobile` 等价于 `--push-android --push-ios`。`--push-all` 在此基础上同时发布 macOS 与 Windows 的官网下载地址。

`./install-dev.sh` 通过 `--mode release|debug` 统一控制所选 Android 手机/Wear OS、iOS/Apple Watch 和 Mac，默认 Release；不提供分平台模式参数。Android Release 强制使用正式签名配置，Debug 使用测试包名及测试签名；失败重试命令保留同一模式。只覆盖安装，不卸载或清空数据。

提交代码前先检查 `git status`、变更范围和 `git diff --check`。只提交本次工作涉及的文件；`build/`、`.dart_tool/` 等构建产物由 `.gitignore` 排除。

Git 提交信息统一使用简体中文。标题简明概括本次改动和新增内容；有需要注意的事项时，在正文中简要说明。不要写与实际变更无关的内容。
