# AI Link iPhone 与 Apple Watch

## 已接入的代码

- iPhone 沿用 Flutter 的同一套聊天、服务配置、语音和本地 SQLite；`ios/Runner/AppleWatchBridge.swift` 在后台 Flutter engine 中复用 `WatchChatProcessor`。
- Xcode 工程增加 `AILinkWatch` SwiftUI watchOS target，并嵌入 iPhone Runner；bundle ID 为 `com.maxhall.ailink.watchkitapp`，配套 iPhone ID 为 `com.maxhall.ailink`，最低 watchOS 10。Debug 的 iPhone ID 为 `com.maxhall.ailink.debug`，watchOS ID 为 `com.maxhall.ailink.debug.watchkitapp`，名称均为「AI Link Debug」，与 Release 使用独立标识；Debug 已通过完整 Xcode 构建与配对模拟器启动；Release 签名与真机验证仍待完成。
- Apple Watch 按住录制 16 kHz、16 位、单声道 WAV，原位松手转写并发送，左上滑取消，右上滑转文字并等待确认。识别/聊天/合成分别优先由 `WatchNetworkClient` 使用 URLSession 请求，手表网络明确不可用且手机可达时再通过 iPhone 无落库接口处理。文字支持 OpenAI 兼容 Chat Completions 与 Claude Messages；语音支持 OpenAI、MiMo 和豆包。
- 选定服务的完整配置经 WatchConnectivity applicationContext 同步，API Key 仅保存在手表 Keychain（AfterFirstUnlockThisDeviceOnly、不同步 iCloud）；手机 UserDefaults 只缓存不含密钥的显示摘要。手表保留最近 50 条问答及最多 100 条未确认同步记录，后者不随显示历史裁剪。每条问答具有会话 UUID、turn UUID 和序号，手机 SQLite 事务保存并确认后，手表才删除待同步记录。录音/合成音频使用临时文件。界面语言跟随手机 App，外观跟随手表系统。
- `AILinkWatchWidgets` 的 WidgetKit 复杂功能源码已实现，**2026-10-03 按用户要求暂时关闭默认构建和嵌入**，等待 Apple Developer 账号与扩展签名准备完成。`Runner` → `AILinkWatch` 的默认构建链不再包含此扩展，普通手机/手表调试无需为新扩展生成描述文件；暂勿单独运行 `AILinkWatchWidgets` Scheme。
- 扩展最低 watchOS 10，支持圆形、矩形与行内复杂功能；矩形样式也支持智能叠放。启用后点击通过本地 URL 打开聊天页，即使 App 停在设置页也会返回聊天；首次使用保留操作引导。入口只显示麦克风图标与「AI Link」，不读取设置、聊天、音频或密钥，不请求网络、不自动录音，无需 App Groups。Debug/Profile 使用 `com.maxhall.ailink.debug.watchkitapp.widgets` 与 `ailink-watch-debug://chat`；Release 使用 `com.maxhall.ailink.watchkitapp.widgets` 与 `ailink-watch://chat`，开发版和正式版入口分开。

- 界面沿用两页聊天与设置：长按屏幕录音、双击进入设置、滑动阅读；右上滑转写后等待确认。自动播报可在手表单独设置。离开录音页或前台取消录音，实际录音不足 0.6 秒静默忽略。设置提供需明确确认的「清除手表配置和问答」，同时删除 Keychain、最近问答及待同步记录；清除后屏蔽缓存配置，直到用户手动同步。

## 当前限制

