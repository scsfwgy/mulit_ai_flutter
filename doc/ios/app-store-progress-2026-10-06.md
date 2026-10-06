# App Store 发布准备进度（2026-10-06）

## 当前产品决定

- iOS 免费下载；用户主动领取 7 天全部功能试用，到期后主动买断，不自动扣款。
- 永久解锁包含 iPhone 与配对 Apple Watch 功能；第三方模型、搜索、语音服务的用量仍由用户承担。
- 用户指定美区 US$10、中国大陆 ¥70；商店当前提供这两个精确价格档位，已分别保存。其他地区价格由 Apple 根据美区基准换算，不能宣称所有地区均为 US$10。
- 目标发行范围包含中国大陆；用户尚未办理或不确定 App 备案、AI 应用登记及适用性结论。不能把网站备案、自备 API Key 或设备直连作为自动豁免。
- 本次是 iOS/watchOS 发布准备，尚未改变 Android 的收费与权益行为。

## App Store Connect 已保存的草稿

| 项目 | 标识 | 当前配置 |
| --- | --- | --- |
| App | `6819497731` / `com.maxhall.ailink` | AI Link - 多模型聊天与语音助手，简体中文，SKU `ailink-ios` |
| 永久解锁（非消耗型） | `6819504917` / `com.maxhall.ailink.permanent_unlock` | 美区 US$10、中国大陆 ¥70；中文显示名称及描述已保存 |
| 7-day Trial（非消耗型） | `6819505561` / `com.maxhall.ailink.trial_7_days` | 各地区零价；中文显示名称及 7 天、主动买断、不自动扣款说明已保存 |

版本 1.0.3 的推广文本、描述、关键词、技术支持与营销 URL 已保存，并取消「需要登录」勾选。应用无 AI Link 账号，但审核仍需专用、限额、可撤销的第三方 API 测试配置。商店版本已从 1.0 调整为 1.0.3，并保存主动领取 7 天试用、一次买断、恢复购买、不自动扣款及第三方用量另计的说明。

商品创建及价格保存不表示商品已审核通过、已可售或应用已接入购买逻辑。尚未设置商品销售地区、英文展示信息及审核截图，也未提交商品审核。App 隐私标签仍为草稿，尚未发布。

## 当前签名与本地构建证据

- 已在 Xcode 的 GAOYUAN WANG 团队创建 Apple Distribution 证书，本机钥匙串可用；团队 ID 为 `T94W2V3B6M`。
- 为 Runner 和 AILinkWatch 的 Release 配置补齐该团队；暂关的 Widgets 扩展保持关闭。
- `./release.sh --platform ios` 完成：`flutter analyze` 无问题，`flutter test` 135 项通过，Archive 与 IPA 导出成功。
- 本次 IPA 为 `1.0.3 (48)`，路径：`release-artifacts/release-history/1.0.3-ce3cee6b+48/20261006101626-6565/ios/AI-Link-1.0.3+48.ipa`。
- 归档阶段的应用为开发签名；**导出的 IPA** 中 iPhone 与 Apple Watch 均重新签为 Apple Distribution，均使用对应的 Team Store Provisioning Profile，`get-task-allow=false`，团队和配套 Bundle ID 一致。脚本已验证深层签名与两端版本号。
- Archive 中手机包含 20 个 `PrivacyInfo.xcprivacy` 文件；这仅证明文件存在，尚未完成最终 Required Reason API/SDK 隐私清单审计。
- 本次没有上传 Apple、提交审核或发布，也没有真实购买、退款、恢复购买、配对真机验证。当前 IPA 尚无内购，不能作为用户选定收费方案的最终上架包。

## 含内购的新本地包

2026-10-06 12:14 本次重新运行 `./release.sh --platform ios`：141 项 Flutter 测试及静态检查通过，iOS/Apple Watch Archive 与 App Store IPA 导出成功。当前候选包仍为 `1.0.3 (48)`（旧包从未上传，无已占用构建号），位于 `release-artifacts/release-history/1.0.3-ce3cee6b+48/20261006121454-37947/ios/AI-Link-1.0.3+48.ipa`；不要使用上午的无内购旧包。

