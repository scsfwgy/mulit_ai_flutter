# AI Link iPhone 与 Apple Watch

2026-10-06：已创建本机 Apple Distribution 证书，补齐手机与手表 Release 团队，并成功导出 `1.0.3 (48)` 的 App Store IPA。该旧包尚未接入用户选定的「7 天试用 + 永久买断」，未上传或提审；当前源码已接入 StoreKit 2，并完成本地测试，见 [购买实现](purchases.md)；商品草稿、签名验证及待办见 [当前发布进度](app-store-progress-2026-10-06.md)。该旧包未包含 Widgets 扩展；当前恢复情况见下文「复杂功能恢复记录」。 中文手机、iPad 与手表截图及图标已在本地准备，见 [商店素材](../app_store/README.md)。

2026-10-07：`./release.sh` 增加 `--push-ios`，可构建正式签名 IPA 并自动上传 App Store Connect，见下文「正式发布与上传 App Store Connect」。上传只把构建送达 TestFlight，提交审核仍需人工完成。

## 正式发布与上传 App Store Connect

`./release.sh --push-ios` 构建正式签名的 iPhone/Apple Watch IPA 并上传到 App Store Connect，构建随后出现在 TestFlight；**不自动提交审核**。上传由 `scripts/appstore_upload.py` 通过 Xcode 自带的 `altool` 完成，构建与本地归档仍由 `scripts/apple_release.py` 负责，两者职责不重叠。

### 一次性配置

1. App Store Connect → 用户和访问 → 集成 → App Store Connect API → 团队密钥 → 生成密钥，角色至少需要 App Manager；记下密钥 ID，以及同一页面顶部显示的 Issuer ID。
2. 私钥 `AuthKey_<密钥 ID>.p8` 只能在生成时下载一次，请放到 `localConfig/` 并离线备份。
3. 复制 `scripts/appstore_connect.env.example` 为 `localConfig/appstore-connect.env`，填写 `ASC_KEY_ID` 与 `ASC_ISSUER_ID`；`ASC_KEY_PATH` 可省略，省略时按 `localConfig/AuthKey_<ASC_KEY_ID>.p8` 查找。同名环境变量优先于文件。`localConfig/` 已被 `.gitignore` 忽略，私钥不入库。

本机可将本地证书与手机、手表、复杂功能的分发描述文件映射保存在 `localConfig/ios-export-options.plist`。未显式传导出选项时，`scripts/apple_release.py` 默认读取此文件；目录已忽略，不入库。此配置支持 Xcode 未登录账号时使用已有本地证书导出；换机器、团队或证书后需重新准备配置，也可通过 `--ios-export-options` / `IOS_EXPORT_OPTIONS_PLIST` 覆盖。

### 常用命令

| 命令 | 作用 |
| --- | --- |
| `python3 scripts/appstore_upload.py --check` | 只检查本地配置、私钥与 altool，不联网 |
| `python3 scripts/appstore_upload.py --check-online` | 检查配置，并向 Apple 校验凭据与 App 记录（联网） |
| `./release.sh --push-ios` | 只构建 iOS 并上传（未指定 `--platform` 时按开关推导为 iOS） |
| `./release.sh --push-mobile` | 同 `--push-android --push-ios`：官网 + Google Play + App Store Connect，不构建 macOS |
| `./release.sh --push-all` | 全端构建并上传：官网（含 Mac DMG 与 Windows 安装包地址）+ Google Play + App Store Connect |
| `./release.sh --platform all --push-ios` | 显式构建全部平台，但只上传 iOS |

`--push-ios` 会在构建前先做联网预检：凭据文件缺失、私钥与密钥 ID 不配对、Issuer ID 无效或网络不通时直接退出，不会白跑一次 iOS 构建。上传前还会解包 IPA，核对手机 `com.maxhall.ailink` 与手表 `com.maxhall.ailink.watchkitapp` 的 Bundle ID、`CFBundleShortVersionString` 与 `CFBundleVersion` 都与本次构建一致，避免上传上一次的产物。结果写入归档目录的 `release-info.txt`（`appstoreStatus=...`），失败时保留完整日志 `appstore-upload.log`。