- URLSession 在 watchOS 上自行选择 iPhone 代理、Wi-Fi 或蜂窝，应用不使用不受支持的低层接口强制选网。独立请求为前台任务，系统挂起或终止应用可能导致失败；手机后台 Flutter 处理同样受运行时间限制。超时状态不明时不换路、不自动重发。语音接口只有明确的 DNS/拒绝连接错误才允许换路，普通 HTTP 客户端异常按状态不明处理。
- 2026-10-03 已在 Xcode 27.0 构建 iOS/watchOS Debug，安装到配对的 iPhone 17 与 Apple Watch Ultra 4 模拟器，并验证页面导航、连接与配置摘要同步。真实语音服务、后台长请求、音频播放及配对真机尚未验证。Apple 官方说明模拟器不支持 `transferFile(_:metadata:)`，录音与合成音频的文件传输需用配对真机验证。
- Apple 版公开发布前需核对并更新线上隐私政策：配对通道同步所选密钥、Apple Watch Keychain、安全存储和第三方直连、手表问答与确认同步、两端分别清理。应用内数据与隐私已更新；此次不修改或部署官网。
- watchOS App 与复杂功能扩展当前版本号固定为 `1.0.0 (1)`；每次 iPhone 版本提升时应一并更新两者的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。Debug/Profile 已配置本机开发团队，Release 签名与 App Store Connect 仍待配置。

## 后续重新启用复杂功能

关闭原因：本机 Xcode 尚无可用开发者账号，新扩展缺少描述文件，会导致 `./install-dev.sh --platform ios` 的 Profile 真机签名失败。功能源码、扩展 target、编译配置与嵌入对象均保留；此前尝试的 App Groups 能力已经完全移除。

关闭后验证（2026-10-03）：`flutter build ios --profile` 已使用现有开发签名完成手机与手表构建，`codesign --verify --deep --strict` 通过；最终安装包不含复杂功能 `.appex`。iOS 配对模拟器构建也通过。此次未安装到真机；该结果证明原有签名构建恢复，不代表新扩展签名已解决。

账号准备好后，先完成下文「新扩展的真机签名」，再在 `ios/Runner.xcodeproj/project.pbxproj` 中恢复 `AILinkWatch` target 的两处引用（位置已有“复杂功能暂关”注释）：

```text
buildPhases 中加入：
AA2200000000000000000025 /* Embed App Extensions */,

dependencies 中加入：
AA2200000000000000000027 /* PBXTargetDependency */,
```

两项必须一起恢复：前者把 `.appex` 嵌入手表 App，后者确保先构建并签名扩展。重新构建后检查 `Runner.app/Watch/AILinkWatch.app/PlugIns/AILinkWatchWidgets.appex`，并在配对真机测试表盘添加、智能叠放与点击跳转；通过后更新本文件、README 和 TODO 中的暂关备注。首次模拟器验证已看到矩形小组件正确渲染；表盘圆形/行内显示、点击回到聊天及真机签名尚未完成验证。

## 添加表盘快捷入口（重新启用后）

1. 安装包含 `AILinkWatchWidgets.appex` 的新版手表 App；Debug/Profile 在系统应用列表中显示为「AI Link Debug」。
2. 选用支持复杂功能的表盘，长按表盘 →「编辑」→ 向左滑到「复杂功能」→ 点击圆形、矩形或行内位置 → 选择「AI Link」。按表冠保存，点击入口进入聊天页。可用位置取决于表盘；并非每个表盘都支持这些样式。
3. 智能叠放：从表盘向上滑动或转动表冠 →「编辑」→「＋」→「AI Link」→ 添加矩形小组件，按需置顶。部分 watchOS 版本通过长按叠放进入编辑。
4. 在聊天页长按屏幕说话；复杂功能只打开应用，不开始录音。中文和英文均显示应用名称，进入应用后仍沿用手机同步的语言。

## 新扩展的真机签名

复杂功能扩展是独立签名目标，现有手机与手表的开发描述文件不能替代它。若出现 `No Accounts` 或 `No profiles for ...watchkitapp.widgets`：

1. 在 Xcode → Settings → Accounts 登录属于当前开发团队的 Apple Developer 账号；已有团队 ID 或缓存描述文件不等于 Xcode 已登录。
2. 打开 `ios/Runner.xcworkspace`，为 `Runner`、`AILinkWatch`、`AILinkWatchWidgets` 三个目标选择同一 Team，启用 Automatically manage signing。使用其他团队时，安装脚本也要传 `--team <TeamID>`。
3. 在 Xcode 选择配对的真机组合，用 Profile 配置构建一次，让 Xcode 为新的扩展标识生成并下载开发描述文件，再运行 `./install-dev.sh --platform ios`。