解压复查：手机与手表均含两项正式 StoreKit 商品 ID，深层签名有效、Apple Distribution、`get-task-allow=false`；本地 `.storekit` 配置及 `--storekit-test` Debug 启用参数均未进入该 IPA。尚未上传 Apple 或真实沙盒验证，第三方共享许可及其他上架待办仍未完成；此包仅为本地发布候选。

## 本地商店素材

2026-10-06 已准备中文 iPhone 中等显示屏推荐截图 5 张（1206 × 2622，另有可选欢迎页 1 张）及大屏备选截图 6 张（1320 × 2868）、iPad 横屏截图 3 张、Apple Watch 截图 2 张，以及生产版 1024 图标。尺寸、RGB 和透明通道检查通过，均为实际应用模拟器原生截图，聊天使用公开示例，不包含用户真机私人聊天与密钥；不代表配对真机或真实服务验证。

预览、清单与上传顺序见 [商店素材说明](../app_store/README.md)；压缩包保存在忽略的 `release-artifacts/app-store/AI-Link-App-Store-zh-Hans-20261006.zip`。本轮 10 张推荐截图已上传至 App Store Connect 简体中文版本草稿（随后版本号更新为 1.0.3）；重新打开设备页面后确认 iPhone 5/10、iPad 3/10、Apple Watch 2/10，文件顺序正确。大屏备选、欢迎页和图标未作为截图上传。未提交审核。新增购买页已在本地 StoreKit 模拟器显示，价格 ¥70.00；实际截图位于 `doc/app_store/zh-Hans/iap/01-trial-and-unlock.jpg`，尚未上传两项内购审核。

## 接下来的必需工作

1. App Store Connect「商务」当前免费 App 协议有效，付费 App 协议状态为「新」，页面要求签署后才能销售付费内购。由账号持有人阅读、签署，并按界面要求完成银行及税务资料；不要替用户填报未知事实。
2. 已接入 StoreKit 2、7 天试用、恢复购买及退款/撤销，手机与手表分别验证交易，不信任配置开关；到期后保留历史与配置。完整行为、校时规则与验证边界见 [购买实现](purchases.md)。2026-10-06 最终静态检查无问题、Flutter 141 项通过、原生 StoreKit 3 项通过、手表本地协议回归通过。真实沙盒、实体配对 Watch、离线/修改时间仍须验证。
3. 完成 StoreKit 本地与 Apple 沙盒购买验证，再生成最终 IPA；真实商店商品、付款、退款与恢复证据须分别报告。
4. 补齐第三方 AI/语音/搜索数据共享的明确许可，以及联网搜索相关的线上隐私说明。Google Analytics 管理页当前报 `ERR_CONNECTION_CLOSED`，广告相关设置及账号数据共享仍未确认；Firebase「允许 Google 使用服务数据」选项不是 Analytics 广告设置，不能据此判定追踪行为。
5. 确认中国大陆 App 备案与 AI 应用登记的适用性、实际服务范围及所需材料；未完成前不能宣称已满足大陆发行条件。核对已准备的商店截图与最终包一致，补齐内购审核截图、审核资料、年龄/内容问卷与最终包行为核对，提交 App 和首批内购共同审核。

## 官方依据

- [Apple 审核指南 3.1.1（非订阅应用零价试用商品）](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)
- [创建消耗型及非消耗型内购](https://developer.apple.com/cn/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases)
- [首批内购随新 App 版本提交](https://developer.apple.com/cn/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- [Apple App 信息中的大陆供应情况](https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information/)
- [网信办关于通过 API 调用已备案模型的应用登记公告](https://www.cac.gov.cn/2026-09/14/c_1791136833136332.htm)
