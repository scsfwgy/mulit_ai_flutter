# AI Link 中文 App Store 素材

2026-10-06 生成，供 App Store Connect 应用 `6819497731` 的简体中文版本使用。10 张推荐截图已上传至简体中文版本草稿，并重新打开各设备页面核对保存数量与顺序：iPhone 5 张、iPad 3 张、Apple Watch 2 张。未提交审核。大屏备选、欢迎页和图标未作为截图上传。

## 上传文件及顺序

| 设备 | 尺寸 | 推荐上传文件（按顺序） |
| --- | --- | --- |
| 带灵动岛的 iPhone（中等显示屏） | 1206 × 2622，竖屏 JPEG | `zh-Hans/iphone/01-chat.jpg`、`02-providers.jpg`、`03-prompts.jpg`、`04-voice-setup.jpg`、`05-settings.jpg` |
| 带灵动岛的 iPhone（大显示屏，选填备份） | 1320 × 2868，竖屏 JPEG | `zh-Hans/iphone-large/` 中的 6 张图片，默认不加入推荐上传组 |
| iPad 13 英寸 | 2752 × 2064，横屏 JPEG | `zh-Hans/ipad/01-chat.jpg`、`02-providers.jpg`、`03-prompts.jpg` |
| Apple Watch Ultra | 422 × 514，JPEG | `zh-Hans/watch/01-chat.jpg`、`02-gestures.jpg` |
| App 图标 | 1024 × 1024，RGB PNG，无透明通道 | `common/app-icon-1024.png` |

`zh-Hans/iphone/06-welcome.jpg` 是可选的空白聊天欢迎页，默认不加入推荐上传顺序。大屏目录也保留同名可选欢迎页。当前 App Store Connect 媒体管理器将中等显示屏列为必填，因此重新在对应尺寸的模拟器原生捕获完整截图，没有将大屏图片缩放充数。

App 图标与生产资产一致，由最终应用构建提供给商店；它不放入截图区域。

Apple 截图格式和尺寸依据：[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。上传时分别选择对应的设备尺寸栏位，不把 iPad 横屏图缩放为 iPhone 图；Watch 使用同一尺寸的一组图片。每组推荐截图均未超过 10 张。

## 内容与来源

- 所有截图均由本次新建的隔离模拟器运行实际应用后，通过 `simctl io screenshot --type=jpeg` 原生捕获；保留原始像素，无裁剪、拉伸、设备边框、鼠标光标或合成界面。
- 手机和 iPad 使用当前 Flutter Debug 模拟器构建，手表使用其中配套的 SwiftUI watchOS 应用。商店截图最初捕获时未修改应用代码；新增内购审核图来自随后接入 StoreKit 的当前实现。
- iPad 状态栏会显示应用名，因此只在临时预览包中将显示名改为与正式包相同的 `AI Link`；Bundle ID 保持 Debug 标识，未改仓库应用配置。
- 聊天和提示词使用本次准备的公开示例，保存在独立模拟器的本机数据中；未使用用户真机私人聊天、API Key、密钥二维码或后台账户资料。
- 示例问答由人工准备，用于展示应用真实的 Markdown、表格、列表与手表问答界面。这些素材不表示真实模型、语音服务、蜂窝网络或配对真机功能已通过测试。
- 模型服务截图展示已有预设，语音截图展示真实的语音服务配置页面且密钥为空；预设模型 ID 不保证某个服务账户具有访问权限。
- 手机/iPad 使用简体中文、浅色外观，状态栏为 9:41；Watch 保留原生系统时钟。
- 新增内购审核截图 `zh-Hans/iap/01-trial-and-unlock.jpg` 为当前实际购买页，1206 × 2622、RGB JPEG，无透明通道。显示免费领取、¥70.00 本地 StoreKit 价格和恢复入口。可以用于两项非消耗型商品审核，不表示真实付款或 Apple 沙盒测试通过；尚未上传。

## 检查及预览

原始图片已逐张检查可读性和内容，所有文件均为 RGB 且无透明通道。`manifest.json` 记录尺寸、字节数、SHA-256 与建议用途。

打开 `preview.html` 可按设备浏览缩略图，点击图片查看原始文件。该页面不请求外部服务。压缩包位于忽略构建目录：

`release-artifacts/app-store/AI-Link-App-Store-zh-Hans-20261006.zip`

商店已接受这 10 张截图并保存为草稿，不表示内购可售或应用已审核通过。最终内购包若改变所展示界面，上传前须核对截图与最终应用一致。