当前实现无需 App Groups；如果仍提示旧 App Groups entitlement 不匹配，确认使用最新工程并在 Xcode 执行 Product → Clean Build Folder 后重建，这不会清空设备应用数据。账号登录和真机签名尚未通过本次模拟器验证确认。

## 真机开发安装脚本

运行 `./install-dev.sh --platform ios`，按序号选择真实 iPhone/iPad、Apple Watch，多个序号用逗号或空格分隔；`--all` 安装到全部 Apple 真机，`--target phone` / `--target watch` 只选择手机或手表。设备须先通过 Device Hub 配对、信任 Mac 并开启开发者模式。

默认构建 Profile 版，手机可脱离调试器从桌面启动。Profile 与 Debug 共用开发标识 `com.maxhall.ailink.debug` / `com.maxhall.ailink.debug.watchkitapp`、名称「AI Link Debug」与同一开发团队，覆盖安装保留应用数据；Release 仍使用正式标识。需要 Flutter 断点或热重载时传 `--ios-mode debug`，再通过 `flutter run` 或 Xcode 启动手机应用。

脚本读取 Xcode Debug 配置的开发团队，也可用 `--team <TeamID>` 或 `IOS_DEVELOPMENT_TEAM` 指定；通过临时 xcconfig 对手机与手表统一签名，不改写项目中的团队设置。两端由同一次 Flutter iOS 构建生成，脚本校验标识、配套关系与签名后分别覆盖安装。只安装手表时也会准备配套 iPhone 的构建依赖，避免直接构建 Watch Scheme 时缺少 Flutter framework。

## 在具备完整 Xcode 的机器验证

1. 安装完整 Xcode，确认 `xcode-select -p` 指向其 `Contents/Developer`，安装 iOS/watchOS SDK 和 Flutter 所需的插件依赖工具。
2. 运行 `flutter pub get`、`flutter analyze`、`flutter test`，再在 Xcode 中打开 `ios/Runner.xcworkspace`。为 Runner 和 AILinkWatch 选择同一 Apple Developer Team；重新启用复杂功能时，还需为 AILinkWatchWidgets 设置相同 Team，检查自动签名及对应 bundle ID。
3. 选择已配对的 iPhone + Apple Watch 模拟器组合运行 Runner 检查界面与即时消息；文件传输和完整语音链路使用配对实机。确认 Watch 应用可从 iPhone 的 Watch 应用安装，且两端 `WCSession` 激活。
4. iPhone 配置文字模型、语音识别及可选朗读；Apple Watch 分别测试授权麦克风、按住录音、上滑取消、自动发送、确认发送、长文本滚动、自动播报、后台唤醒与断连。检查 iPhone 会话入库及手表标记；不要清除已有用户数据来测试。
5. 对真实语音服务与多个供应商分别验证 WAV 兼容性、模型权限、TTS 格式和响应时限。重点核验后台 30 秒以上请求的系统行为，以及 watchOS 10 播放路由。

独立路由通过 `WatchRequestRouting` 最多切换一次。仅请求前的 DNS、拒绝连接或明确无网络错误允许自动切换；超时、服务错误、连接重置、部分回答或截断流不重发。每个阶段先使用手表请求，手机可达也不改变优先级；手表网络明确失败且手机可达时可转向手机。手机兜底也失败后直接结束，不回到手表反复尝试。回答在手表落库后，重连同步进手机 SQLite 的手表会话；手机清空数据后可从最早未确认的序号重建会话，已确认历史不会全量恢复。

每次启动、恢复前台和重连时尝试同步手机最新配置；冷启动先加载 Keychain 缓存，等待 WatchConnectivity 激活后发送同步请求。手机不可达、15 秒超时、返回格式无效或 Keychain 保存失败时保留上次缓存；已有可用快照时可以继续录音，不等待手机处理器。点击「同步手机配置」立即开始新请求，即使自动同步仍在进行；被替换或已失败请求的迟到响应不会覆盖配置。缺少文字或识别配置时须先同步手机配置，否则不开始录音。收到删除服务或密钥后的快照会使手表配置失效；尚未同步时不能立即获知手机上的删除。开启自动播报仍须配置朗读服务。

## 独立网络验证

