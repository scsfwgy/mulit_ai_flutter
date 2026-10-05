# 手表语音状态与新话题

Wear OS 与 Apple Watch 的聊天顶部在语音合成、传输和播放器准备期间显示旋转圆弧，在实际播放期间显示动态声波。状态固定在顶部，为聊天内容留出空间，结束、失败或停止后隐藏。

松手发送后，顶部沿用同一旋转圆弧，依次显示「语音识别中」「正在思考」「正在回答」。转文字后等待用户确认时隐藏，确认发送后重新显示；失败或回答完成时隐藏，自动朗读则继续切换至语音加载和播放状态。聊天正文不重复显示这些阶段提示。

在语音加载或播放阶段长按聊天区域，会取消当前朗读并开始新录音。旧音频的迟到结果不能重新播放或覆盖新请求状态。松手发送、取消、转文字确认和实际录音不足 0.6 秒的误触过滤保持原有行为。

双击聊天进入设置，点击「开启新话题」返回空白聊天。此操作停止朗读，重置模型上下文、会话 ID 和消息序号，保留服务配置与录音模式。模型回答或录音进行中不能切换新话题。

手机已有历史保留。手表尚未同步的问答保留在独立待同步队列，重连后继续按原会话 ID 归档至手机；新话题使用新的会话 ID，不与旧话题合并。离线开启新话题不代表记录已经到达手机。

## 验证

- `cd android && ./gradlew :wear:testDebugUnitTest :wear:assembleDebug`
- `python3 scripts/test_watch_network.py`
- `flutter test test/watch_turn_sync_test.dart test/watch_preferences_test.dart`
- Xcode 构建 `AILinkWatch` target，使用 watchOS Simulator SDK；模拟器 target 构建不包括配对手机构建或真机签名。

2026-10-05：以上构建和回归通过。独立 Wear OS 临时模拟器通过加载/播放阶段长按打断、短录音过滤、迟到语音隔离、新话题清空及保留待同步问答的交互检查。两端模拟器已检查语音状态与新话题布局，并补齐中英文文案；Apple Watch 动画截图使用独立测试应用注入显示状态。真实服务、配对真机麦克风/播放路由、手机后台同步仍需实机验证。

同日补充：两端手表构建通过；Wear OS 交互检查覆盖录音松手进入识别动画、确认文字进入模型等待动画、请求结束清除动画及错误提示。识别、思考与回答的顶部布局通过注入测试状态截图检查；Apple Watch 使用独立测试应用检查相同状态。该验证不代表真实模型服务测试。

## Markdown 回复

两端手表的实时回复与已保存问答使用同一套 Markdown 展示，用户输入继续按普通文本显示。支持标题、粗体、斜体、删除线、段落、有序/无序及嵌套列表、引用、分隔线、行内代码、代码块和来源链接。标题限制字号，代码保留原始字符并自动换行；表格按行展开为「列名: 内容」，避免多列挤在小屏上。链接显示来源名称，HTTP/HTTPS 地址交给系统处理，不保证每种手表系统都能打开网页。不加载远程图片，不执行 HTML 或脚本，数学公式未做专用渲染。

Wear OS 使用 Markwon 原生文本样式，Apple Watch 使用 Foundation Markdown 解析与 SwiftUI。Markdown 原文继续完整保存在手表并同步至手机，不在落库或流式回调中删除标记。

Apple 解析回归：`python3 scripts/test_watch_markdown.py`。Wear 原生样式回归：先构建 `:wear:assembleDebugAndroidTest -PwatchTestRunner=com.maxhall.ailink.wear.WatchMarkdownInstrumentation`，安装 Debug 手表包与测试包后运行 `adb -s <设备> shell am instrument -w com.maxhall.ailink.debug.test/com.maxhall.ailink.wear.WatchMarkdownInstrumentation`。此测试只创建内存 TextView，不读写用户配置或问答，也不请求模型。
