# AI Link iPhone 与 Apple Watch 第一版

## 已接入的代码

- iPhone 沿用 Flutter 的同一套聊天、服务配置、语音和本地 SQLite；`ios/Runner/AppleWatchBridge.swift` 在后台 Flutter engine 中复用 `WatchChatProcessor`。
- Xcode 工程增加 `AILinkWatch` SwiftUI watchOS target，并嵌入 iPhone Runner；bundle ID 为 `com.maxhall.ailink.watchkitapp`，配套 iPhone ID 为 `com.maxhall.ailink`，最低 watchOS 10。
- Apple Watch 按住录制 16 kHz、16 位、单声道 WAV，松开发往配对 iPhone，上滑取消。iPhone 使用用户选择的云端语音识别与文字模型；关闭自动发送时，手表先显示转写文字并等待确认。回复进入 iPhone SQLite，会话在侧栏显示手表标记；可选云端语音合成通过文件传回手表播放。
- Apple Watch 仅保存最近 20 条显示用问答，不接收模型或语音 API Key。录音与合成音频使用临时文件。界面语言通过 WatchConnectivity 同步 iPhone App 的语言设置，外观跟随手表系统；按住录音显示实时波形与计时，上滑松开取消。

## 当前限制

- Apple Watch 第一版需要配对 iPhone 可达，由 iPhone 网络和后台执行完成模型请求；手表自有 Wi-Fi 或蜂窝网络还不能独立提问。WatchConnectivity 文件传输可能延迟，系统也可能结束长时间后台请求。
- 本开发机只有 Xcode Command Line Tools，没有完整 Xcode、watchOS SDK 或 CocoaPods。项目文件和 Swift 语法已静态检查，**没有 iOS/watchOS 编译、安装、配对或真实语音服务的通过证据**。
- 公开隐私政策页面目前仍以 Wear OS 数据流为主。Apple 版发布前，需要补充：手表仅保存最近问答、录音经 WatchConnectivity 传至 iPhone、识别/模型/合成请求从 iPhone 直发用户配置的第三方服务、Apple Watch 不接收 API Key、清空 iPhone 数据不会自动删除手表最近问答。应用内“数据与隐私”已按两类手表分别说明；线上正文需同步。
- watchOS target 当前版本号固定为 `1.0.0 (1)`；每次 iPhone 版本提升时应一并更新 watchOS target 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。签名团队和 App Store Connect 尚未配置。

## 在具备完整 Xcode 的机器验证

1. 安装完整 Xcode，确认 `xcode-select -p` 指向其 `Contents/Developer`，安装 iOS/watchOS SDK 和 Flutter 所需的插件依赖工具。
2. 运行 `flutter pub get`、`flutter analyze`、`flutter test`，再在 Xcode 中打开 `ios/Runner.xcworkspace`。为 Runner 和 AILinkWatch 选择同一 Apple Developer Team，检查自动签名及两个 bundle ID。
3. 选择已配对的 iPhone + Apple Watch 模拟器组合或实机运行 Runner。确认 Watch 应用可从 iPhone 的 Watch 应用安装，且两端 `WCSession` 激活。
4. iPhone 配置文字模型、语音识别及可选朗读；Apple Watch 分别测试授权麦克风、按住录音、上滑取消、自动发送、确认发送、长文本滚动、自动播报、后台唤醒与断连。检查 iPhone 会话入库及手表标记；不要清除已有用户数据来测试。
5. 对真实语音服务与多个供应商分别验证 WAV 兼容性、模型权限、TTS 格式和响应时限。重点核验后台 30 秒以上请求的系统行为，以及 watchOS 10 播放路由。

后续独立网络与手机网络切换方案见 [`TODO.md`](../../TODO.md)。Apple 的 [WatchConnectivity 数据传输说明](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) 区分即时消息、排队字典和文件传输；[独立 watchOS 应用说明](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/) 解释了配套应用与独立运行选项。
