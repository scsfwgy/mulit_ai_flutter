# 1.0.4 (50) 内购拒审排查

2026-10-07 读取 App Store Connect 当前页面，提交 `7dc02b9a-741d-4ec7-8e9f-e960133049ec` 的 App 版本被拒绝；两项非消耗型内购均在本次提交中，状态为「可供审核」。Apple 在 iPad Air 11-inch (M3)、iPadOS 27.0 上看到试用与买断按钮灰色，商品价格未加载，页面显示商品暂不可用。

## 已核实的阻塞

「商务 → 协议」当前免费 App 协议有效，**付费 App 协议为「新」且未签署**。Apple 明确要求付费 App 协议生效后，付费内购才能在审核沙盒中工作；内购商品本身不要求提前审核通过。因此这是当前必须先解决的后台阻塞，不能用本地 StoreKit 测试通过替代。

实际拒审版本的本地 IPA `release-artifacts/release-history/1.0.4-7ebd31df+50/20261006125543-49783/ios/AI-Link-1.0.4+50.ipa` 解压核对：手机 `com.maxhall.ailink` 与手表 `com.maxhall.ailink.watchkitapp` 均为 1.0.4 (50)，原生二进制均含 `com.maxhall.ailink.permanent_unlock` 与 `com.maxhall.ailink.trial_7_days`；未打包本地 `.storekit` 配置。这不证明 Apple 沙盒能返回商品。

客户端通过 `Product.products(for:)` 读取商品，空结果对应 `productsUnavailable`；试用可用性和永久商品价格决定购买按钮状态，与审核截图一致。此轮未改变购买逻辑，也未绕过交易验证或伪造价格。

## 下一步

1. 账号持有人阅读并确认付费 App 协议，按后台要求填写银行和税务资料，确认协议最终显示「有效」。协议确认涉及法律及结算承诺，不能代填未知事实。当前浏览器已打开待确认条款，未勾选、未同意。
2. 核对两项商品的定价、本地化、审核资料和销售范围，再在无本地 StoreKit 配置的 TestFlight/Apple 沙盒中测试商品加载、领取试用、购买、取消及恢复。特别检查 iPad 上能显示原生本地价格并弹出系统购买确认。
3. 沙盒验证成功后再决定是否沿用 1.0.4 (50) 重新提交，或上传确有客户端修复的新构建。不能只凭协议已签署就声称本次问题已解决；此轮没有回复 Apple 或重新提交。

## 官方依据

- [Configure In-App Purchases for review in the sandbox](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases)
- [View agreements status](https://developer.apple.com/help/app-store-connect/manage-agreements/view-agreements-status)
- [TN3186: Troubleshooting In-App Purchases availability in the sandbox](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox)
