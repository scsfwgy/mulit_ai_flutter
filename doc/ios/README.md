# AI Link iPhone 与 Apple Watch 第一版

## 已接入的代码

- iPhone 沿用 Flutter 的同一套聊天、服务配置、语音和本地 SQLite；`ios/Runner/AppleWatchBridge.swift` 在后台 Flutter engine 中复用 `WatchChatProcessor`。
- Xcode 工程增加 `AILinkWatch` SwiftUI watchOS target，并嵌入 iPhone Runner；bundle ID 为 `com.maxhall.ailink.watchkitapp`，配套 iPhone ID 为 `com.maxhall.ailink`，最低 watchOS 10。Debug 的 iPhone ID 为 `com.maxhall.ailink.debug`，watchOS ID 为 `com.maxhall.ailink.debug.watchkitapp`，名称均为「AI Link Debug」，与 Release 使用独立标识；Debug 已通过完整 Xcode 构建与配对模拟器启动；Release 签名与真机验证仍待完成。
- Apple Watch 按住录制 16 kHz、16 位、单声道 WAV，原位松手后经配对 iPhone 转写并发送，左上滑松手取消，右上滑松手转文字并等待确认。iPhone 使用用户选择的云端语音识别与文字模型。回复进入 iPhone SQLite，会话在侧栏显示手表标记；可选云端语音合成通过文件传回手表播放。
- Apple Watch 仅保存最近 50 条显示用问答，不接收模型或语音 API Key。录音与合成音频使用临时文件。界面语言通过 WatchConnectivity 同步 iPhone App 的语言设置，外观跟随手表系统；按住录音显示实时波形与计时，并高亮当前选中的取消或转文字动作。
- `AILinkWatchWidgets` 的 WidgetKit 复杂功能源码已实现，**2026-10-03 按用户要求暂时关闭默认构建和嵌入**，等待 Apple Developer 账号与扩展签名准备完成。`Runner` → `AILinkWatch` 的默认构建链不再包含此扩展，普通手机/手表调试无需为新扩展生成描述文件；暂勿单独运行 `AILinkWatchWidgets` Scheme。
- 扩展最低 watchOS 10，支持圆形、矩形与行内复杂功能；矩形样式也支持智能叠放。启用后点击通过本地 URL 打开聊天页，即使 App 停在设置页也会返回聊天；首次使用保留操作引导。入口只显示麦克风图标与「AI Link」，不读取设置、聊天、音频或密钥，不请求网络、不自动录音，无需 App Groups。Debug/Profile 使用 `com.maxhall.ailink.debug.watchkitapp.widgets` 与 `ailink-watch-debug://chat`；Release 使用 `com.maxhall.ailink.watchkitapp.widgets` 与 `ailink-watch://chat`，开发版和正式版入口分开。

- 界面对齐 Wear OS：首页全屏显示可上下滚动的聊天，旧问答直接展开；长按屏幕录音，双击聊天进入设置。首次打开显示操作引导，确认后不再重复，设置页保留操作说明。右上滑转文字后，在聊天内容中显示确认发送与重新录音；设置页保留停止播放。自动播报可在手表独立设置，覆盖单次请求选项，不修改手机默认设置；同步仅包含语言、服务名称、模型 ID、默认开关与配置就绪状态；iPhone 检查密钥是否配置，不向手表发送密钥。离开前台或录音页取消录音，不足 0.6 秒静默忽略。

## 当前限制

- Apple Watch 第一版需要配对 iPhone 可达，由 iPhone 网络和后台执行完成模型请求；手表自有 Wi-Fi 或蜂窝网络还不能独立提问。WatchConnectivity 文件传输可能延迟，系统也可能结束长时间后台请求。
- 2026-10-03 已在 Xcode 27.0 构建 iOS/watchOS Debug，安装到配对的 iPhone 17 与 Apple Watch Ultra 4 模拟器，并验证页面导航、连接与配置摘要同步。真实语音服务、后台长请求、音频播放及配对真机尚未验证。Apple 官方说明模拟器不支持 `transferFile(_:metadata:)`，录音与合成音频的文件传输需用配对真机验证。
- 公开隐私政策页面目前仍以 Wear OS 数据流为主。Apple 版发布前，需要补充：手表仅保存最近问答、录音经 WatchConnectivity 传至 iPhone、识别/模型/合成请求从 iPhone 直发用户配置的第三方服务、Apple Watch 不接收 API Key、清空 iPhone 数据不会自动删除手表最近问答。应用内“数据与隐私”已按两类手表分别说明；线上正文需同步。
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

后续独立网络与手机网络切换方案见 [`TODO.md`](../../TODO.md)。Apple 的 [文件传输与模拟器限制](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile%28_%3Ametadata%3A%29)、[WatchConnectivity 数据传输说明](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) 区分即时消息、排队字典和文件传输；[独立 watchOS 应用说明](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/) 解释了配套应用与独立运行选项。

手表开始录音前会向 iPhone 校验文字模型与所选语音识别服务，要求两者均有有效配置和非空密钥；缺少任一项时不申请麦克风或录音，显示手机设置路径。仅向 Apple Watch 发送配置就绪状态，不发送密钥。每次按住前重新校验，避免删除服务后沿用旧状态。自动播报仍为可选功能。
