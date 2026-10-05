# macOS 客户端

macOS 与手机共用 Flutter 聊天、协议、模型/语音/搜索配置、Markdown 和本地数据逻辑。当前最低系统版本为 macOS 12，完整 Xcode 构建与运行需要在 Mac 上完成。

## 使用与开发

```bash
flutter pub get
flutter run -d macos
./install-dev.sh --platform macos          # 构建 Debug 并安装到 ~/Applications
./install-dev.sh --platform macos --launch # 安装后打开
```

宽度达到 900 点时，首页左侧只显示历史会话，底部保留设置入口，右侧显示当前聊天。点击设置后，左侧切换为通用设置、模型服务、提示词、语音服务、联网搜索、消息设置、数据与隐私和关于等分类，右侧显示对应详情；编辑服务等子页面也保留分类侧栏。设置侧栏底部可返回聊天，恢复历史列表和当前会话。通用设置直接显示语言、外观与主题色控件，不重复手机端的设置入口列表。详情控制最大宽度，使用桌面标题和留白；切回聊天保留草稿。小窗口恢复会话抽屉。窗口最小为 600 × 500，保存上次位置和大小。桌面页面打开和返回均立即切换，操作菜单居中立即出现；手机端保留原有 Cupertino 页面动画。

- Enter 发送；Shift+Enter 换行；中文输入法组合文本确认期间 Enter 不发送。
- ⌘Enter 发送，⌘N 新对话，⌘, 打开设置，⌘L 聚焦输入框。
- 原生 File 菜单提供 New Conversation，应用菜单提供 Settings。
- 原文复制保留 Markdown；格式化复制同时写入 macOS 剪贴板的 HTML 和纯文本。
- 录音与播放复用现有云端语音服务，按住录音、松开发送和滑动行为与手机一致；不使用系统 ASR/TTS。
- 摄像头扫码导入配置或填写密钥需要相机权限。

macOS 不提供手机与手表配对入口，不接入 Firebase Analytics，也没有手机与电脑之间的配置或聊天自动同步。

开发安装可用 `--device macos` 选择本机，`--macos-dir` 指定安装目录，`--macos-mode debug|profile|release` 选择模式。安装只替换并校验 `.app`，失败恢复旧应用包；Mac 各构建模式共用本机数据，更新时不卸载、不清空数据。

## 数据与权限

应用标识为 `com.maxhall.ailink.macos`。聊天和配置存在本机 SQLite；API Key 在 macOS 登录 Keychain 保存，使用 `MacOsOptions(usesDataProtectionKeychain: false)`，不启用跨应用 Keychain Sharing。手机端安全存储选项不变。保存、删除密钥需使用同一选项。

Debug/Profile 与 Release 均启用 App Sandbox、联网客户端、麦克风和摄像头权限。Debug/Profile 额外保留 Flutter 调试所需的 JIT 和网络服务权限。相机、麦克风只在用户使用对应功能时请求授权。权限拒绝不影响文本聊天。

## 验证

```bash
flutter analyze
flutter test
flutter test integration_test/macos_smoke_test.dart -d macos
flutter build macos --debug
flutter build macos --release
```

原生集成测试只使用本机临时 HTTP 服务和测试密钥，验证 SQLite、Keychain、流式回复、标题、输入框发送、设置快捷键、剪贴板、聊天/设置侧栏切换、服务编辑/返回及草稿保留；测试完成后只删除自身创建的服务和话题，恢复原选择与搜索开关，不清空用户数据。测试会临时替换应用窗口，执行前保存未发送的输入。

手机 UI 回归及截图可运行：

```bash
flutter drive --driver=test_driver/android_ui.dart --target=integration_test/android_ui_smoke_test.dart -d <Android设备ID>
```

截图保存到 `.dart_tool/android-ui-qa/`，覆盖欢迎页、已有聊天、会话抽屉、服务列表和编辑页。测试只使用自建的本地数据，不请求任何服务商。输入框截图不包含系统键盘；键盘遮挡需另用实际软键盘或注入视图遮挡验证。

真实语音服务、不同录音设备、摄像头扫描和其他 Mac 的安装，需要另外实机验证。本机接口测试不能当成服务商实测。

## 本地发布包

```bash
./release-macos.sh
```

脚本先分析与测试，再生成 Release `.app`，归档 DMG、ZIP 和 SHA-256 到被 Git 忽略的 `release-artifacts/macos/`。DMG 内提供 Applications 快捷入口；本机构建位置为 `build/macos/Build/Products/Release/AI Link.app`。

未配置本地证书时默认使用 ad-hoc 签名。它的身份随构建变化，更新后读取旧 Keychain 项可能要求重新授权。推荐将 `macos/Runner/Configs/Signing.local.xcconfig.example` 复制为同目录下被 Git 忽略的 `Signing.local.xcconfig`，填写已安装的 Apple Development 证书和团队；本次已在开发机配置并验证该签名。首次从临时签名迁移时，旧密钥仍可能需要在系统授权弹窗中允许访问；应用不会删除或绕过钥匙串保护。

开发证书签名不等于 Developer ID 签名、公证或 App Store 上架。面向其他用户分发前，需配置 Apple Developer 的 Developer ID Application 身份，对应用及嵌入组件签名、启用 hardened runtime，并完成 Apple 公证及 stapling，再验证其他 Mac 安装。脚本不读取上传凭据，不自动执行公证或发布。
