# Apple 试用与永久解锁

应用免费安装。使用 Apple 非消耗型商品 `com.maxhall.ailink.trial_7_days` 主动领取 7 天全部功能试用；到期后可主动购买 `com.maxhall.ailink.permanent_unlock`。永久商品目标价格为美区 US$10、中国大陆 ¥70，客户端展示 StoreKit 的本地价格。没有自动续费或到期扣款；第三方 API 用量另计。

## 权益规则

- iPhone 和配对 Apple Watch 分别验证 StoreKit 2 的交易签名、商品类型与撤销状态。手机配置中的开关不能给手表授予购买权益。
- 永久权益来自当前有效非消耗型交易；退款/撤销后移除。恢复购买调用 `AppStore.sync()`。
- 试用从已验证历史中最早的试用 `originalPurchaseDate` 开始，持续 604800 秒。退款、重装、恢复购买不重新开始；保留领取历史以阻止重复试用。
- 试用冷启动需要向 `https://www.apple.com/library/test/success.html` 发起 HTTPS HEAD 请求，用响应日期（及缓存 Age）校时；运行期间用系统 uptime 推进，不用用户可修改的墙上时间。请求不携带聊天、密钥或录音。校时失败时暂停试用请求，但仍可阅读历史、编辑配置及恢复/购买。永久解锁无需该校时请求。
- 权益不足时，文字、联网搜索、识别及朗读请求进入购买页；手表提示在手机领取/购买并刷新权益。Android、macOS 的现有免费行为不变，Apple 和 Google 权益不自动互通。

## 开发与测试

普通 Debug/Profile 使用独立 Bundle ID，不要求购买；发布版的正式 Bundle ID 启用购买检查。Debug Swift 编译条件 `DEBUG` 已明确添加至手机与手表 target。

本地内购测试使用共享 `Runner-StoreKit` Scheme：复制普通 Runner 的构建行为，Run 绑定 `ios/AILinkPurchases/AI-Link.storekit` 并传入 `--storekit-test`。本地商品及该参数不会使 Release 版绕过商店验证；本地配置仅加入测试 target 的资源，不随正式 App 打包。不要把本地测试成功说成真实 App Store 付款成功。

```bash
flutter analyze
flutter test
python3 scripts/test_watch_network.py
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner-StoreKit \
  -configuration Debug -destination 'platform=iOS Simulator,name=AI Link Store Required' \
  -parallel-testing-enabled NO -only-testing:RunnerTests
```

2026-10-06：Flutter 购买桥接及过期页面测试 6 项通过；完整 Flutter 141 项通过，静态检查无问题；原生 StoreKit 测试 3 项通过，覆盖试用边界、时钟倒退、试用和买断、等待批准、退款，以及新控制器从商店历史恢复同一试用。iOS/watchOS Debug 与原生测试 bundle 已通过完整 Xcode 编译。测试仅清理该本地 StoreKit 配置的虚拟交易，不清空用户聊天、配置或密钥。

仍需完成：真实 Apple 沙盒商品、取消/购买/恢复/退款、离线冷启动和改设备时间的真机验证、同一账户配对 Watch 恢复及独立网络测试。付费协议、银行/税务资料、销售地区和首批内购共同审核仍为 App Store Connect 前置事项。
