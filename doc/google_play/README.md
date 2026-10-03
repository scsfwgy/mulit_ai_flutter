# AI Link 上架资料与待办

包名：`com.maxhall.ailink`。手机与 Wear OS 使用相同包名及上传签名；Wear 为单独的 AAB，`versionCode = 1000000 + Git 提交次数`，手机使用 `git rev-list --count HEAD`。当前手表首次配置依赖手机，因此 manifest 标为 non-standalone。

## 已准备

- `common/app_icon_512.png`：商店图标 512×512 PNG。
- `common/feature_graphic_1024x500.png`：1024×500 特色大图。
- `zh-CN/LISTING.md`、`en-US/LISTING.md`：商店文案草稿；上线前按实际功能复核。
- `wear/`：Wear OS 480×480 模拟器真实界面截图（中英、明暗及设置页），作为审核素材候选；最终上架前仍需核对签名版和实际配置。
- `zh-CN/phone/`、`en-US/phone/`：各 4 张 1080×1920 的真实手机模拟器截图，已转换为无透明通道的 JPEG。截图来自隔离的 Pixel 10 Pro 模拟器和本地测试签名包，作为商店详情草稿；发布前仍需用最终上传签名版本复核应用界面，并补充真实聊天画面。
- `../../release.sh`：先运行分析、测试；默认只构建并归档正式上传签名的手机与 Wear OS AAB，`--test` 只构建本地测试签名的两端 APK。仅显式传入 `--push-release` 才通过 Google Play API 上传两个 AAB，默认进入内部测试轨道。每次归档记录 SHA-256、签名证书、版本号和上传状态。
- `../../android/key.properties.example` 和 `../../android/key.test.properties.example`：两套签名配置模板。测试密钥 `localConfig/ai-link-test.jks` 与实际配置 `android/key.test.properties` 已入库，便于共同测试；正式密钥 `localConfig/ai-link-upload.jks` 和实际配置 `android/key.properties` 仅在本机，始终被 Git 忽略。同一套构建中的手机与手表必须使用同一密钥。
- 官方网站：<https://www.tools24.uk/app/ai-link>；中英文隐私政策：<https://www.tools24.uk/app/ai-link/privacy>。两页已公开可访问；应用内“数据与隐私”和“关于”分别提供入口。

首次配置时已在本机生成两套独立 RSA 4096 / PKCS12 密钥。**正式密钥、`android/key.properties` 和密码必须一起离线备份**；仅备份 keystore 而丢失密码仍无法继续签包。正式密钥、配置、密码及其备份绝对不能提交到 Git、上传到公开网盘或放进截图。测试签名及配置在仓库中，测试密码是公开信息，不能作为正式上传密钥或保护真实用户数据。Google Play 的 Play App Signing 以正式上传证书识别上传包；测试签名只用于本地安装，不可用于 Play 上传。若已有 Play Console 上传证书，必须先比对指纹，不能擅自换钥。

```bash
./release.sh                                      # 只构建正式手机与手表 AAB
./release.sh --test                               # 只构建测试手机与手表 APK
./release.sh --push-release --play-track internal # 构建并上传到手机及 Wear OS 内部测试轨道
```

上传脚本使用 `localConfig/google-play-service-account.json`（Git 忽略）或 `PLAY_SERVICE_ACCOUNT_JSON` 指定的现有服务账号 JSON。当前机器上的本地路径已链接到 Tools24 使用的同一 API 账号；仓库源码不依赖 Tools24 的路径，也不复制或提交账号私钥。首次在其他机器运行时需自行配置该文件。`--play-track` 支持 `internal`、`alpha`、`beta`、`production`；手机使用所选轨道，Wear OS 使用 `wear:<轨道>`。脚本在一次 Play 编辑会话中上传两端 AAB，核对版本号与 SHA-256，校验编辑后才提交；失败不会提交该编辑。版本更新日志见 `release_notes.json`。基础版本由 `pubspec.yaml` 管理；发布脚本以 Git 提交次数作为手机 versionCode，手表加 1,000,000，versionName 为基础版本加 8 位 HEAD 哈希，与 Tools24 一致。浅克隆禁止发布，同一 HEAD 重打包不递增版本 Code；上传前须确保新提交次数高于已上传版本。关于页分开显示版本及版本 Code，正式 Play 包版本追加 `(gp)`，测试包不标渠道。

