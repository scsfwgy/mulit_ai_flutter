# 聊天附件

输入区左侧固定一个语音/文字切换按钮，右侧空输入时显示「＋」，输入非空白文字或选中附件后显示「发送」，生成中显示停止。「＋」按「拍照」「相册」「文件」排列；已选附件可在附件栏末尾继续添加。Android/iOS 沿用同一 widget 树；桌面点击「＋」直接打开文件选择器，也可将图片和文件拖入聊天区；手机保留拍照、相册、文件菜单。相册与拍照使用 `image_picker`，文件使用 `file_selector`；本机没有额外上传服务器或公共图床。

## 支持范围

- 图片：JPEG、PNG、GIF、WebP。相册、拍照和文件入口统一经过下文的本机自适应压缩，不请求完整照片元数据。原始 HEIC 等不支持的文件明确提示转为 JPEG。选择器取消不发送任何内容。
- PDF：原文档随请求发送，依赖接口和模型支持；应用内目前只显示文件信息，不渲染 PDF 页面。
- UTF-8 文本与代码：TXT、Markdown、CSV/TSV、JSON/JSONL、YAML、XML、HTML、CSS、常见语言源码与日志。读取文字后作为用户内容块发送，不执行脚本、宏或表格公式。
- DOCX/XLSX、压缩包、音视频及其它二进制格式暂不支持，选取后明确提示。CSV 问答不等于已提供可靠的程序计算能力。
- 模型回复仍按文字与 Markdown 展示；尚未接入生成文件的返回、下载和保存。回复中的链接沿用现有链接打开方式。
- 每条消息图片与文件合计最多 9 个；每个附件最大 10 MB，图片按压缩后大小计算。移除原有 16 MB 合计限制，单条消息可达 9 × 10 MB；预算保留的整个请求上下文附件上限为 90 MB，避免历史附件累积成无限请求。发送前再次检查文件存在性、类型和大小，失败不会静默退回文字请求。

## 选择数量与图片压缩

相册打开前计算 `9 - 已选图片/文件数`，iOS PHPicker 和可用的 Android Photo Picker 在原生选择界面执行该上限；仅剩一格时使用原生单选。Android 先检查 Photo Picker 是否可用，不可用时单选累加；桌面点击「＋」同样采用文件单选累加；拖拽可一次加入多个附件，整体超过剩余名额时不导入本次拖拽，避免静默丢弃文件。文件系统选择器没有统一的限量能力，文件入口使用单选累加。达到 9 个后不再打开选择器；返回后的校验仅用于异常恢复或第三方选择器的防御，不能替代选择时限制。

