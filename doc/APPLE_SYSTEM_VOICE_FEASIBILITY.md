# 苹果系统语音接入可行性

调研日期：2026-10-14。代码基线：`7991c01`。范围：iPhone 与 Apple Watch；以下为初始调研，实施进展见文末。

## 结论

可以让用户只配置文字模型，就在 Apple Watch 上通过苹果系统听写提问，并使用系统语音朗读回答，不再要求配置第三方语音服务。但系统听写会使用苹果的输入界面，不能直接替换现有自定义长按录音后的云端识别。

建议首版采用「Apple Watch 系统输入 + 本地系统朗读」，保留现有云端语音路径。iPhone 可以另外接入 Speech 识别与系统朗读，并保留现有录音手势。不能把“不需要语音 API Key”表述为“整个问答离线”或“无需文字模型”。

## 当前阻塞点

- `ios/AILinkWatch/WatchNetworkConfiguration.swift:85`：`canTranscribe` 要求云端 ASR 配置、模型和非空 API Key。
- `ios/AILinkWatch/WatchChatSession.swift:361`：开始录音要求 `textReady && asrReady`；松手后的流程再次要求 `config.canTranscribe`，然后调用手表云端 ASR 或配对手机云端 ASR。
- `lib/watch/watch_chat.dart`：同步的 `asrReady` 取决于所选云端识别服务；`remoteTranscribe` 也依赖该服务及密钥。
- `ios/AILinkWatch/WatchChatSession.swift:541`：回答完成后只在开启朗读且配置了云端 TTS 时合成。TTS 缺失不会阻止文字问答；ASR 缺失会阻止当前唯一录音入口。
- `lib/chat/chat_home.dart:720`：手机长按录音同样先要求云端识别配置。现有手机录音是 PCM 流转 WAV，可以作为 iPhone 系统文件识别的输入。

因此，增加系统朗读本身不能解决“未配置语音服务时无法提问”；必须增加不依赖云端 ASR 的输入路径。

## 官方能力与限制

| 能力 | iPhone | Apple Watch | 对 AI Link 的含义 |
| --- | --- | --- | --- |
| `AVSpeechSynthesizer` 系统朗读 | 支持 | watchOS 2 起支持 | 直接朗读文字，无需云端 TTS Key；项目最低 watchOS 10 可用 |
| `SFSpeechRecognizer` 音频转文字 | iOS 10 起支持 | 不支持 | iPhone 可保持自定义录音界面；不能在手表直接识别现有 WAV |
| `SpeechAnalyzer` / `SpeechTranscriber` | iOS 26 起，另有设备、语言和资源限制 | 不支持 | 新 API 不能解决手表自定义录音转写；手机也不能只用它覆盖最低 iOS 15 |
| `DictationTranscriber` | iOS 26 起，可覆盖更多旧设备/语言 | 不支持 | 同样不能作为手表录音识别器 |
| `TextFieldLink` 系统文本输入 | 不是 iPhone API | watchOS 9 起支持 | SwiftUI 手表可通过系统输入取得字符串，用户可用听写、键盘等方式输入 |