- 本地协议测试：`python3 scripts/test_watch_network.py` 编译原生 Swift 网络代码，并通过本机 HTTP fixtures 测试 OpenAI/Claude 流式回复、三类 ASR/TTS、重定向拒绝、截断流、换路限制及待同步记录；不调用真实服务、不使用用户密钥。
- Flutter 测试：`flutter test`，覆盖手机无落库请求、配置失效、保守重试判定、同步幂等、顺序和手机数据重置后的恢复。
- 配对真机：更新安装手机和手表，手动同步后分别验证手机可达、关闭手机且手表连 Wi-Fi、手表关闭 Wi-Fi 并有可用蜂窝三种情况。每次确认转写、上下文回复、可选播放及重连入库；蜂窝型号与套餐须支持上网。
- 故障验证：无网络、错误密钥、服务器 401/500、超过时限和收到部分回答后断网。检查仅安全失败换路，未知状态或部分回答不重复计费；不要通过删除已有用户数据制造测试条件。
- 真机不可用时，签名构建和模拟器截图不能代替 WatchConnectivity 文件传输、Keychain 配对同步、真实语音、Wi-Fi/蜂窝与后台唤醒验证。Apple 官方 [URLSession 网络路由说明](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date)、[独立 watchOS 应用](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/)、[文件传输与模拟器限制](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile%28_%3Ametadata%3A%29)。

2026-10-04 本次代码验证：`flutter analyze` 无问题，`flutter test` 84 项通过，原生本地协议与路由测试通过；完整 Xcode 的 iOS/watchOS Profile 构建和 `codesign --verify --deep --strict` 通过，配套标识一致，产物独立运行标志为 YES，未嵌入暂关的 Widget 扩展。配对模拟器 Debug 已构建、安装并启动。当前安装工具未发现可安装的 Apple 真机，未更新实体设备，真实服务与独立 Wi-Fi/蜂窝尚未实测；Mac 锁定也限制了本次设置页交互检查。

同日路由调整：Apple Watch 改为各请求阶段始终先在手表执行，明确网络失败且 iPhone 可达时才兜底到手机；已有可用配置不再逐次等待手机录音前校验。原生回归覆盖手机可达仍优先手表、手表失败转手机、手机不可达、超时/部分回复/服务错误不换路，以及手机兜底失败不循环重试。URLSession 的物理网络路径仍由 watchOS 自行选择。

配置同步补充：启动同步失败仅更新状态提示，保留内存和 Keychain 中上次成功的配置；无缓存时提示先连接手机同步。手机成功返回的有效空配置仍会撤销旧密钥，不当作失败沿用已删除服务。明确清除手表数据后继续保留须手动同步才能恢复的规则。原生回归新增冷启动等待激活、自动请求合并、手动立即重发、旧请求/超时回调隔离。

## Firebase Analytics（2026-10-04）

- 下载的正式配置已放到 `ios/Runner/GoogleService-Info.plist` 并加入 Runner 的资源阶段，Bundle ID 为 `com.maxhall.ailink`。不把配置加入 Watch 或暂时关闭的 Widgets target。
- Runner 通过 Swift Package Manager 使用 Firebase Apple SDK 12.19.2，依赖 `FirebaseCore` 和 `FirebaseAnalyticsCore`。该版本中，旧的 `FirebaseAnalyticsWithoutAdId` 已由 Core 产品替代；不选择 `FirebaseAnalyticsIdentitySupport` 或完整的 `FirebaseAnalytics` 产品，以避免引入广告 ID 支持。
- 沿用 Flutter `AppDelegate` 与现有引擎、手表桥接。仅正式 Bundle ID 执行 `FirebaseApp.configure()` 与 `Analytics.setAnalyticsCollectionEnabled(true)`；Info.plist 默认关闭统计，Debug/Profile 不初始化。下载文件中的 `IS_ANALYTICS_ENABLED` 保持原样，收集开关由 AppDelegate 的正式包分支明确设置。
- 当前仅 SDK 自动应用事件，没有 Flutter 页面路由或聊天内容埋点。未安装到真机并在 Firebase DebugView/报告验证之前，只能声明依赖和构建验证结果。