### 上传后仍需人工完成

- 构建处理需要数分钟到数十分钟；处理完成后在 App Store Connect → TestFlight 查看，并附加到对应的 App 版本。
- 提交审核、审核备注、内购与付费协议都在后台处理，脚本不代替这些步骤。自动提审（App Store Connect API 的 `appStoreVersionSubmissions`）当前刻意未实现：付费 App 协议未生效时提交只会再次被拒，见 [内购拒审排查](app-store-rejection-2026-10-07.md)。

### 出口合规声明

2026-10-07：用户在 App Store Connect 的加密问卷中选择「不属于上述的任意一种算法」，完成本次构建声明。按该声明，在 `ios/Runner/Info.plist`、`ios/AILinkWatch/Info.plist` 和 `macos/Runner/Info.plist` 中固定设置 Boolean 类型的 `ITSAppUsesNonExemptEncryption=false`。该字段表示没有使用非豁免加密，不会关闭 HTTPS/TLS 或 Keychain；此配置记录的是开发者声明，不代表 Apple 已审查并确认加密分类。

重新构建并上传的新包会携带此声明，从而避免同一加密状态下每次手动回答问卷；源码修改不会补写到已上传的构建。当前不填写 `ITSEncryptionExportComplianceCode`，也不使用占位代码。如果加密实现、第三方 SDK 或豁免状态变化，需要重新核对；若 Apple 要求文稿，提交并获批后改为 `ITSAppUsesNonExemptEncryption=true`，并填写 Apple 提供的实际合规代码。

依据：[Apple 的声明字段说明](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)。

### 限制与注意

- 同一个 `CFBundleVersion` 只能上传一次；重复上传需先提升 `pubspec.yaml` 的 `version: x.y.z+build` 构建号。
- 上传失败不自动重试，避免产生重复或半成品构建；重跑整条命令即可。
- `altool` 走系统网络设置，不读取 `http_proxy`/`https_proxy` 环境变量；`release.sh` 里探测到的代理只作用于 Google Play 与 OSS 链路。
- 本机没有 iOS Distribution 证书和 App Store 描述文件时会跳过 iOS；此时 `--push-ios` 直接报错退出，而不是构建出不可上传的包。

## 已接入的代码