Google [技术质量要求](https://support.google.com/googleplay/android-developer/answer/17492799?hl=en)从 2027 年 2 月起对 DEX 超过 10 MB 的普通应用要求混淆、优化及裁剪各至少 25%，覆盖所有设备形态。开启 R8 不等于已达到百分比，须在 Play Console 的 App bundle explorer 核对最终上传包。

手机及手表 Release 均启用 R8 混淆、代码优化与资源裁剪；手机额外启用 Dart 混淆及调试符号拆分。每次归档保存两端 R8 映射和 Dart 符号，须与产物一起保留以还原堆栈。

上传前需在 Play Console 完成 Play App Signing、Wear OS form factor 和相关应用内容设置。2026-09-30 API 已可见 `wear:internal`、`wear:beta`、`wear:production`，但尚无 `wear:alpha`；选择 `--play-track alpha` 时，脚本会在同一编辑会话中创建对应的 Wear OS 封闭测试轨道，再上传两端 AAB。其他缺失的 Wear OS 轨道仍会在构建前停止。提交成功只表示 API 编辑已提交，审核与上线状态以 Console 为准；脚本不会自动完成问卷，也不会上传 Tools24 专用的 OSS/官网发布接口。每次正式上传前更新 `release_notes.json` 的版本说明。

正式包「AI Link」使用 `com.maxhall.ailink`；普通 `flutter run`/Debug APK 和 `./release.sh --test` 均为「AI Link Debug」，使用 `com.maxhall.ailink.debug` 及仓库中的测试签名，彼此可覆盖更新，并可与正式包同时安装。手机与 Wear OS 必须安装同一类型的包，才能满足 Data Layer 的包名与签名匹配要求。正式版与测试版的本地数据、密钥和手表同步各自独立。旧测试包仍保留原包名及数据，不会迁移到新测试包；**不要通过卸载或清除数据来强行切换签名**。

本机新建证书的公开 SHA-256 指纹如下（不含私钥或密码）。两端同档产物已验签一致；在 Play Console 首次登记上传证书前再次核对，已有应用则先核对原上传证书，不能直接替换。

| 用途 | 证书 SHA-256 |
| --- | --- |
| 正式上传 | `7D:40:42:72:92:83:07:84:C3:DB:74:56:0D:3F:13:68:B9:A0:B8:E5:DA:CD:6D:73:FF:BB:D4:A7:71:D2:11:DE` |
| 本地测试 | `F5:39:89:7F:7B:78:64:86:EB:C4:4F:13:83:AF:43:4D:CE:6A:E6:BB:3E:D1:2D:CF:36:3F:6F:46:33:B8:59:6F` |

## 上架前仍需完成

截至 2026-09-30，Play Console 中的 `com.maxhall.ailink` 已建立为草稿。使用有权访问该应用的 API 账户，已保存并回读确认：默认语言、联系网站和邮箱、中英文商品详情文案、图标、特色大图、中英文各 4 张手机截图，以及中文 1 张、英文 3 张 Wear OS 截图。Console 中还已保存隐私政策 URL、效率应用分类、无广告、非政府应用、无金融和健康功能、未使用广告 ID 的声明。API 查询未发现任何测试或正式轨道版本。上述素材和声明仍需与最终安装包一起复核，不能视为已完成发布或审核。

1. 确定 Play Console 开发者名称；支持邮箱为 `mateolim93@gmail.com`。公开隐私政策已上线，Console 已填写 <https://www.tools24.uk/app/ai-link/privacy>；发布前再核对线上正文与最终安装包行为。仓库中的 `zh-CN/PRIVACY_POLICY_DRAFT.md` 和 `en-US/PRIVACY_POLICY_DRAFT.md` 是历史草稿，以线上正式版为准。
2. 在 Play Console 完成应用访问、Data safety、目标受众和内容分级问卷。应用核心功能需用户自有 API Key；审核用访问说明需要独立、可撤销且限额的测试配置，不能使用真实用户密钥或误报为无需访问条件。Data safety 需结合实际依赖和所接第三方服务逐项核对，不能仅凭“本地保存”判定为不收集/不共享。
3. 为 AI 生成内容提供应用内举报/反馈入口和实际接收、处置流程；目前尚未实现，**上架前阻塞项**。
4. 用最终签名版本复核已上传的手机与 Wear OS 截图，并补充体现实际聊天体验的真实画面。`wear/` 和 `*/phone/` 是已上传的草稿素材；不能用设计稿代替真实界面。Wear OS 至少一张 1:1、最小 384×384 的真实应用截图，不能加设备框。商店图标已改为白色背景、天蓝色与绿色气泡；官网图标和特色大图若需要统一视觉，发布前同步更新。
5. Play Console 应用已建立；仍需配置 Wear OS form factor，先上传到测试轨道，检查预发布报告、设备兼容性、权限说明、配对和断连流程，再提交审核。不要把本地 AAB 构建成功或商品素材保存当作已上架。
6. 核对 Android 目标 API：截至 2026-09-29，新手机应用需 API 36+，Wear OS 需 API 35+。重新发布时按当日官方要求复核。
7. 更换包名后，旧 `com.example.mulit_ai_flutter` 的本地 SQLite 与安全存储不会自动迁移到新包；旧应用可并存。对已有测试数据须先制定迁移或导出方案，不能直接卸载旧包。
8. 真实手机与至少一款 Wear OS 设备验证安装引导、两端签名一致、语音权限、电话/手表网络切换、离线记录同步、手机 App 语言同步与手表系统日夜模式。iOS 工程存在，但本轮未构建验证。

## 官方依据

- [Wear OS 打包与分发](https://developer.android.com/training/wearables/packaging)
- [Android 应用签名](https://developer.android.com/studio/publish/app-signing)
- [Google Play 素材规范](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [目标 API 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [用户数据与隐私政策](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [AI 生成内容政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en)