尺寸采样移植自 [Luban 1.1.8 Engine](https://github.com/Curzibn/Luban/blob/1.1.8/library/src/main/java/top/zibin/luban/Engine.java)，保留其按长宽比区分照片与长图的规则，并参考 [Luban 2](https://github.com/Curzibn/Luban) 的像素保护与膨胀回退。不是微信官方实现，也不声称与微信当前压缩结果完全一致。Apache-2.0 许可放在 `assets/licenses/luban.txt`，应用开源许可页登记 Luban。

- 100 KB 以内保留原始字节；GIF 保留原始动画，较大的 APNG/WebP 也检测动画帧并透传，不静默变成单帧。
- 普通照片按 Luban 的 1664/4990/10240 分段采样，长图按短边比例采样，保持比例，不裁剪、不放大小图。
- 目标解码图像最多 10.24 MP，先使用 Flutter 原生 codec 在目标尺寸解码，再在独立 isolate 编码，逐张处理，不同时展开九张原始照片。旋转方向由原生 codec 处理。
- JPEG 采用质量 85（相对于 Luban 1.1.8 的 60 提高质量）；透明图保留 PNG。无透明度的 PNG 同时比较 PNG/JPEG 体积，PNG 不超过 JPEG 的 1.25 倍时保留无损 PNG，优先保留文字与平色截图。
- 输出更大时保留原字节；转换格式时同步更新 MIME、显示扩展名、私有文件扩展名和大小。用户原图不改写。源图片读取另有 64 MB 的内存保护，上传大小仍以处理后的 10 MB 为准；无法处理或处理后仍超限则明确报错，不通过其它服务器压缩。

## 桌面拖拽

macOS、Windows、Linux 通过 `desktop_drop` 接收系统文件投递，只有当前可见且空闲的聊天区域接收附件；话题侧栏及其它页面不作为投递区。拖入显示「松开以添加图片或文件」，松开后复用同一类型、大小、数量、压缩和私有复制流程，不自动发送给模型。文件夹明确拒绝，不递归扫描目录。

macOS 读取带 bookmark 的拖入文件时，临时开启 security-scoped access，等待私有副本导入完成后在 finally 中释放；导入失败同样释放，不持久化 bookmark 或源文件路径。原有 `user-selected.read-only` 沙盒能力保留，不申请整个磁盘访问。使用兼容本仓库 Flutter 3.47.4 的 `desktop_drop` 0.8.x；0.9.x 要求更高 SDK，不能直接升级套用新 API。

## 协议与上下文

OpenAI Chat Completions 用 `image_url` 的 Base64 data URL 传图片，用 `file.filename/file_data` 传 PDF。Claude Messages 用 `image`/`document` 加 `source.type=base64`；文本文件两端均使用 `text` 内容块。普通文字消息仍发送原有字符串格式。

不维护模型白名单，未知能力允许尝试。接口明确返回附件类型不支持时显示切换模型和重试入口；切换后由用户主动重试。400/415/422 的其它附件错误只提示检查格式、大小和模型；鉴权、超时及上下文超限保留原有分类。只保留原有明确不支持 `stream_options` 的兼容重试，不自动去掉附件、不自动改模型或把文件上传给其它解析服务。

重试复用已保存的用户消息；多轮追问按预算保留原附件，重启后仍可读取。附件影响本机上下文估算，但视觉与 PDF 成本只做粗估，见 [上下文说明](CHAT_CONTEXT.md)。只有附件、没有问题文字时不运行联网搜索；有问题文字时只将问题发给搜索服务，不主动将文件正文作为搜索词。标题请求仅用文字/文件名和首轮回答，不重复发送原附件。

## 本地保存与隐私

SQLite v6 为 messages 新增可空 attachments 列，保存名称、MIME、大小、本地随机文件名及粗估 Token。旧消息保持无附件，原正文不改写。附件复制到应用私有支持目录的 chat_attachments/，不额外加密；密钥仍留在安全存储，不写入附件元数据。草稿不建立空话题。

移除/取消草稿会清理应用副本，删除话题清理其附件，明确确认的清空数据同时清理本机附件；启动清理旧的无引用副本。用户选择的原始文件不受影响。发送后附件或文本直接交给所选模型服务，后续追问可能再次发送；切换服务后重试会发送至新选服务。删除本机内容不能撤回第三方已接收内容。未引入服务端 Files API，因此没有远端 file_id 或额外远端删除操作。

应用内简中、繁中、英文隐私说明已补充附件数据流。发布前还需同步官网公开隐私政策；本次没有修改或发布 HomeTools 网站。附件不进入统计、日志、自动朗读或手表同步；手表继续使用原有文字/语音链路。

## 验证

- `test/chat_attachment_test.dart`：类型、编码、大小、路径边界、私有副本、孤儿清理；两类协议的附件块、多轮追问、兼容重试、鉴权与能力错误、缺失文件和裁剪顺序。
- `test/chat_attachment_storage_test.dart`：从 v5 迁移只新增可空列，不删除历史；元数据随第一条消息事务写入。
- `test/attachment_picker_test.dart`：相册参数在调用前按剩余名额设置，Android 新旧选择器与桌面单选回退，零名额不打开。
- `test/desktop_attachment_drop_test.dart`：原生投递事件、悬停反馈、禁用与页面遮挡、macOS 权限生命周期和目录拒绝。
- `test/image_compression_test.dart`：Luban 采样、长图像素上限、小图/动画保留、JPEG 方向、截图无损、透明度、跨入口压缩和原文件保留。
- `test/chat_attachments_ui_test.dart`：三语言、深色、窄屏和键盘占位下的输入区及可操作错误入口。
- iOS 模拟器集成：`flutter drive --driver=test_driver/android_ui.dart --target=integration_test/chat_attachments_smoke_test.dart -d <simulator-id>`。相册、拍照、文件选择器结果由原生通道桩提供，键盘文字使用测试输入；真实私有文件、SQLite、Keychain、本机 HTTP/SSE 和界面完成发送、拒绝、重试、追问、重载、预览与删除。测试仅清理自身数据并恢复设置，不清空或卸载应用。驱动沿用现有截图目录 `.dart_tool/android-ui-qa/`，新截图使用 `ios-attachment-` 与 `ios-composer-` 前缀。
- 选择器通道桩不代表相机硬件、相册权限或云盘文件下载已实测；本机接口不代表真实服务商验收。真机拍照、HEIC 转换与具体模型分析效果仍需真实设备/账户验证。手表未增加附件入口。

iOS 集成验证先单独执行 `flutter build ios --simulator --debug --target=integration_test/chat_attachments_smoke_test.dart -d <simulator-id>`（含手表配套工程时需要指定设备），确认退出成功后再运行上述 drive 命令并加 `--no-build`。测试驱动可能在构建失败后连接旧的已安装测试包；必须同时确认构建日志和当前源码对应的界面，不能只看测试输出末尾的通过提示。

## 接口参考

- [OpenAI 图片输入](https://developers.openai.com/api/docs/guides/images-vision)、[文件输入](https://developers.openai.com/api/docs/guides/file-inputs)
- [Claude 图片输入](https://platform.claude.com/docs/en/build-with-claude/vision)、[PDF 输入](https://platform.claude.com/docs/en/build-with-claude/pdf-support)
- Flutter 插件：[image_picker](https://pub.dev/packages/image_picker)、[file_selector](https://pub.dev/packages/file_selector)

桌面集成使用 `integration_test/desktop_attachments_smoke_test.dart` 和现有截图驱动：先 `flutter build macos --debug --target=integration_test/desktop_attachments_smoke_test.dart`，再 `flutter drive --no-build --driver=test_driver/android_ui.dart --target=integration_test/desktop_attachments_smoke_test.dart -d macos`。模拟原生文件选择与拖拽通道，密钥访问使用空桩而不读取用户 Keychain；测试绑定在窗口隐藏时强制调度渲染帧。真实执行应用状态、文件导入/压缩、移除及原文件保留；不发模型请求、不修改已有服务或话题，并恢复测试前外观设置。通过 Flutter 渲染边界采集 macOS 截图；这不替代 Finder 实际拖拽、其它来源程序和 Windows/Linux 设备验证。