- iPhone 沿用 Flutter 的同一套聊天、服务配置、语音和本地 SQLite；`ios/Runner/AppleWatchBridge.swift` 在后台 Flutter engine 中复用 `WatchChatProcessor`。
- Xcode 工程增加 `AILinkWatch` SwiftUI watchOS target，并嵌入 iPhone Runner；bundle ID 为 `com.maxhall.ailink.watchkitapp`，配套 iPhone ID 为 `com.maxhall.ailink`，最低 watchOS 10。Debug 的 iPhone ID 为 `com.maxhall.ailink.debug`，watchOS ID 为 `com.maxhall.ailink.debug.watchkitapp`，名称均为「AI Link Debug」，与 Release 使用独立标识；Debug 已通过完整 Xcode 构建与配对模拟器启动；Release 签名归档已有本地验证，配对真机验证仍待完成。
- Apple Watch 按住录制 16 kHz、16 位、单声道 WAV，原位松手转写并发送，左上滑取消，右上滑转文字并等待确认。识别/聊天/合成分别优先由 `WatchNetworkClient` 使用 URLSession 请求，手表网络明确不可用且手机可达时再通过 iPhone 无落库接口处理。文字支持 OpenAI 兼容 Chat Completions 与 Claude Messages；语音支持 OpenAI、MiMo 和豆包。
- 选定服务的完整配置经 WatchConnectivity applicationContext 同步，API Key 仅保存在手表 Keychain（AfterFirstUnlockThisDeviceOnly、不同步 iCloud）；手机 UserDefaults 只缓存不含密钥的显示摘要。手表保留最近 50 条问答及最多 100 条未确认同步记录，后者不随显示历史裁剪。每条问答具有会话 UUID、turn UUID 和序号，手机 SQLite 事务保存并确认后，手表才删除待同步记录。录音/合成音频使用临时文件。界面语言跟随手机 App，外观跟随手表系统。
- `AILinkWatchWidgets` 的 WidgetKit 复杂功能已恢复默认构建与嵌入（2026-10-07）。`Runner` → `AILinkWatch` → `AILinkWatchWidgets` 在同一次构建中生成，手机、手表、扩展须使用同一签名团队。
- 扩展最低 watchOS 10，支持圆形、矩形与行内复杂功能；矩形样式也支持智能叠放。矩形在思考时显示本次问题（两行，超长省略），开始回答后显示回复摘要，生成中截取尾部并优先保留最新文字；圆形显示状态图标，行内显示简短状态。覆盖就绪、录音、识别、待确认、思考、回答、完成、语音加载、播放和失败。点击通过本地 URL 打开聊天页，即使 App 停在设置页也会返回聊天；首次使用保留操作引导。不请求网络、不自动录音，无需 App Groups。Debug/Profile 使用 `com.maxhall.ailink.debug.watchkitapp.widgets` 与 `ailink-watch-debug://chat`；Release 使用 `com.maxhall.ailink.watchkitapp.widgets` 与 `ailink-watch://chat`，开发版和正式版入口分开。
- `WatchComplicationSnapshot.swift` 仅保存状态、有限问题或回复摘要、语言和更新时间。通过专用 Keychain Sharing 组共享：Debug/Profile 为 `$(AppIdentifierPrefix)com.maxhall.ailink.debug.watchkitapp.preview`，Release 为 `$(AppIdentifierPrefix)com.maxhall.ailink.watchkitapp.preview`；不向扩展分享 API Key、服务配置、完整聊天库或音频。共享项使用 AfterFirstUnlockThisDeviceOnly，不同步 iCloud；摘要写入前移除已知密钥和 Markdown 标记，正文标记 `privacySensitive()`。原有手表凭据组保留为 entitlements 第一项，扩展使用自己的默认组，不能读取手表私有凭据组。清除手表数据或开启新话题会更新为空摘要。

- 界面沿用两页聊天与设置：长按屏幕录音、双击进入设置、滑动阅读；右上滑转写后等待确认。自动播报可在手表单独设置。离开录音页或前台取消录音，实际录音不足 0.6 秒静默忽略。设置提供需明确确认的「清除手表配置和问答」，同时删除 Keychain、最近问答及待同步记录；清除后屏蔽缓存配置，直到用户手动同步。

## 当前限制

- URLSession 在 watchOS 上自行选择 iPhone 代理、Wi-Fi 或蜂窝，应用不使用不受支持的低层接口强制选网。独立请求为前台任务，系统挂起或终止应用可能导致失败；手机后台 Flutter 处理同样受运行时间限制。超时状态不明时不换路、不自动重发。语音接口只有明确的 DNS/拒绝连接错误才允许换路，普通 HTTP 客户端异常按状态不明处理。
- 2026-10-03 已在 Xcode 27.0 构建 iOS/watchOS Debug，安装到配对的 iPhone 17 与 Apple Watch Ultra 4 模拟器，并验证页面导航、连接与配置摘要同步。真实语音服务、后台长请求、音频播放及配对真机尚未验证。Apple 官方说明模拟器不支持 `transferFile(_:metadata:)`，录音与合成音频的文件传输需用配对真机验证。
- Apple 版公开发布前需核对并更新线上隐私政策：配对通道同步所选密钥、Apple Watch Keychain、安全存储和第三方直连、手表问答与确认同步、两端分别清理。应用内数据与隐私已更新；此次不修改或部署官网。
- 开发构建的 watchOS App 与扩展使用相同版本号；正式发布由 `scripts/apple_release.py` 的临时 xcconfig 统一手机、手表与扩展版本，并校验三个签名包的标识和版本。安装脚本也校验扩展标识，防止把正式扩展混入开发包。
- 复杂功能不能滚动全文。回答中最多每 5 秒合并一次摘要更新请求，状态变化立即请求刷新；WidgetKit 仍决定实际刷新时间，离开 App 后的请求与播放也受 watchOS 后台限制。中间状态 3 分钟后、播放状态 15 分钟后显示「打开查看状态」，避免长期显示过期的运行状态；完成的回复摘要保留。此处显示的是手表最近回复，不是手机所有话题的最新消息。小组件图库使用固定示例，避免在选择界面展示聊天正文。

