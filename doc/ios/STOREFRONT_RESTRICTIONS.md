# App Store 地区与 OpenAI 限制

AI Link 的 iOS 版本使用 StoreKit `Storefront.current` 获取当前 App Store 商店地区，不依据设备语言、系统地区、IP 或定位推断用户身份。只有经 StoreKit 验证、`AppTransaction.environment == .production` 的正式商店安装才接受海外地区结果；开发安装、沙盒/TestFlight、验证失败或超时均视为正式商店地区未知。iOS 15 没有 `AppTransaction`，同样按未知禁用 OpenAI。

| Storefront 状态 | OpenAI |
| --- | --- |
| `CHN`（中国大陆） | 禁用 |
| 未知、空值、读取失败或超时 | 禁用 |
| 经验证的正式商店安装，已确认其他地区，包括香港、澳门和台湾 | 开放 |
| 开发安装、沙盒/TestFlight，无论测试地区为何 | 禁用 |

Android / Wear OS 与目前直接分发的 macOS 版本保持现有行为。这项实现没有覆盖未来的 Mac App Store 分发。

## 执行范围

- iOS 在首帧之前查询地区；回到前台时先撤销旧的地区结果，再重新读取；原生监听 `Storefront.updates`。文字、语音及明确 OpenAI 模型的请求在发送前重新查询，失败后不沿用旧的海外结果。
- 原生查询最多等待 4 秒；Flutter 桥接最多等待 5 秒。前台和手机后台 Flutter engine 共用原生地区状态；并发查询合并，带版本号的通知防止旧结果覆盖新状态。
- 限制识别 `openai` 预设、`openai.com` 及其子域名（大小写与尾随点归一化），以及明确的 `openai/…`、`~openai/…` 模型标识。兼容 Chat Completions 的协议本身不禁用。受限制时界面使用“Chat Completions 兼容”、通用语音服务名称及通用服务名示例，避免在其他服务说明中展示 OpenAI 品牌。
- 受限制的服务不进入聊天/手表模型选择；服务管理页保留已有配置并显示不可用说明。新增表单、JSON 和二维码配置保存均检查限制。OpenAI 预设及其官方密钥入口不可用；OpenRouter 的 OpenAI 默认预设也不展示。
- 请求守卫覆盖文字聊天、重试、自动标题、模型列表、云端识别和朗读，以及手机后台 worker。明确 OpenAI 命名的服务端模型列表条目被过滤；缓存模型在聊天选择页展示时也过滤。手动模型 ID 在确认及请求时再次检查。
- 地区变化会取消活动中的 OpenAI 文字和语音客户端；本机配置、密钥和聊天记录不删除。
- 手机通过 WatchConnectivity 下发 `openAIRestricted`，同时在受限制的配置快照中撤回对应凭据。Apple Watch 使用 Keychain 保存快照，缺少该字段的旧缓存默认限制；独立请求和手机兜底都执行限制。地区限制不作为可自动换路的网络故障。
- 手表离线沿用最后收到的手机地区限制；无法离线判断手机账号是否刚刚切换商店。重连时同步最新限制。

## 边界与提交审核

这是对可识别 OpenAI 服务的技术限制。任意自定义地址可以隐藏其实际上游，应用无法可靠识别所有第三方转发、重命名模型或动态路由。若审核要求保证中国大陆模式完全不接入这类上游，需进一步限定经过核验的服务/模型白名单及自定义入口。

App Store Connect 元数据不是应用代码的一部分。本次代码修改不会自动删除应用名称、副标题、宣传文本、描述、关键词或截图中的引用；提交审核前仍需按拒审信修改相关字段。也不把本限制当作其它生成式 AI 服务已经满足全部当地要求的证明。

完成最终安装包和商店地区验证后，可在审核备注中说明：

> The iOS app uses StoreKit storefront information to determine regional availability. OpenAI services are disabled when the storefront country code is CHN or the storefront cannot be determined. Restrictions apply to provider setup, custom configuration imports, chat, model listing, topic titles, speech recognition, speech synthesis, and the paired Apple Watch, including phone fallback requests. Other providers using a compatible protocol are evaluated separately. We have also removed the relevant references from the App Store metadata.

最后一句只能在实际完成元数据修改后使用。测试时应覆盖中国大陆、地区未知、海外、读取失败、前后台切换、账号地区切换，以及 Apple Watch 的旧缓存、离线与重连；沙盒与 TestFlight 验证不能替代正式商店地区验证。

官方接口：[Storefront](https://developer.apple.com/documentation/storekit/storefront)、[Storefront.current](https://developer.apple.com/documentation/storekit/storefront/current)、[Storefront.updates](https://developer.apple.com/documentation/storekit/storefront/updates)。

## 本次验证（2026-10-10）

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub`：208 项通过，包括地区未知/中国大陆/海外、桥接失败与超时、旧通知、防绕过、手表凭据撤回及活动流取消。
- `python3 scripts/test_watch_network.py`：通过；使用本地 HTTP fixtures，包含原生地区限制及聚合模型测试，不调用真实服务。
- `flutter build ios --debug --no-codesign --no-pub`：通过；包含 iPhone、Apple Watch 和 Widgets 扩展，未签名。
- `flutter build ios --release --no-codesign --no-pub`：通过，已编译正式版 `AppTransaction` 验证分支；未签名、未上传。
- Android Debug APK 构建通过；没有连接 Android 模拟器，未进行模拟器截图检查。
- 尚未验证真实 App Store / Sandbox / TestFlight 商店地区、配对真机切区与后台行为，也未修改远端元数据或重新提审。

## 真机发现与修正（2026-10-10）

已连接 iPhone 的最新 Debug 包实际返回 `Storefront.current.countryCode = USA`，与用户陈述的日常中国大陆 Apple ID 不一致。该值是 StoreKit 返回值，不是 IP/VPN 判断；无法仅凭这个返回值断定具体沙盒账号设置。现已增加正式商店安装验证，避免开发/沙盒地区被误当作正式海外商店而开放 OpenAI。Debug 日志仅打印地区代码、安装环境与禁用状态，不记录用户身份、密钥或请求内容。

修正后真机 Debug 日志为 `rawCountry=USA environment=development restricted=true`；用户在真机“国际服务”列表确认 OpenAI 不再显示。已签名 Debug 包覆盖安装并启动，未修改正式版或用户数据；这不代表正式 App Store 分发、真实海外商店或配对 Apple Watch 已完成验证。
