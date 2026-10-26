# 系统分享接收

手机端可通过系统分享接收文字、网页链接、图片和文件。文字与 URL 保存为可移除、可预览的 UTF-8 文本附件；URL 不会自动抓取网页。输入框保留给用户写问题，用户点击发送后才创建话题、保存消息和请求所选模型。

- Android：系统分享选择 AI Link 后直接打开应用。支持单文件、多文件和文字混合分享，冷启动与运行中的应用都进入原生待接收队列。
- iOS：分享表单内选择 AI Link，扩展复制内容并显示“已保存，请打开 AI Link”。用户打开应用后接收为新对话草稿。[Apple 的扩展文档](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html)说明普通 Share Extension 不提供主动打开主应用的能力，因此不使用 responder-chain/UIApplication 绕过方式。
- 默认创建未归属项目的新草稿，沿用当前可用服务和模型；没有服务时仍可接收，发送时再配置。
- 已有未发送文字或附件时先确认：稍后处理保留当前草稿和待接收内容，下次进入前台再次提示；载入新对话会明确丢弃旧草稿。正在生成回复、录音、导入文件或停留在设置等页面时暂缓载入。
- 每批最多 9 个附件，分享的文字占 1 个。文字最多 1 MiB；文件沿用现有附件校验：单个最终文件最多 30 MiB、图片压缩前最多 64 MiB、单条最终附件合计 90 MiB。原生暂存也限制单文件 64 MiB、合计 90 MiB，避免无界复制。
- 原生入口先将临时 URI/NSItemProvider 文件复制到私有暂存区。Flutter 全部成功导入后才确认移除原生副本，失败回滚导入文件并允许稍后重试或删除该批次；不删除来源文件、不在接收时发起网络请求。
- 暂存内容、本地草稿和普通附件均为本机明文。清空本地数据同时清空待接收队列。iOS 共享暂存区不参与 iCloud 备份。

## iOS 签名配置

新增 `AILinkShare` 扩展并嵌入 Runner；Runner 与该扩展使用专用 App Group。手表及 Widget 的 Keychain Sharing 设置不变，不授予它们这个 App Group。

| 构建 | App Group | 扩展 Bundle ID |
| --- | --- | --- |
| Debug/Profile | `group.com.maxhall.ailink.debug.share` | `com.maxhall.ailink.debug.share` |
| Release | `group.com.maxhall.ailink.share` | `com.maxhall.ailink.share` |

在 Apple Developer 为主应用与分享扩展启用对应 App Group、分别关联容器并更新描述文件，才能在真机签名安装。公开 App Store Connect API 的 APP_GROUPS 开关不会自动关联容器；关联需通过开发者网站完成。Debug 与 Release 的分享队列彼此隔离。扩展仅能访问新分享的文件，不持有 API Key、不读聊天数据库。

## 验证

- `test/incoming_share_test.dart`：私有复制、批次失败回滚、数量限制、原生错误与明确确认后 ack。
- `test/incoming_share_ui_test.dart`：冷启动载入、未发送草稿保护、稍后处理、恢复前台与重复通知去重。
- `test/project_ui_test.dart`：对话列表只保留一个可点击筛选标题，项目筛选与抽屉销毁后的选择保留。
- 还需真机验证：Android 的 Documents/相册/浏览器分享、进程重建、撤销读取权限；iOS 的 Safari/照片/文件 App、iCloud 尚未下载文件、取消扩展、签名 App Group 与冷启动接收；大文件及连续多批分享。

本次验证：静态分析无问题，Android Debug APK 构建成功。整套 Flutter 测试通过（357 项，另有 1 项原有跳过），之后新增的空列表筛选标题测试也已单独通过。iOS 完整模拟器 App 和分享扩展构建通过；在新建模拟器中向 App Group 放入专用测试批次，冷启动后已显示本地化文本附件并确认原生暂存批次被移除，未生成对话记录。这只验证了主应用接收链路，不等同于真实宿主 App 的系统分享面板验证。Android 本机没有可用模拟器镜像，本次未完成 Android 模拟器截图及实际分享入口验证。

## 本机签名修复（2026-10-26）

正式版与 Debug 的主应用、分享扩展 App ID 已注册并分别关联对应 App Group。已生成并安装两套开发描述文件，正式版还更新了 App Store 分发描述文件以及本机 IPA 导出映射。

本机 Xcode 未登录账号时，自动签名仍选择旧通配 Profile。现在 `ios/Flutter/Debug.xcconfig` 与 `Release.xcconfig` 通过可选 include 读取忽略的 `localConfig/ios-signing.local.xcconfig`。项目默认保持 Automatic；仅本机配置选择 Manual，并按目标和构建模式指定已安装的描述文件。参考模板为 `scripts/ios-signing.local.xcconfig.example`。签名文件、证书、私钥及 Profile 不入库。更换证书或 Profile 过期后需更新该本机配置。

`install_dev.py` 的临时团队覆盖不再强行改回 Automatic，并校验分享扩展的包标识；20 项安装脚本测试通过。`flutter build ios --release --no-pub` 完整签名构建通过，`codesign --verify --deep --strict` 通过，主应用与扩展均带 `group.com.maxhall.ailink.share`，Watch 和 Widget 没有获得这个 App Group。

本次设备发现未找到可安装的 iPhone，故只完成签名构建，未安装到手机、未上传商店。