## 复杂功能恢复记录

2026-10-03：因本机尚未完成账号及新扩展描述文件配置，按用户要求临时移除 Watch target 的扩展依赖与嵌入；源码和 target 保留，并移除 App Groups。关闭后 Profile 手机/手表签名构建通过，安装包不包含 `.appex`。

2026-10-07：用户确认开发者账号已申请，恢复 `AILinkWatch` 的 `Embed App Extensions`（`AA2200000000000000000025`）及 `PBXTargetDependency`（`AA2200000000000000000027`），并为手机/手表 Profile 及扩展 Release 配置同一团队。两处引用须一起保留，确保先构建签名扩展，再将它嵌入手表 App。

本机 Xcode 账号登录仍不可用；使用已有 App Store Connect API 凭据完成自动签名并生成开发描述文件，扩展独立 Profile 构建通过。私钥及配置保持在忽略的 `localConfig/` 内，不加入源码。最终扩展路径为 `Runner.app/Watch/AILinkWatch.app/PlugIns/AILinkWatchWidgets.appex`。完整 `flutter build ios --profile` 构建通过，手机包确实包含手表和扩展，三者团队一致，`codesign --verify --deep --strict` 通过，无 App Groups entitlement。原生 Watch + Widget 模拟器构建通过，覆盖安装并启动到首次引导页；Mac 锁屏阻止了本次表盘/智能叠放添加与点击验收。配对 iPhone 真机当前不可用，未更新真机。安装脚本 17 项及发布脚本 16 项测试通过；正式包校验也能拒绝混入开发标识的扩展。

正式构建验证：完整 Release 归档及 App Store IPA `1.0.6 (2)` 本地导出通过，手机、手表、扩展的正式标识和版本一致，解包后的三者签名校验通过。因 Xcode 未登录且 API 无云签名权限，自动导出曾失败；最终为三个标识准备同一本机已有分发证书的描述文件，使用忽略的本地导出配置完成签名。不增加云签名权限，不上传商店。最后通过 `scripts/apple_release.py` 的默认导出流程复验，成功归档到 `build/complication-release-verification/`。

### 回复摘要与状态首版（2026-10-07）

上述 IPA 验证针对恢复后的快捷入口；随后新增本节的状态与摘要共享。本版已通过原生 Watch + Widget Debug 模拟器构建，以及 Profile、Release 配置的 watchOS 开发签名构建；两个签名目标的私有组和共享摘要组已核对，签名校验通过且不含 App Groups。Release 配置构建不等于本版已重新导出分发 IPA。状态优先级、最新文字截取、Markdown 清理、密钥脱敏、语言和过期逻辑的 Swift 检查通过。模拟器已覆盖安装，Mac 锁屏限制了表盘和智能叠放交互验收，未宣称配对真机的刷新时效或后台播放已验证。

本地效果图使用实际 SwiftUI 内容组件和固定示例回复渲染，不是表盘截图。可重现：

```bash
python3 scripts/render_watch_complications.py
# 输出 build/complication-preview/statuses.png（生成文件不入库）
xcrun swiftc -swift-version 5 -parse-as-library \
  ios/AILinkWatchShared/WatchComplicationSnapshot.swift \
  scripts/watch_complication_tests.swift -o /tmp/ailink-watch-complication-tests
/tmp/ailink-watch-complication-tests
```

仅 Debug 模拟器支持启动参数 `--complication-preview thinking|replying|complete|loadingAudio|playing` 来写入示例状态；不改聊天历史或服务配置。恢复普通启动会重新发布实际状态。真机验收需分别检查思考阶段问题及长问题省略、正常完成、流式中途回表盘、语音加载/播放/结束、失败、手机语言切换和清除手表数据后的显示。

## 添加表盘快捷入口

