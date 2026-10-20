# 手机联网搜索

## 配置与使用

已配置的官方 DeepSeek 文字服务会自动出现在联网搜索列表，直接读取该文字服务的当前 API Key，无需再次添加搜索服务或输入密钥。尚未设置默认搜索服务时会自动选用一个可用的 DeepSeek 文字服务；有多个时可在「默认搜索服务」切换。联网开关仍由用户主动开启，已明确选择「无」的默认项会保留。

1. 如需独立配置，进入「设置 → 联网搜索 → 添加搜索服务」，选择博查、Tavily、Exa 或 DeepSeek。
2. 名称和完整搜索接口地址自动填写。点击配置页的「申请 API Key」跳转官方控制台，注册 / 登录后创建密钥并填回；「查看价格与免费额度」可打开官方计费说明。搜索服务不填写模型 ID。编辑同一服务、同一地址时留空保留密钥，更换类型或地址时必须重新填写。
3. 按需选择 3 / 5 / 10 个结果及时间范围。Tavily 的深入模式使用 `advanced`，Exa 使用 `auto`；普通模式分别使用 `basic` / `fast`。博查始终请求网页摘要。DeepSeek 普通模式使用 `summary` / `snippet`，深入模式通过 `need_content: true` 请求网页正文，正文缺失时回退摘要；时间范围转换为 `after:YYYY-MM-DD` 查询语法。
4. 可点击「测试搜索」：发送固定查询 `Flutter`，可能计费，不保存配置。保存后第一项服务自动成为默认，之后可在默认服务行切换。
5. 回到聊天，在右上角「更多 → 消息设置」中开启「联网搜索」后发送问题。默认关闭，开关保存到本机；开启时检查默认服务与密钥，缺少配置则跳转联网配置页，配置完成后返回即开启，未完成则保持关闭。「更多 → 联网搜索」直接进入配置页。
6. 手机直接查询搜索服务，然后把资料交给当前文字服务生成回答；支持现有 OpenAI 兼容与 Claude Messages。点击回答中的链接，或展开「搜索来源」查看标题与链接。右上角「更多 → 消息设置」可直接调整消息统计、复制与朗读按钮的显示。

## API Key 申请与费用

博查、Tavily、Exa 说明核对于 2026-10-05，DeepSeek 核对于 2026-10-20；配置页按所选服务显示申请入口、费用类型与额度说明。网址使用系统浏览器打开；无法打开时可复制网址。页面不会自动注册账号或领取额度。

