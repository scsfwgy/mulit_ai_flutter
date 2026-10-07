# Apple 试用与永久解锁

应用免费安装。使用 Apple 非消耗型商品 `com.maxhall.ailink.trial_7_days` 主动领取 7 天全部功能试用；到期后可主动购买 `com.maxhall.ailink.permanent_unlock`。永久商品目标价格为美区 US$10、中国大陆 ¥70，客户端展示 StoreKit 的本地价格。没有自动续费或到期扣款；第三方 API 用量另计。

## 权益规则

- iPhone 原生购买控制器是唯一购买权益来源，负责 StoreKit 2 交易验证、领取、购买、恢复和退款。Apple Watch 不查询商品或交易，也不调用商店购买、恢复接口；仅通过配对设备的 WatchConnectivity 通道接收手机原生权益快照。该快照信任配对 iPhone 已完成的 StoreKit 验证，不声称由手表再次独立验证交易签名。Flutter 服务配置中的开关不能授予权益，iPhone 也不接收手表回传的授权。
- 领取、购买和恢复后的权益变化自动推送，手表启动、恢复前台、重连和「刷新购买权益」也会向手机请求最新快照。权益消息独立于服务配置、语言及配置同步请求 ID，更新 applicationContext 时保留其它字段。手表设置显示「7 天试用中」或「已永久解锁」。
- 手表在 Keychain 保存原生权益快照，永久解锁保持至手机同步新的撤销状态，不额外要求每日连接手机。试用的截止时间固定为手机原始领取时间加 604800 秒，手表用可信 HTTPS 时间与 uptime 检查，不因刷新、重启或重新同步延长。旧消息不能覆盖新状态，手机退款/撤销验证后的同步会移除授权；手表离线期间保存最后收到的永久状态，重连后补同步。试用冷启动校时失败时暂停试用请求，但不影响永久解锁。
- 永久权益来自当前有效非消耗型交易；退款/撤销后移除。恢复购买调用 `AppStore.sync()`。
- 购买返回值与 `Transaction.updates` 中的已验证交易先交付权益，再结束交易；后续空查询不覆盖当前进程刚取得的有效交易。查询同时读取商品对应的 `Transaction.latest`，按购买及签名时间合并，同一笔交易的已签名撤销优先于旧购买记录。缓存只存在于当前进程，冷启动仍须由 StoreKit 提供已验证记录，不持久化可修改的解锁布尔值。购买账户及交易范围由 StoreKit 查询与签名验证负责，不另用 App 下载账户筛选内购交易。
- 原生刷新期间收到交易更新会重新查询；传给 Flutter 的状态带递增序号，旧回复不能覆盖新权益。恢复失败提示不会被后台刷新清掉；恢复超过 45 秒会结束界面等待并明确提示，商店查询超过 30 秒也会提示。超时不伪造购买、退款或成功结果，后续已验证通知仍可解锁。
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

## 2026-10-07 修复后的真机复测

此次依据 TestFlight 1.0.4（50）的现场证据修复：系统购买成功但 StoreKit 保存/同步交易出现 `noAccount`，历史与当前权益查询返回 0；恢复操作的失败提示还可能被随后正常刷新覆盖。应用修复不能代替 Apple 恢复其账户或交易服务；本地测试与签名构建也不能证明该真机故障已经解决。

修复后的完整 Flutter 测试 194 项通过，静态检查无问题；其中购买测试还覆盖试用可用不代表永久权益到账。原生 StoreKit 6 项通过，包含真实本地签名购买回调、空查询保留刚验证的权益、同一笔交易退款撤销、旧购买回调不能覆盖撤销、查询与购买交错、未验证交易拒绝解锁，以及冷启动商品专属查询恢复。iOS/watchOS 已通过 Debug 测试编译及 Release 归档/分发签名校验。最终修复测试包使用 1.0.5（58），其编译源码快照及验证日志保存在忽略目录 `release-artifacts/iap-fix-20261007/`；没有清除真机交易、聊天、配置或密钥。

Apple 已确认 1.0.5（58）上传并处理完成，内部状态为 `IN_BETA_TESTING`，已加入现有内部群组 `AI Link Test`。本次交付为 TestFlight 内部测试版本；正式审核构建应在真机复测后选择。

安装修复版 TestFlight 后按以下顺序测试，无需卸载、退出账号或清除购买记录：

1. 进入「设置 → 试用与永久解锁」，已有永久权益应显示「已永久解锁」，不再显示试用与购买按钮。
2. 若仍未识别权益，点一次「恢复购买」。记录顶部结果提示；若商店不响应，应在 45 秒后恢复按钮可用并显示等待超时提示。
3. 若仍未恢复，可在确认是 TestFlight 版本后点「永久解锁」。Apple 若显示“已经购买，免费再获取一次”，确认后应立即显示已解锁；记录系统结果与应用提示。TestFlight 的内购使用沙盒，不产生实际扣款。
4. 等待超过 1 分钟，再点「刷新商店」，确认已解锁状态保留。完全退出应用并重新打开，确认 StoreKit 能恢复权益。
5. 如果失败，保留准确操作时间、TestFlight 版本/构建号和页面结果截图。新原生日志分类为 `com.maxhall.ailink / Purchases`，只记录查询条数、验证/撤销状态、错误域与错误码，不记录收据、交易或账户标识、付款信息、聊天或 API Key。

试用和退款的破坏性场景由独立的本地 StoreKit 虚拟交易回归覆盖；不要为复测清理用户原有购买或聊天记录。
