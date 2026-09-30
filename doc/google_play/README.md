# AI Link 上架资料与待办

包名：`com.maxhall.ailink`。手机与 Wear OS 使用相同包名及上传签名；Wear 为单独的 AAB，`versionCode = 1000000 + pubspec 构建号`，手机使用 `pubspec` 构建号。当前手表首次配置依赖手机，因此 manifest 标为 non-standalone。

## 已准备

- `common/app_icon_512.png`：商店图标 512×512 PNG。
- `common/feature_graphic_1024x500.png`：1024×500 特色大图。
- `zh-CN/LISTING.md`、`en-US/LISTING.md`：商店文案草稿；上线前按实际功能复核。
- `wear/`：Wear OS 480×480 模拟器真实界面截图（中英、明暗及设置页），作为审核素材候选；最终上架前仍需核对签名版和实际配置。
- `../../release.sh`：本地运行分析、测试；默认用正式上传密钥构建手机与 Wear OS AAB，`--test` 用独立测试密钥构建两端可安装 APK；产物记录 SHA-256，均不会上传。
- `../../android/key.properties.example` 和 `../../android/key.test.properties.example`：两套签名配置模板。本机正式密钥 `localConfig/ai-link-upload.jks`、测试密钥 `localConfig/ai-link-test.jks` 以及两个实际 properties 文件均被 Git 忽略；同一套构建中的手机与手表必须使用同一密钥。
- 官方网站：<https://www.tools24.uk/app/ai-link>；中英文隐私政策：<https://www.tools24.uk/app/ai-link/privacy>。两页已公开可访问；应用内“数据与隐私”和“关于”分别提供入口。

首次配置时已在本机生成两套独立 RSA 4096 / PKCS12 密钥。**正式密钥、`android/key.properties` 和密码必须一起离线备份**；仅备份 keystore 而丢失密码仍无法继续签包。切勿将密钥、properties、密码或含密钥的压缩包提交到 Git、上传到公开网盘或放进截图。Google Play 的 Play App Signing 以正式上传证书识别上传包；测试签名只用于本地安装，不可用于 Play 上传。若已有 Play Console 上传证书，必须先比对指纹，不能擅自换钥。

```bash
./release.sh --test  # 测试签名：手机和手表 APK
./release.sh         # 正式上传签名：手机和手表 AAB
```

两种包使用同一个应用 ID `com.maxhall.ailink`，但证书不同，无法在同一设备上互相覆盖安装。测试前先确认设备中是否有需要保留的聊天和密钥；**不要通过卸载或清除数据来强行切换签名**。普通 `flutter run`/Debug APK 仍使用 Android SDK 默认调试证书，与这里的测试签名也不同。

本机新建证书的公开 SHA-256 指纹如下（不含私钥或密码）。两端同档产物已验签一致；在 Play Console 首次登记上传证书前再次核对，已有应用则先核对原上传证书，不能直接替换。

| 用途 | 证书 SHA-256 |
| --- | --- |
| 正式上传 | `7D:40:42:72:92:83:07:84:C3:DB:74:56:0D:3F:13:68:B9:A0:B8:E5:DA:CD:6D:73:FF:BB:D4:A7:71:D2:11:DE` |
| 本地测试 | `F5:39:89:7F:7B:78:64:86:EB:C4:4F:13:83:AF:43:4D:CE:6A:E6:BB:3E:D1:2D:CF:36:3F:6F:46:33:B8:59:6F` |

## 上架前仍需完成

1. 确定 Play Console 开发者名称；支持邮箱为 `mateolim93@gmail.com`。公开隐私政策已上线，上架填写 <https://www.tools24.uk/app/ai-link/privacy>，发布前再核对线上正文与最终安装包行为。仓库中的 `zh-CN/PRIVACY_POLICY_DRAFT.md` 和 `en-US/PRIVACY_POLICY_DRAFT.md` 是历史草稿，以线上正式版为准。
2. 在 Play Console 完成 Data safety、目标受众、内容分级、广告与应用访问等问卷。Data safety 需结合实际依赖和所接第三方服务逐项核对，不能仅凭“本地保存”判定为不收集/不共享。
3. 为 AI 生成内容提供应用内举报/反馈入口和实际接收、处置流程；目前尚未实现，**上架前阻塞项**。
4. 用最终签名版本，在真实或模拟设备上采集真实手机截图和 Wear OS 截图。手机截图仍未准备，`wear/` 是尚待最终审核的真实模拟器截图候选；不能用设计稿代替真实界面。Wear OS 至少一张 1:1、最小 384×384 的真实应用截图，不能加设备框。商店图标已改为白色背景、天蓝色与绿色气泡；官网图标和特色大图若需要统一视觉，发布前同步更新。
5. 建立 Play Console 应用和 Wear OS form factor，先上传到测试轨道，检查预发布报告、设备兼容性、权限说明、配对和断连流程，再提交审核。不要把本地 AAB 构建成功当作已上架。
6. 核对 Android 目标 API：截至 2026-09-29，新手机应用需 API 36+，Wear OS 需 API 35+。重新发布时按当日官方要求复核。
7. 更换包名后，旧 `com.example.mulit_ai_flutter` 的本地 SQLite 与安全存储不会自动迁移到新包；旧应用可并存。对已有测试数据须先制定迁移或导出方案，不能直接卸载旧包。
8. 真实手机与至少一款 Wear OS 设备验证安装引导、两端签名一致、语音权限、电话/手表网络切换、离线记录同步与系统语言/主题。iOS 工程存在，但本轮未构建验证。

## 官方依据

- [Wear OS 打包与分发](https://developer.android.com/training/wearables/packaging)
- [Android 应用签名](https://developer.android.com/studio/publish/app-signing)
- [Google Play 素材规范](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [目标 API 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [用户数据与隐私政策](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [AI 生成内容政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en)