| 服务 | API Key 申请入口 | 免费情况 | 官方说明 |
| --- | --- | --- | --- |
| 博查 | [API KEY 管理](https://open.bochaai.com/api-keys) | 按量付费，使用前需充值或领取可用赠送额度；免费额度由活动和账号决定，不保证每个账号都有。 | [服务条款第 5 节](https://open.bochaai.com/terms-of-service)、[官方价格页](https://bocha-ai.feishu.cn/wiki/JYSbwzdPIiFnz4kDYPXcHSDrnZb) |
| Tavily | [官方控制台](https://app.tavily.com/) | 每月 1,000 免费积分，无需绑定信用卡；普通搜索每次 1 积分，深入搜索每次 2 积分；更多用量需付费。 | [Credits & Pricing](https://docs.tavily.com/documentation/api-credits) |
| Exa | [API Keys](https://dashboard.exa.ai/api-keys) | 每月 10 美元免费额度，另有 10 美元新账户奖励，无需添加付款方式；额度按接口用量消耗，更多用量需按量付费。 | [官方价格页](https://exa.ai/pricing) |
| DeepSeek | [API Keys](https://platform.deepseek.com/api_keys) | 使用 DeepSeek API Key，无需模型 ID；按成功且有结果的搜索请求计费，与模型调用分别计费，当前公开价格为每千次 5 元。 | [搜索计费说明](https://api-docs.deepseek.com/zh-cn/guides/search#%E8%AE%A1%E8%B4%B9) |

免费额度不是无限免费，搜索费用与文本模型费用分别计算；额度、账号条件和价格可能调整，以服务商官网及账号实际额度为准。博查公开价格文档本次未能直接抓取，因此不在应用中写固定单价或免费赠送数量。

## 第一版范围

- 每次请求只搜索一次，当前问题截取前 1000 个 Unicode 字符作为查询；DeepSeek 总上限为 128 个 Unicode 字符，启用时间范围时预留日期操作符长度，再截取问题，三端一致。尚未做依赖前文的搜索词改写、模型自主多轮搜索、网页点击阅读或服务商原生搜索。
- 最多 10 条来源，每条摘录最多 2000 个 Unicode 字符；这只是用于回答的网页证据，不声称读取了全文。来源由真实搜索结果提供，正文引用由文本模型生成，不代表逐条事实校验。
- 搜索失败、空结果、无密钥或格式错误会终止本次回答，并提供搜索配置和重试入口。用户可关闭搜索再重试；重试只请求回答，不重复写入用户消息。
- 停止按钮同时取消搜索和模型请求。流式用量参数兼容重试复用同一份检索资料，不再次搜索。自动会话标题不搜索。
- Android/iOS 手机共用 Flutter UI。手机联网开关及所选搜索配置和密钥自动同步到 Wear OS / Apple Watch；两端设置页显示状态、提供商和搜索服务。手表使用手机转发或独立网络时，都先搜索再请求文本模型。离线保留上次配置，重连补同步；手机关闭或删除默认搜索服务后同步关闭。旧手表配置没有搜索字段时保持关闭。搜索服务不需要模型 ID，设置页显示实际服务类型。
- 手表问答保留正文中的来源链接，随问答同步回手机；独立手表路径暂不保存手机式可展开来源摘录。搜索完成后模型失败不自动换路，避免重复搜索计费。

## 数据与安全

复用文字服务时仅保存 `textProviderId` 引用与搜索选项，不复制密钥；文字服务的 Key 更新后，聊天、测试搜索与手表同步均读取最新值。删除来源文字服务会清除关联搜索选项，并关闭该服务的联网选择。仅自动复用官方 `https://api.deepseek.com` 文字服务，搜索地址固定为官方 Search API；自定义地址与聚合平台不能仅凭名称或预设图标复用密钥。

非密钥配置与开关保存到 SQLite settings；搜索密钥保存在手机系统安全存储，并经配对通道同步到所选手表，Wear OS 使用 Keystore 加密、Apple Watch 使用 Keychain。Wear OS 的持久化 DataItem 只保存配置变化标记，含密钥快照使用配对 Message 通道；离线重连后请求最新快照。Apple Watch 沿用 applicationContext 同步，并将密钥保存在 Keychain。开启后，当前问题和搜索密钥发给搜索服务；检索资料发给当前模型服务。请求不经过 AI Link 自有中转服务器。错误提示不显示服务商原始响应，请求不跟随重定向，不记录密钥、查询或网页正文日志。

来源标题、链接、摘录和发布时间保存在助手消息的 `search_sources` 字段，数据库从 v4 原地升级到 v5，旧消息保持无来源。后续聊天上下文可带已有来源的标题与 URL，不重复注入全部摘录。删除搜索服务保留历史来源；清空本机全部数据会同时删除配置、来源和密钥。网页资料作为不可信证据，提示模型忽略其中的指令。

应用内与本仓库中英文隐私草稿已补充搜索数据流。公开官网隐私政策需在发布前同步；本次未部署官网。

## 接口依据与验证

- [博查 Web Search](https://open.bochaai.com/)：`POST https://api.bochaai.com/v1/web-search`，Bearer Key，`query` / `count` / `summary` / `freshness`。
- [Tavily Search](https://docs.tavily.com/documentation/api-reference/endpoint/search)：`POST https://api.tavily.com/search`，Bearer Key，`query` / `max_results` / `search_depth` / `time_range`。
- [DeepSeek Search](https://api-docs.deepseek.com/zh-cn/guides/search)：`POST https://api.deepseek.com/v1/tools/search`，Bearer Key，`query` / `count` / `need_content`，解析 `results` 的 `summary` / `snippet` / `content` / `date`。仅接入搜索接口，未增加 Fetch 或模型自主工具调用。
- [Exa Search](https://exa.ai/docs/reference/search)：`POST https://api.exa.ai/search`，`x-api-key`，`query` / `numResults` / `type` / `contents` / `startPublishedDate`。

协议、失败阻断、重定向、响应限制、取消、用量兼容和来源保存使用本地模拟接口验证；没有真实服务商密钥时不能据此声明真实平台可用、搜索质量或账单验证通过。

### 本次验证（2026-10-05）

- `flutter analyze` 无问题，`flutter test` 全部 112 项通过，其中新增 15 项搜索协议、存储和界面测试。
- Android 手机 Debug、Wear OS Debug 和 iOS Simulator Debug 构建通过；不代表配对手表或商店发布验证。
- Android 模拟器保留已有数据，使用临时本地搜索 / 文本接口完成“配置测试 → 搜索 → 模型回答 → 来源落库 → 重新打开”链路。确认标题请求不搜索、来源链接与长标题、Markdown 表格和长文本正常显示，检查欢迎页、已有聊天、话题、服务列表与编辑页、配置页键盘及中文浅色 / 英文深色界面。临时服务和话题已删除，已有服务与聊天数据前后对比一致。
- 测试搜索服务和测试文字服务均使用虚拟密钥；真实博查、Tavily、Exa 账号请求与计费尚未验证。

### 配置入口与聊天菜单补充验证

配置页已增加 API Key 申请、官方计费页面及免费额度说明，随服务类型切换；费用政策核对见上表。「更多」菜单提供新对话、切换模型、消息设置、模型设置、语音服务和联网搜索入口；联网开关位于消息设置中，输入框上方移除联网按钮。联网开关在发送、搜索、录音、转写或配置切换期间不可修改。

补充改动后，静态分析、112 项完整测试及 29 项菜单 / 搜索界面回归测试通过，Android Debug 与 iOS Simulator Debug 构建通过。独立临时 Android 模拟器截图确认输入区布局、「更多」菜单、消息设置跳转及博查 / Tavily 申请与费用说明；官网跳转参数通过界面测试验证。未使用真实搜索密钥请求服务。

最新菜单调整后，静态分析、115 项完整测试和 32 项界面回归测试通过，Android Debug 与 iOS Simulator Debug 构建通过。独立临时 Android 模拟器确认六项菜单顺序、消息设置标题、联网开关未配置时跳转，以及模型设置、语音服务和联网搜索配置入口。开关测试覆盖缺少服务、缺少密钥、已有配置、补齐配置后返回开启及关闭保存。

### 手表同步与隐私入口补充验证

- 手机保存联网开关、切换默认搜索服务、编辑配置或密钥、删除服务后，主动发送最新手表快照；启动和恢复前台补同步。测试覆盖开启、关闭、旧快照默认关闭和服务撤销。手机转发请求使用手表快照中的开关与服务 ID。
- 119 项 Flutter 完整测试及静态分析通过；Android 手机、Wear OS Debug 和包含手表配套应用的 iOS Simulator Debug 构建通过。Wear OS JVM 搜索协议测试和 Swift 本地接口测试通过；Swift 验证三个搜索服务分别给 OpenAI / Claude 提供证据，搜索失败阻断模型请求。连接拒绝可安全换路，搜索完成后的模型失败不自动重搜；超时和连接重置不视为安全重试。
- 独立 Android 测试沙盒使用虚拟密钥验证 Keystore 加密保存、关闭及撤销搜索配置、替换默认服务；原生手表设置页在 454 × 454 测试布局显示「已开启 / QA Exa / Exa」，与文字、语音字段形式一致。当前 Wear OS 模拟器多次启动退出，本次布局检查在普通 Android 测试镜像中运行原生手表 APK，不代表圆屏 Wear OS 或配对设备验证。
- 关于页「数据与隐私」新增「隐私协议」，用系统浏览器打开 `https://www.tools24.uk/app/ai-link/privacy`。英文翻译、准确跳转参数测试及 Android 页面截图检查通过；实际点击启动 Chrome，首次运行引导不属于应用页面。
- 未验证真实配对设备的 Data Layer / WatchConnectivity 同步、后台唤醒、独立 Wi-Fi / 蜂窝和真实搜索账号计费。测试使用独立临时模拟器，未清空已有用户模拟器的数据；本次未提交、推送或部署官网隐私政策。

### DeepSeek 接入（2026-10-20）

- 增加 DeepSeek 搜索预设、官方密钥与计费入口，补齐简体中文、繁体中文及英文说明；沿用独立搜索配置和安全存储，不增加模型 ID 或 Fetch 调用。
- Flutter、Wear OS 和 Apple Watch 均适配 `query` / `count` / `need_content`；按 Unicode 码点限制查询长度，日期操作符包含在 128 字符上限内。正文不可用时依次回退长摘要和短摘要，并读取 `date` 保存发布日期。
- `flutter analyze` 无问题，完整 Flutter 回归 227 项通过；最终搜索协议与存储回归 24 项通过，覆盖两类聊天协议的搜索证据注入、配置保存及密钥隔离。Wear OS 17 项 JVM 测试通过，Swift 本地接口测试通过，包含 DeepSeek 两类聊天协议、长 Unicode 查询及正文回退。
- Android 手机 Debug、Wear OS Debug 和包含 Apple Watch 的 iOS Simulator Debug 构建通过。
- 本次未使用真实 DeepSeek 密钥，未验证实际搜索质量、账户权限、计费或配对真机网络。当前未安装 Android 模拟器镜像，未完成 Android 页面截图检查。

### 直接复用文字服务（2026-10-20）

- 官方 DeepSeek 文字服务直接成为可选搜索服务，配置页显示来源并隐藏重复的 Key 输入；保留原有独立搜索配置及默认选择。自动来源仍可保存结果数量、时间范围和深入模式。
- Android 手机 Debug 与包含 Apple Watch 的 iOS Simulator Debug 构建通过。完整 Flutter 回归 229 项通过，静态分析无问题；补充存储回归覆盖自动默认、明确选择无、Key 更新、缺失或删除来源、地址修改失效、不复制密钥以及手表快照使用最新 Key。未调用真实 DeepSeek 服务，Android 模拟器截图与配对真机验证仍未完成。
