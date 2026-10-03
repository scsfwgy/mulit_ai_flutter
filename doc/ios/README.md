# AI Link iPhone 与 Apple Watch 第一版

## 已接入的代码

- iPhone 沿用 Flutter 的同一套聊天、服务配置、语音和本地 SQLite；`ios/Runner/AppleWatchBridge.swift` 在后台 Flutter engine 中复用 `WatchChatProcessor`。
- Xcode 工程增加 `AILinkWatch` SwiftUI watchOS target，并嵌入 iPhone Runner；bundle ID 为 `com.maxhall.ailink.watchkitapp`，配套 iPhone ID 为 `com.maxhall.ailink`，最低 watchOS 10。Debug 的 iPhone ID 为 `com.maxhall.ailink.debug`，watchOS ID 为 `com.maxhall.ailink.debug.watchkitapp`，名称均为「AI Link Debug」，与 Release 使用独立标识；Debug 已通过完整 Xcode 构建与配对模拟器启动；Release 签名与真机验证仍待完成。
- Apple Watch 按住录制 16 kHz、16 位、单声道 WAV，原位松手后经配对 iPhone 转写并发送，左上滑松手取消，右上滑松手转文字并等待确认。iPhone 使用用户选择的云端语音识别与文字模型。回复进入 iPhone SQLite，会话在侧栏显示手表标记；可选云端语音合成通过文件传回手表播放。
- Apple Watch 仅保存最近 50 条显示用问答，不接收模型或语音 API Key。录音与合成音频使用临时文件。界面语言通过 WatchConnectivity 同步 iPhone App 的语言设置，外观跟随手表系统；按住录音显示实时波形与计时，并高亮当前选中的取消或转文字动作。

- 界面对齐 Wear OS：首页全屏显示可上下滚动的聊天，旧问答直接展开；长按屏幕录音，双击聊天进入设置。首次打开显示操作引导，确认后不再重复，设置页保留操作说明。右上滑转文字后，在聊天内容中显示确认发送与重新录音；设置页保留停止播放。自动播报可在手表独立设置，覆盖单次请求选项，不修改手机默认设置；同步仅包含语言、服务名称、模型 ID、默认开关与配置就绪状态；iPhone 检查密钥是否配置，不向手表发送密钥。离开前台或录音页取消录音，不足 0.6 秒静默忽略。

## 当前限制

- Apple Watch 第一版需要配对 iPhone 可达，由 iPhone 网络和后台执行完成模型请求；手表自有 Wi-Fi 或蜂窝网络还不能独立提问。WatchConnectivity 文件传输可能延迟，系统也可能结束长时间后台请求。
- 2026-10-03 已在 Xcode 27.0 构建 iOS/watchOS Debug，安装到配对的 iPhone 17 与 Apple Watch Ultra 4 模拟器，并验证页面导航、连接与配置摘要同步。真实语音服务、后台长请求、音频播放及配对真机尚未验证。Apple 官方说明模拟器不支持 `transferFile(_:metadata:)`，录音与合成音频的文件传输需用配对真机验证。
- 公开隐私政策页面目前仍以 Wear OS 数据流为主。Apple 版发布前，需要补充：手表仅保存最近问答、录音经 WatchConnectivity 传至 iPhone、识别/模型/合成请求从 iPhone 直发用户配置的第三方服务、Apple Watch 不接收 API Key、清空 iPhone 数据不会自动删除手表最近问答。应用内“数据与隐私”已按两类手表分别说明；线上正文需同步。
- watchOS target 当前版本号固定为 `1.0.0 (1)`；每次 iPhone 版本提升时应一并更新 watchOS target 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。Debug 已配置本机开发团队，Release 签名与 App Store Connect 仍待配置。

## 真机开发安装脚本

运行 `./install-dev.sh --platform ios`，按序号选择真实 iPhone/iPad、Apple Watch，多个序号用逗号或空格分隔；`--all` 安装到全部 Apple 真机，`--target phone` / `--target watch` 只选择手机或手表。设备须先通过 Device Hub 配对、信任 Mac 并开启开发者模式。

默认构建 Profile 版，手机可脱离调试器从桌面启动。Profile 与 Debug 共用开发标识 `com.maxhall.ailink.debug` / `com.maxhall.ailink.debug.watchkitapp`、名称「AI Link Debug」与同一开发团队，覆盖安装保留应用数据；Release 仍使用正式标识。需要 Flutter 断点或热重载时传 `--ios-mode debug`，再通过 `flutter run` 或 Xcode 启动手机应用。

脚本读取 Xcode Debug 配置的开发团队，也可用 `--team <TeamID>` 或 `IOS_DEVELOPMENT_TEAM` 指定；通过临时 xcconfig 对手机与手表统一签名，不改写项目中的团队设置。两端由同一次 Flutter iOS 构建生成，脚本校验标识、配套关系与签名后分别覆盖安装。只安装手表时也会准备配套 iPhone 的构建依赖，避免直接构建 Watch Scheme 时缺少 Flutter framework。

## 在具备完整 Xcode 的机器验证

1. 安装完整 Xcode，确认 `xcode-select -p` 指向其 `Contents/Developer`，安装 iOS/watchOS SDK 和 Flutter 所需的插件依赖工具。
2. 运行 `flutter pub get`、`flutter analyze`、`flutter test`，再在 Xcode 中打开 `ios/Runner.xcworkspace`。为 Runner 和 AILinkWatch 选择同一 Apple Developer Team，检查自动签名及两个 bundle ID。
3. 选择已配对的 iPhone + Apple Watch 模拟器组合运行 Runner 检查界面与即时消息；文件传输和完整语音链路使用配对实机。确认 Watch 应用可从 iPhone 的 Watch 应用安装，且两端 `WCSession` 激活。
4. iPhone 配置文字模型、语音识别及可选朗读；Apple Watch 分别测试授权麦克风、按住录音、上滑取消、自动发送、确认发送、长文本滚动、自动播报、后台唤醒与断连。检查 iPhone 会话入库及手表标记；不要清除已有用户数据来测试。
5. 对真实语音服务与多个供应商分别验证 WAV 兼容性、模型权限、TTS 格式和响应时限。重点核验后台 30 秒以上请求的系统行为，以及 watchOS 10 播放路由。

后续独立网络与手机网络切换方案见 [`TODO.md`](../../TODO.md)。Apple 的 [文件传输与模拟器限制](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile%28_%3Ametadata%3A%29)、[WatchConnectivity 数据传输说明](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) 区分即时消息、排队字典和文件传输；[独立 watchOS 应用说明](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/) 解释了配套应用与独立运行选项。

手表开始录音前会向 iPhone 校验文字模型与所选语音识别服务，要求两者均有有效配置和非空密钥；缺少任一项时不申请麦克风或录音，显示手机设置路径。仅向 Apple Watch 发送配置就绪状态，不发送密钥。每次按住前重新校验，避免删除服务后沿用旧状态。自动播报仍为可选功能。