1. 安装包含 `AILinkWatchWidgets.appex` 的新版手表 App；Debug/Profile 在系统应用列表中显示为「AI Link Debug」。
2. 选用支持复杂功能的表盘，长按表盘 →「编辑」→ 向左滑到「复杂功能」→ 点击圆形、矩形或行内位置 → 选择「AI Link」。按表冠保存，点击入口进入聊天页。可用位置取决于表盘；并非每个表盘都支持这些样式。
3. 智能叠放：从表盘向上滑动或转动表冠 →「编辑」→「＋」→「AI Link」→ 添加矩形小组件，按需置顶。部分 watchOS 版本通过长按叠放进入编辑。
4. 在聊天页长按屏幕说话；复杂功能点击只打开应用，不开始录音。回复后矩形显示摘要，各样式显示当前状态；文案跟随手机同步的中文/英文。

## 新扩展的真机签名

复杂功能扩展是独立签名目标，现有手机与手表的开发描述文件不能替代它。若出现 `No Accounts` 或 `No profiles for ...watchkitapp.widgets`：

1. 在 Xcode → Settings → Accounts 登录属于当前开发团队的 Apple Developer 账号；已有团队 ID 或缓存描述文件不等于 Xcode 已登录。
2. 打开 `ios/Runner.xcworkspace`，为 `Runner`、`AILinkWatch`、`AILinkWatchWidgets` 三个目标选择同一 Team，启用 Automatically manage signing。使用其他团队时，安装脚本也要传 `--team <TeamID>`。
3. 在 Xcode 选择配对的真机组合，用 Release 配置构建一次，让 Xcode 为正式标识生成并下载描述文件，再运行 `./install-dev.sh --platform ios`。测试包改用 Profile 配置，并在安装时加 `--ios-mode profile`。

当前实现无需 App Groups；如果仍提示旧 App Groups entitlement 不匹配，确认使用最新工程并在 Xcode 执行 Product → Clean Build Folder 后重建，这不会清空设备应用数据。本机已通过 API 凭据生成并缓存开发描述文件；更换团队、证书或电脑时仍需重新完成自动签名。

摘要共享新增 `keychain-access-groups` entitlement。手机不需要加入共享组；只为 Watch 和 Widgets 配置。同一团队的开发描述文件须允许该共享组，本机现有描述文件已通过签名检查。换团队时让 Xcode 重新生成匹配的描述文件，保留默认私有组并同步修改两个目标的摘要组，切勿把原有凭据组共享给扩展。

## 真机开发安装脚本

运行 `./install-dev.sh --platform ios`，按序号选择真实 iPhone/iPad、Apple Watch，多个序号用逗号或空格分隔；`--all` 安装到全部 Apple 真机，`--target phone` / `--target watch` 只选择手机或手表。设备须先通过 Device Hub 配对、信任 Mac 并开启开发者模式。

默认构建 Release 正式包，标识为 `com.maxhall.ailink` / `com.maxhall.ailink.watchkitapp`，名称「AI Link」，手机可从桌面启动。测试包传 `--ios-mode profile`：与 Debug 共用 `com.maxhall.ailink.debug` / `com.maxhall.ailink.debug.watchkitapp`、名称「AI Link Debug」，可与正式包并存，覆盖安装保留各自的数据。需要 Flutter 断点或热重载时传 `--ios-mode debug`，再通过 `flutter run` 或 Xcode 启动手机应用。

脚本读取 Xcode Debug 配置的开发团队，也可用 `--team <TeamID>` 或 `IOS_DEVELOPMENT_TEAM` 指定；通过临时 xcconfig 对手机、手表与复杂功能扩展统一签名，不改写项目中的团队设置。两端由同一次 Flutter iOS 构建生成，脚本校验标识、配套关系与签名后分别覆盖安装。只安装手表时也会准备配套 iPhone 的构建依赖，避免直接构建 Watch Scheme 时缺少 Flutter framework。

## 在具备完整 Xcode 的机器验证

1. 安装完整 Xcode，确认 `xcode-select -p` 指向其 `Contents/Developer`，安装 iOS/watchOS SDK 和 Flutter 所需的插件依赖工具。
2. 运行 `flutter pub get`、`flutter analyze`、`flutter test`，再在 Xcode 中打开 `ios/Runner.xcworkspace`。为 Runner、AILinkWatch 与 AILinkWatchWidgets 选择同一 Apple Developer Team，检查自动签名及对应 bundle ID。
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

