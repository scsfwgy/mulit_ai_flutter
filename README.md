# AI Link

一个使用自有 API Key 的本地优先聊天应用。Android 与 iOS 手机端共用 Flutter 页面；Wear OS 与 Apple Watch 使用各自的原生手表界面。Apple 平台 Debug 已通过完整 Xcode 构建及配对模拟器界面、配置同步验证；真机语音链路和发布签名仍待验证。

[官方网站](https://www.tools24.uk/app/ai-link) · [隐私政策](https://www.tools24.uk/app/ai-link/privacy)

## 已实现

- 19 个服务预设，覆盖 OpenAI、Claude、Gemini、DeepSeek、GLM、千问、豆包、Kimi、MiniMax、百度千帆、腾讯混元、OpenRouter 等；按国内、国际、聚合与推理平台分组。选平台、粘贴密钥即可接入；地址和模型均可修改。
- 自定义 API：支持 OpenAI 兼容 Chat Completions 和 Claude Messages 两种协议。
- 服务配置同时支持表单与完整 JSON 导入，支持按服务端模型列表选择模型，也能手填模型 ID。
- 服务配置支持扫码一键导入：在「模型服务」→「扫码导入配置」扫描完整配置 JSON 二维码；字段校验通过后自动保存，API Key 仍写入系统安全存储。扫码只读取二维码内容，不上传到中间服务器。
- 使用平台预设时，也可以点 API Key 输入框旁的扫码图标，扫描仅包含密钥字符串的二维码；密钥会填入表单，检查后点「保存并接入」。JSON 编辑模式也提供「扫码填写 API Key」。
- 多话题聊天：新建、切换、重命名、删除；每个话题可选择服务与模型。冷启动会记住上次使用的服务和模型，并用于下一条新对话。
- 流式回复、停止生成、Markdown 回复渲染（标题、列表、表格、代码块等）、链接打开与原文复制。聊天记录保存在设备 SQLite 数据库；API Key 保存在系统安全存储中，不写入聊天数据库。
- 手机联网搜索：独立配置博查、Tavily、Exa，可选择默认服务、结果数量、时间范围和搜索模式。在右上角「更多 → 消息设置」开启联网后，当前问题先搜索，再由当前文字模型回答；来源链接和摘录随回复保存在本机。搜索失败不会静默改成普通回答；联网开关及所选搜索服务自动同步到手表，手机转发与手表独立请求均支持联网搜索。配置与验证说明见 [联网搜索](doc/WEB_SEARCH.md)。
- iOS 风格的聊天页、话题页和服务配置页，Android 与 iOS 复用相同页面组件。
- 界面支持简体中文、繁體中文与英文，可跟随系统；每种语言一份独立配置文件（`assets/i18n/<code>.json`），新增语言只需登记枚举并放入同名 JSON。
- 全局提示词和按「服务 + 模型 ID」设置的模型提示词。发送时先应用全局内容，再追加当前模型的内容；提示词不会显示在聊天记录中。
- 云端语音识别与朗读：设置中单独添加语音提供商，分别选择识别和朗读服务。支持 OpenAI 兼容音频接口、小米 MiMo 和豆包语音；手机左滑取消、右滑转文字后编辑确认、直接松手发送；手表左上滑取消、右上滑转文字后确认、直接松手发送。回复可手动朗读，或开启完成后自动朗读。仅使用录音、音频播放能力，不调用系统语音识别或系统文字转语音。
- Wear OS 第一版配套应用：手机配置模型与语音服务后，连接手机时优先由手机网络处理云端识别、文字模型和可选语音合成；手机网络失败时切到手表 Wi-Fi 或蜂窝网络。未连接手机时先用手表网络，若请求前后手机恢复连接且手表网络失败，再尝试手机。手表统一保存问答，重连后同步到手机会话列表；继续提问会带上手表本地最近的历史文字。
- Apple Watch 配套应用：长按录音，松手发送，左上滑取消，右上滑转文字后确认；优先由手表直接请求文字和语音服务，手表网络不可用且 iPhone 可达时再转交手机。所选密钥经配对通道同步并保存在手表 Keychain；问答在手表保存，重连后按顺序同步到手机。独立 Wi-Fi/蜂窝与真实服务链路待真机验证。
- 手表界面语言同步手机 App 的简体中文或英文设置（“跟随系统”取手机语言），离线保留上次语言，重连补同步；外观跟随手表日夜模式。录音时显示实时波形、计时和取消／转文字状态浮层；手表参与过的话题在手机侧栏带手表图标。
- 手机与手表录音不足 0.6 秒会视为误触，静默忽略，不发送到语音服务。

## Firebase 使用统计

Android 与 iOS 正式手机版接入同一 Firebase 项目 `tools24-d1201` 下各自的 `com.maxhall.ailink` 应用，记录 SDK 自动应用事件。Android 使用 Google Services 插件 4.5.0 和 Firebase BoM 34.19.0；`android/app/google-services.json` 由插件生成匹配正式包名的资源，并由 `FirebaseInitProvider` 自动初始化。Debug/Profile 及 `./release.sh --test` 的统计关闭，不要求 `com.maxhall.ailink.debug` 的 Firebase 配置。

iOS 的配置文件位于 `ios/Runner/GoogleService-Info.plist`，已加入 Runner 资源。Swift Package Manager 固定 Firebase Apple SDK 12.19.2，链接 `FirebaseCore` 与不含广告 ID 支持的 `FirebaseAnalyticsCore`（该版本已不使用旧产品名 `FirebaseAnalyticsWithoutAdId`）。现有 Flutter `AppDelegate` 仅在正式 Bundle ID 下调用 `FirebaseApp.configure()` 并开启统计；Debug/Profile 不初始化。打开 `ios/Runner.xcworkspace` 即可由 Xcode 解析依赖。两端手表不接入 Analytics。

当前没有 Flutter 路由级页面统计或自定义聊天事件，也不上传聊天正文、API Key、录音或模型服务地址。禁用广告标识符与广告个性化信号。配置文件是 Firebase 客户端标识，不是服务账号私钥；正式服务账号与其他密钥仍不得入库。应用内与公开隐私政策需说明 Analytics，Play Data safety / App Store 隐私标签应按最终安装包复核。构建成功不代表 Firebase 控制台已收到真机事件。

## 运行

macOS 客户端可使用 `flutter run -d macos` 运行，支持首页左侧历史会话与右侧聊天、设置页左侧分类与右侧详情、键盘快捷键、云端语音、扫码配置和富文本复制。运行、数据与本地打包说明见 [macOS 客户端](doc/macos/README.md)。Mac 与手机分别保存本机数据，暂不自动同步。

```bash
flutter pub get
flutter run
```

首次进入时点「接入模型服务」，选择预设并填入对应平台的 API Key。然后创建新对话并发送消息。请求由手机直接发送到配置的 API 地址，不经过本项目的服务器。部分服务可能因账户权限、地域和模型可用性返回错误；可在服务配置中手动调整模型 ID。

语音入口：聊天输入区左侧麦克风可切换至「按住说话」模式，左侧随之变成键盘按钮，可随时切回文字输入。按住时全屏浮层显示音量波纹与时间：左滑松手取消，右滑松手转文字后编辑确认，原位松手转写后直接发送；滑回起点恢复直接发送。侧栏「设置」→「语音服务」添加提供商并分别选定识别/朗读服务；右滑转文字后手机会切回文字输入，将识别内容放入输入框等待编辑和发送；发送方式由本次手势决定。小米 MiMo 可复用指向其官方 API 的文字服务密钥；OpenAI 兼容音频服务可复用文字密钥，但需要该服务实际实现音频接口。豆包语音使用独立于火山方舟文字服务的豆包语音 API Key，并须开通相应识别和合成资源。手机录音最长 60 秒，临时录音及合成音频播放后删除；语音内容直接发送给所选语音服务商。朗读前会将 Markdown 转成可读文字；单条朗读上限 1800 字。

语音模型和音色输入框可点「选择」。OpenAI 兼容音频和小米 MiMo 会尝试用当前密钥读取 `/models`，筛出可能用于识别或合成的 ID；返回模型 ID 不保证音频接口可用。豆包的音色列表 OpenAPI 使用火山引擎 AK/SK 签名，当前豆包语音 API Key 无法直接调用，因此按[豆包语音产品动态](https://www.volcengine.com/docs/6561/162929)与[ListSpeakers 接口示例](https://api.volcengine.com/api-explorer/?action=ListSpeakers&serviceCode=speech_saas_prod&version=2025-05-20)内置部分与现有合成接口匹配的音色候选。候选不代表账号已开通；选择页和三个输入框均可手动填写 ID。音色示例会随 OpenAI 合成模型过滤（`tts-1`/`tts-1-hd` 仅展示其支持的内置音色）。

提示词入口：聊天页右上角「模型服务」→「提示词」。全局提示词对所有模型生效；单模型提示词只对选定服务及模型 ID 生效。切换话题中的服务或模型后，会使用新组合对应的提示词。两者都保存在本机 SQLite，修改后从下一次发送开始生效。

### 开发构建与安装

运行 `./install-dev.sh`，脚本会按序号列出已连接的 Android 手机、Wear OS 手表、真实 iPhone/iPad、Apple Watch，以及本机 Mac。只有一台设备时自动选中；多台设备时输入 `1`、`1,3` 或 `all`，支持跨平台一次选择多个设备。Android 模拟器也可选择；Apple 模拟器不在此脚本的安装范围内。

```bash
./install-dev.sh                                  # 列出设备并按序号选择
./install-dev.sh --list                           # 只查看当前设备和序号
./install-dev.sh --select 1,3                      # 构建并安装到指定序号
./install-dev.sh --platform android --all          # 所有已连接 Android 设备
./install-dev.sh --platform ios --all              # 所有已连接 iPhone 与 Apple Watch
./install-dev.sh --platform macos                  # 构建 Mac Debug，安装到 ~/Applications
./install-dev.sh --platform macos --launch         # 安装后打开 Mac 客户端
./install-dev.sh --device macos --macos-mode release # 安装 Mac Release
./install-dev.sh --target desktop --macos-dir /自选目录
./install-dev.sh --target watch                   # 只列出手表并选择
./install-dev.sh --platform ios --target phone --ios-mode debug
./install-dev.sh --device <序列号或UDID>           # 可重复传 --device 选择多台
```

序号以本次筛选后的列表为准；设备重连或筛选条件变化后应重新查看。无人值守安装建议使用 `--device` 指定稳定的设备 ID。原用法 `./install-dev.sh <Android手机序列号> <WearOS手表序列号>` 仍可使用。

脚本需要 Python 3、Flutter 和所选平台的工具链。Android 使用 `adb` 与 Gradle 构建 Debug APK。Apple 使用完整 Xcode、已配对且开启开发者模式的真机；默认读取 Xcode Debug 目标中的开发团队，也可传 `--team <TeamID>` 或设置 `IOS_DEVELOPMENT_TEAM`。iPhone 和 Apple Watch 通过同一次 Flutter iOS 构建生成配套安装包，再用 `devicectl` 分别安装；仅选手表时也需要准备配套 iPhone 构建。

Mac 使用完整 Xcode 构建，默认 Debug，可选 `--macos-mode profile` / `release`；安装到 `~/Applications/AI Link.app`，`--macos-dir` 可改目录。复制后验证签名，再替换应用包；替换失败会恢复旧包，不清空 SQLite 或钥匙串。Mac 的 Debug/Profile/Release 共用 `com.maxhall.ailink.macos` 和本机数据；签名读取忽略的 `Signing.local.xcconfig`，详见 [Mac 说明](doc/macos/README.md)。默认仅安装，`--launch` 打开 Mac 应用。

Android/iOS 两端开发安装都叫「AI Link Debug」并沿用开发包标识。Apple 默认使用 Profile 模式，可从桌面启动；`--ios-mode debug` 用于 Flutter 断点和热重载，手机需要通过 `flutter run` 或 Xcode 启动。Profile 与 Debug 可覆盖更新并保留数据，Release 保持正式标识。脚本先完成所需构建，再覆盖安装所选设备，不执行卸载或数据清空；安装失败会停止并保留已成功安装的设备。安装成功不代表语音、配对和后台流程验证通过。

### Wear OS 手表

先在手机端「设置 → 语音服务」选择识别服务；需要播报时还要选择朗读服务。再到「设置 → 手表」选择手表使用的文字模型，并决定是否播报。手表首页全屏显示聊天，最近问答在上，历史回答直接展开，可上下滚动；长按聊天任意位置录音，双击聊天进入设置，可查看当前模型、同步手机配置，并单独调整手表的自动播报；手表上调整的播报偏好优先于手机同步值。首次配置需要连接手机，手表启动时会请求最新配置。首次打开会展示长按、双击与滚动的操作引导，确认后不再重复；设置页保留操作说明。手表端不填写服务地址或 API Key，长按屏幕录音，原位松手转写并发送，左上滑松手取消，右上滑松手转文字后确认，录音最长 30 秒。右上滑时，手表显示转写文字并等待点按「确认发送」。模型回复可在手表逐步显示。更换手表模型会开始一条新的手表会话。

需要一只与安卓手机配对的 Wear OS 手表，且手机上安装本应用。手机首次安装或启动时不主动提示安装手表应用；有需要的用户可进入「设置 → 手表」，检查各手表的安装状态并在缺失的手表上打开商店安装页。只装手表端时，手表会提示安装手机端，并可在配对的安卓手机上打开商店安装页。配对本身不会自动安装应用；商店尚未提供本应用时，开发测试包仍需按下方步骤分别安装。手机通过配对的 Data Layer 向手表同步所选文字、识别与朗读服务的配置和密钥；手表用 Android Keystore 加密保存密钥。连接手机时，手表经 Data Layer 请求手机端代为调用 HTTPS 服务；手机端仅执行网络请求，最终问答由手表保存。手机网络明确失败时，手表指定自身 Wi-Fi 或蜂窝网络重试；手机未连接时直接使用手表网络。如果服务商返回密钥、模型或权限错误，或已收到部分回答、手机请求状态不明，不会自动换路重复请求。手表问答保存在应用私有存储，重连后经 Data Layer 同步到手机 SQLite；这不是跨账户云同步。清空手机本地数据不会清除手表离线数据，卸载手表应用才能清除手表数据。手表当前使用应用入口；如果表盘支持应用快捷方式，可将「AI Link」固定到表盘。抬腕只唤醒屏幕，不会自动打开应用或启用麦克风。

开发安装可使用上方的 `./install-dev.sh --platform android`，按序号选择手机和手表；也可手动执行：

```bash
flutter build apk --debug
cd android && ./gradlew :wear:assembleDebug && cd ..
adb -s <手机序列号> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <手表序列号> install -r build/wear/outputs/apk/debug/wear-debug.apk
```

调试版名称为「AI Link Debug」，手机与手表均使用 `com.maxhall.ailink.debug` 和仓库中的测试签名，可与正式版并存；两端须安装同一类型的包。首次配置仍需与手机配对；随后手表可独立请求模型。模拟器编译与界面检查不等于配对真机的录音、后台唤醒、断连恢复、Data Layer 或真实语音平台验证。

### Apple Watch

在 iPhone 上安装 AI Link，进入「设置 → 语音服务」选择识别服务，再到「设置 → 手表」选择文字模型和可选朗读。安装新版手机与配套手表应用后，在手表设置点击「同步手机配置」。Apple Watch 与 Wear OS 使用相同操作：全屏聊天可上下滚动，长按屏幕说话、松手发送，左上滑取消，右上滑转文字后确认，双击聊天进入设置。手表用已同步的配置优先直接请求云端识别、文字模型和语音合成；手表网络明确不可用且手机可达时，再复用手机的对应接口，无需系统语音识别或系统朗读。

所选文字/识别/朗读服务凭据只保存在手表 Keychain，不写入问答存储或日志；WatchConnectivity 通过配对通道同步配置。手表保留最近 50 条问答，最多 100 条未确认同步的问答；重连后逐条同步到手机 SQLite，手机确认保存后才移除待同步记录，重复传输不会重复入库。手机数据清空后，重新建立会话接收尚未确认的问答；已确认的旧问答不会自动全量恢复。可在手表设置中明确确认「清除手表配置和问答」，随后须手动同步配置才能重新使用。

每个请求阶段最多换路一次，只有请求尚未到达服务的明确网络失败才自动换路；超时、连接中断、权限错误和已有部分回答时均不自动重发。watchOS 的 URLSession 自行选择 iPhone 代理、Wi-Fi 或蜂窝路径，应用不能强制指定无线接口。当前使用前台请求，不能保证熄屏或系统结束后台任务后仍完成长请求。配对真机、真实服务、独立 Wi-Fi/蜂窝仍需验证；验证步骤见 [Apple 平台说明](doc/ios/README.md)。

Apple Watch 表盘复杂功能已恢复构建和嵌入，支持圆形、矩形、行内入口及智能叠放的矩形小组件；矩形显示最近手表回复摘要，回答中优先显示最新文字，各样式显示回答、语音加载和播放等状态，点击打开聊天页。刷新由 watchOS 调度，不支持表盘内滚动全文。2026-10-03 因签名准备未完成暂关，2026-10-07 在开发者账号就绪后重新启用。添加方式、签名要求与验证范围见 [Apple 平台说明](doc/ios/README.md)。

工程、安装与验证步骤见 [Apple 平台说明](doc/ios/README.md)。已获得 iOS/watchOS Debug 完整 Xcode 构建、配对模拟器启动与配置同步证据；录音及合成音频使用的 WatchConnectivity 文件传输仍需配对真机验证。

#### 没有真机手表时的模拟测试

1. 在 Android Studio 的「Tools → Device Manager」启动一台带 Google Play 的 Android 11 及以上手机模拟器和一台 Wear OS 模拟器。点 **Wear OS 设备所在行最右侧的 `⋮` → `Pair Wearable`**，选择当前运行的手机模拟器。列表上方的 Wi-Fi 图标是 ADB 无线调试配对，不能用来配对手机与手表。若向导提示缺少 Google Pixel Watch，请在手机模拟器的 Play 商店安装并完成配套应用设置；商店可能要求本人登录 Google 账号。
2. 用上面的命令分别安装手机 APK 和 Wear APK，`adb devices` 确认序列号；连接真机手机时尤其要保留 `adb -s`，避免装错设备。手机端在「设置 → 语音服务」配置识别服务，在「设置 → 手表」选好文字服务、模型及可选的朗读服务。手表端双击聊天进入设置页点「同步手机配置」。首次同步必须保持两端配对连接。
3. 在手表模拟器的 `⋮ → Microphone` 中开启 `Virtual microphone uses host audio input`，授权电脑麦克风。打开手表应用，长按聊天屏幕说话，松开后检查转写、自动发送或确认发送、模型回复以及可选朗读。手表状态会提示当前走手机网络还是手表网络。
4. 两端均联网并配对时，应优先显示「正在通过手机网络…」。手机应用网络失败而手表仍联网时，应显示切换到手表网络；停止手机模拟器、保持手表联网且已同步过配置时，手表可独立请求。恢复配对后，检查手表问答是否只同步一次到手机会话列表。

若蓝牙设置显示「已配对」，但应用仍显示「尚未建立 Wear OS 数据连接」，说明应用暂未发现 Google Play 服务的 Data Layer 节点；蓝牙配对记录本身不能证明该通道可用。确认当前运行的是配对时选择的**同一台手机模拟器**，在手机端完成 Wear OS 配套应用的连接向导，再点手机端「设置 → 手表」的连接状态重新检查。只有数据通道连通后，首次服务配置才能从手机同步到手表。

当前使用的 API 37 模拟器可只阻断**本应用**联网，保留 Google Play 服务的配对链路，用于模拟手机网络故障。以下示例中的 `emulator-5554` 必须换成 `adb devices` 列出的**手机模拟器**序列号；测试后恢复网络。若此前防火墙链已开启，先记录原状态，结束时恢复原状态。

```bash
adb -s emulator-5554 shell cmd connectivity set-chain3-enabled true
adb -s emulator-5554 shell cmd connectivity set-package-networking-enabled false com.maxhall.ailink.debug
# 测试手机故障 → 手表网络接管后恢复：
adb -s emulator-5554 shell cmd connectivity set-package-networking-enabled true com.maxhall.ailink.debug
adb -s emulator-5554 shell cmd connectivity set-chain3-enabled false
```

将序列号改为手表模拟器可测试手表应用断网而手机仍可处理请求。此命令属于当前模拟器系统的调试能力，其他系统镜像可能不提供；服务商鉴权失败或模型报错不属于网络故障，不会触发换路。

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

扫码导入时，将上面这份 JSON（换成自己的配置和密钥）作为二维码内容即可；新服务的 `apiKey` 不可留空。二维码包含密钥，请仅在可信场景中展示和扫描。

如果使用已有的平台预设，二维码也可以只包含 API Key 字符串，无需包装成 JSON；在该服务的 API Key 输入框旁扫码填写即可。

`protocol` 也可以填 `anthropic_messages`。`baseUrl` 是根地址，应用会追加 `/chat/completions` 或 `/messages`。默认要求 HTTPS；Android 模拟器访问宿主机时可用 `http://10.0.2.2:端口`。编辑现有服务时，`apiKey` 留空表示保留原密钥。

## 数据与当前边界

**密钥只保存在设备的安全存储中，我们不会把密钥收集到自己的服务器。**应用没有 API 中转服务；获取模型列表或发送对话时，设备会将密钥放入请求头，直接发送给你配置的 API 服务商进行认证。因此请只接入可信的服务地址。

表单、JSON 和扫码导入使用同一套保存方式：配置中的名称、协议、API 根地址、默认模型和预设 ID 拆成字段，写入设备本机的 SQLite `providers` 表；`apiKey` 单独由 `flutter_secure_storage` 按服务 ID 保存，不进入 SQLite。完整 JSON 文本和二维码原文不会另存为文件或数据库记录。话题、消息正文和提示词也保存在本机 SQLite，其中消息正文与提示词未加密。Android 备份已关闭；卸载应用会删除本地记录。

服务图标来自 [Lobe Icons](https://github.com/lobehub/lobe-icons)，随应用本地打包；许可见 [assets/provider_icons/LICENSE](assets/provider_icons/LICENSE)。预设地址和模型随第三方服务变化，实际可用性以服务商及账户为准；没有真实 API Key 的平台不视为已实测。

当前聊天请求仍发送文字消息；语音输入先经所选语音模型转写为文字。模型回复可以显示 Markdown，但尚不支持公式、HTML、图片上传或文件上传。工具调用、历史导入导出及跨账户同步尚未实现；Token 用量仅在服务端报告时展示。Apple 平台 Debug 构建与配对模拟器界面、配置同步已验证；真机语音链路待验证。Android 正式和测试签名已在本机配置，公开隐私政策已上线；发布 Apple 版前须更新线上隐私政策的 Apple Watch 数据说明，详见 [Apple 平台说明](doc/ios/README.md)。密钥离线备份、真实截图和 Play Console 审核详见 [Android 上架清单](doc/google_play/README.md)。

正式版「AI Link」使用 `com.maxhall.ailink`；普通 Debug 与 `./release.sh --test` 均为「AI Link Debug」，使用 `com.maxhall.ailink.debug`，可与正式版同时安装。两者的服务、密钥与聊天记录各自独立，不自动迁移。旧测试包 `com.example.mulit_ai_flutter` 和此前占用正式包名的测试包也不会自动迁移；不要为了测试新包而卸载或清空旧包。iOS Debug 同样使用 `com.maxhall.ailink.debug` 与「AI Link Debug」，配套 watchOS Debug 使用 `com.maxhall.ailink.debug.watchkitapp`；Apple 平台仍待发布签名及配对真机端到端验证。

本机已配置正式上传密钥；独立测试密钥及配置已入库，测试密码视为公开信息。运行 `./release.sh` 生成正式签名的手机、手表 APK 和 AAB；运行 `./release.sh --test` 生成测试签名的手机、手表 APK。默认仅本地归档，`--push-website` 上传两端 APK 到 OSS 并同步 AI Link 官网，`--push-release` 同时同步官网和 Google Play。官网发布需先部署同级 HomeTools 的 `/api/v1/ai-link/release` 接口，并在 `localConfig/.env.local` 配置发布密钥和 OSS 配置路径，示例见 `scripts/website_release.env.example` 与 `scripts/oss_config.example.json`。两端必须使用同一套签名；正式密钥与密码须离线备份且绝不入库，测试签名包与正式包独立安装；普通 Debug 与 `--test` 包共用测试签名，可以相互覆盖更新并保留测试数据。发布版本与 Tools24 一致：基础版本加 8 位 Git 哈希，手机 versionCode 使用 Git 提交次数，手表加 1,000,000。两端启用 R8 优化与资源裁剪，手机启用 Dart 混淆；APK/AAB 分别保存映射和符号。详见 [上架清单](doc/google_play/README.md)。

## 开发验证

```bash
flutter analyze
flutter test
flutter build apk --debug
```