依据：[Speech 平台可用性](https://developer.apple.com/documentation/speech/)、[SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)、[SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)、[WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)、[AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)、[TextFieldLink](https://developer.apple.com/documentation/swiftui/textfieldlink)。本次同时核对了 Apple 文档的 JSON availability 与本机 SDK 声明；新的三个 Speech 类型均明确标记 watchOS unavailable，WatchOS SDK 也没有 Speech.framework。

### 系统听写与现有手势

`TextFieldLink` 是让用户进入系统输入界面的按钮，完成后通过 `onSubmit` 返回文字。watchOS 11 起，`TextField` / `TextFieldLink` 默认进入用户上次使用的输入方式，其中包括听写。不能保证每次点击都直接开始语音；用户可能上次使用的是键盘。

系统掌管输入界面的录音、停止、编辑、取消和提交。不能将其作为接受我们录音文件的 ASR 接口，也不能让现有左上取消、右上转文字、原位松手发送的浮层控制系统听写。建议系统模式单独提供「提问」入口，取得文字后复用已有确认与发送逻辑；云端模式保留长按手势。

听写语言和可用性受系统输入设置、语言、设备与环境影响。App 可以提供自身中英文提示，但不能承诺系统听写总会服从手机 App 的语言选择；需真机核对中英文切换与用户选择行为。

依据：[watchOS 11 Release Notes](https://developer.apple.com/documentation/watchos-release-notes/watchos-11-release-notes)、[WatchKit 系统输入](https://developer.apple.com/documentation/watchkit/navigating-between-scenes)、[Apple Watch 输入说明](https://support.apple.com/guide/watch/enter-text-apdaf7837856/26/watchos/26)。

### 系统朗读

手表收到回答文字后直接调用 `AVSpeechSynthesizer`，不需要将文字发到第三方 TTS，也不需要从 iPhone 传输合成音频。使用设备已有音色，按语言选择，保留停止、完成、失败等状态；开始新录音时停止朗读。

必须运行时枚举设备音色，不能假定 iPhone 与 Watch 的中文、英文或高质量音色相同，也不能宣传为某个固定的 Siri 音色。内置扬声器、蓝牙耳机、音量、音频中断、抬腕结束与锁屏后的行为要实测；后台持续朗读不能仅凭 API 支持就承诺。

依据：[设备可用音色](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/speechvoices())、[AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)。

### iPhone 系统识别与离线边界

最低 iOS 15 可以使用 `SFSpeechRecognizer`，直接识别已有录音文件，保留当前 0.6 秒误触过滤、取消与确认发送流程。需增加 `NSSpeechRecognitionUsageDescription`，首次使用时请求授权，并检查当前语言的 `isAvailable`。

“苹果系统识别”不等于“始终离线”。旧 API 的部分语言或设备可能需要 Apple 服务器，也有服务限流和约一分钟的识别限制。如果提供严格本地模式，先确认 `supportsOnDeviceRecognition`，再设 `requiresOnDeviceRecognition = true`；不支持时明确不可用，不静默改成联网识别。iOS 26 新 API 可以作为后续优化，需检测设备/语言支持和资源下载状态。

依据：[SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)、[识别授权](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)、[requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)、[WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)。

## 方案比较与推荐

| 方案 | 需要语音服务 Key | 离开 iPhone 后 | 交互代价 | 建议 |
| --- | --- | --- | --- | --- |
| Watch 系统输入 + Watch 系统朗读 | 不需要 | 不依赖 AI Link iPhone App 代转写；听写及文字模型网络仍有各自条件 | 使用苹果系统输入界面 | 首版推荐 |
| Watch 长按录音 → iPhone 系统识别 → Watch 系统朗读 | 不需要 | iPhone 不可达时无法识别 | 可以保留现有录音手势 | 后续可选，先验证后台可靠性 |
| 当前 Watch 云端识别 + 系统朗读 | 只需 ASR Key | 依赖已配置 ASR 与模型服务 | 保留现有手势 | 降低部分配置成本，但未解决核心反馈 |

第二种方案可以复用 WatchConnectivity 文件传输，但需要新增 iPhone 原生 Speech 处理路径，不能只复用当前云端 Dart worker。权限应在 iPhone 前台使用时完成；不能期待后台唤醒替用户完成首次授权。文件传输不等于即时完成，手机可达、锁屏、App 不在前台、用户强制退出、识别任务时长都可能影响响应。应分别测试，并且手机不可达时提供系统输入入口，而不是仍将手表判断为“已具备识别能力”。

依据：[WCSession.isReachable](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable)、[transferFile](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:))。这里的后台可靠性是待验证的工程问题，不是本次确认的运行能力。

## 实施范围

1. 识别来源与朗读来源分别保存为系统/云端选项。保留已有云端服务及密钥；旧用户保持原选择，新用户可采用系统模式。
2. Watch 配置同步表达输入和朗读模式。将“文字模型可用”“云端 ASR 可用”“系统输入入口可用”分开判断，不把系统输入伪装成含空 Key 的云端服务。
3. 系统输入返回的文字进入现有文字模型请求、手表历史保存与手机幂等同步。保存前仍执行文字长度、空内容及控制字符校验；取消与空输入不发请求。
4. Watch 本地朗读复用现有播放状态和复杂功能状态发布；朗读失败保留已保存的文字回答。系统输入模式不显示云端录音手势说明。
5. 手机若同时加入系统语音，通过原生桥接接入 `lib/voice/` 的调用点，沿用同一 Flutter widget 树；用平台能力判断显示可用选项。Android/Wear OS 不接入苹果 API，原协议保持兼容。
6. 同步更新三语言文案、配置引导、权限说明、应用内隐私和官网隐私。区分 Apple 联网识别、本地识别、第三方 ASR/TTS 与文字模型请求；不能宣传整个问答离线。
7. 落地时更新 `AGENTS.md` 当前“不得使用系统 ASR/TTS 代替”的约定，明确为新增可选系统路径、保留云端实现。本次用户要求调研系统路径，故该旧约定不阻止调研。

## 本次验证与后续验收

本次确认了当前代码的配置门槛、最低版本（iOS 15 / watchOS 10）、Apple 官方平台可用性和 Xcode 27.0 SDK 声明，并在临时目录完成两项独立 `swiftc -typecheck` 检查：

- watchOS 10 模拟器目标：`TextFieldLink` + `AVSpeechSynthesizer` + 中文音色选择，通过。
- iOS 15 模拟器目标：`SFSpeechRecognizer` + 文件识别请求 + 本地识别能力判断，通过。

这些只证明 API 在最低部署目标可编译；未改动业务代码，未完成 App 集成构建，也未验证识别准确率、播放、后台或配对真机。

实施后验收至少覆盖：只配置文字模型的首次使用；中英文听写和系统输入方式切换；取消/空输入/重复提交；系统听写被关闭或不可用；Watch 离开 iPhone 的 Wi-Fi/蜂窝使用；扬声器/耳机与录音打断朗读；后台和锁屏；系统/云端切换；旧版配置兼容；回答保存与重连不重复同步。若实现手机代识别，还需独立验证首次权限、拒绝权限、手机锁屏/强制退出与 WatchConnectivity 文件传输。真机结果应单独记录。

## 2026-10-14 实施进展

已接入 iPhone 系统录音文件识别、系统朗读，以及 Watch 系统输入与本地朗读。新安装默认系统识别/朗读；自动播报默认关闭，保留旧云端选择、停用设置和后续自定义服务。未新增额外文字大模型校对请求。实施范围与验证边界见 `doc/ios/README.md` 的“苹果系统语音”章节。