- 下载的正式配置已放到 `ios/Runner/GoogleService-Info.plist` 并加入 Runner 的资源阶段，Bundle ID 为 `com.maxhall.ailink`。不把配置加入 Watch 或 Widgets target。
- Runner 通过 Swift Package Manager 使用 Firebase Apple SDK 12.19.2，依赖 `FirebaseCore` 和 `FirebaseAnalyticsCore`。该版本中，旧的 `FirebaseAnalyticsWithoutAdId` 已由 Core 产品替代；不选择 `FirebaseAnalyticsIdentitySupport` 或完整的 `FirebaseAnalytics` 产品，以避免引入广告 ID 支持。
- 沿用 Flutter `AppDelegate` 与现有引擎、手表桥接。仅正式 Bundle ID 执行 `FirebaseApp.configure()` 与 `Analytics.setAnalyticsCollectionEnabled(true)`；Info.plist 默认关闭统计，Debug/Profile 不初始化。下载文件中的 `IS_ANALYTICS_ENABLED` 保持原样，收集开关由 AppDelegate 的正式包分支明确设置。
- 当前仅 SDK 自动应用事件，没有 Flutter 页面路由或聊天内容埋点。未安装到真机并在 Firebase DebugView/报告验证之前，只能声明依赖和构建验证结果。

## 苹果系统语音（2026-10-14）

- 新安装 iPhone 默认选择系统识别与朗读，手机与 Watch 自动朗读默认关闭，需用户手动开启；现有云端选择及明确关闭朗读的设置保留。识别与朗读可分别切换系统、已配置的自定义服务或无。
- `SystemVoiceBridge.swift` 在前台 iPhone engine 处理 Speech 授权、临时 WAV 识别与系统朗读，尽可能使用本地识别；不支持本地识别时可能使用 Apple 服务。每次请求包含真实权限与当前语言可用性检查，取消、超时、结束均清理临时文件。手机录音原有 0.6 秒过滤与手势不变。
- Watch 的 `systemAsr` 使用 `TextFieldLink` 系统听写/键盘输入，不把系统听写接到自定义录音文件上；确认后复用模型请求、历史保存与幂等同步。`systemTts` 在手表本地使用 `AVSpeechSynthesizer`，不传输合成音频。云端模式保留原有长按录音与网络路由。
- 手机「语音服务」提供设备实际可用音色选择，ID 保存在 SQLite 的 `system_tts_voice_id` 并同步到 Watch；手表设置可选择本地音色或跟随手机，指定音色不可用时回退到默认音色。当前不列出需额外授权的个人声音。系统音色选择不会自动启动播放。手表使用点按入口打开独立音色列表，避免内嵌滚轮与设置页滚动手势冲突；打开时缓存音色列表，选择后返回设置。
- 系统模式的提问按钮仅显示麦克风图标，保留无障碍标签。手机语音服务页底部说明：系统听写使用苹果输入界面，配置自己的识别服务后可使用原有自定义手势。
- 配置版本仍为 1，新增 optional 字段；旧缓存保持云端模式。两端需要更新才能使用系统语音默认值。没有 ASR 密钥时仍保持旧协议的 `asrReady = false`，避免旧 Watch 误以为云端语音已配置。
- 验证：216 项 Flutter 测试（含默认值、旧选择、Android 隔离、配置快照、原生桥接错误与 iOS 选择页），原生 Watch 协议与 Markdown 测试；iOS/watchOS Debug 配对模拟器构建及启动通过。独立新安装模拟器的四项设置已核对为系统识别、系统朗读、手机自动朗读关闭、Watch 自动朗读关闭。最终静态分析无问题，Android Debug APK 构建通过；官网本地隐私源码三语更新的 91 项测试通过，尚未发布线上。
- 真机未验收：中文/英文识别质量、设备音色、扬声器/耳机、权限拒绝与恢复、真实模型请求、锁屏/后台、配对与断连。模拟器启动与编译不代替这些证据。
