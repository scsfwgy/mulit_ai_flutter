# DeepSeek 语音服务

在「设置 → 语音服务 → 添加语音提供商」选择 DeepSeek。
已有官方 DeepSeek 文字服务时，优先引用其服务 ID，无需再次填写 API Key；可在「密钥来源」选择其它官方 DeepSeek 服务或「独立密钥」。独立 Key 保存在安全存储，非密钥配置保存在 SQLite settings。修改文字服务 Key 后，下次请求读取最新 Key；关联服务地址改为其它平台后，不再读取该服务 Key。删除关联文字服务时，沿用既有语音配置清理规则。

文字服务的官方根地址、`/v1` 与 `/anthropic` 地址均可复用 Key，语音请求统一发送到 `https://api.deepseek.com/v1`。自定义代理服务的 Key 不自动提供给 DeepSeek。现有语音服务选择、系统语音默认值及自动朗读开关不受新增服务影响。

- 识别：`POST /tools/asr`，multipart 的 `file` 字段上传录音，读取 JSON `text`，不发送模型 ID。
- 朗读：`POST /tools/tts`，发送 `text`、`voice_id`、`format: pcm` 和 `filter_markdown: true`，读取 24 kHz、16 位、单声道 PCM，并在本地封装带准确长度的标准 WAV，避免 Android 播放器拒绝流式 WAV 的未定长度头。
- 音色：`stella`（海星，女声）、`tide`（暗潮，男声）。不向文字 `/models` 查询语音模型。
- 使用现有 16 kHz、16 位、单声道 PCM WAV 录音流程。手机/桌面在上传前拒绝超过 120 秒或 8 MiB 的 DeepSeek 录音；应用本身的更短录音上限仍有效。
- 手机、桌面、手机后台 worker、Wear OS 直连与 Apple Watch 直连使用相同协议；播放文件后缀与手表中转格式为 WAV。
- 复用 Key 只共用鉴权，语音仍单独计费。请求禁止自动跟随重定向，错误正文与 Key 不显示到界面。

API 文档核对日期：2026-11-14。

- [语音识别](https://api-docs.deepseek.com/zh-cn/guides/asr/)
- [语音合成](https://api-docs.deepseek.com/zh-cn/guides/tts/)

协议、配置页面、Key 引用与独立保存通过本地桩接口测试；真实 DeepSeek 账号配额、识别效果和真机录音/播放仍需实际服务验证。

本次验证：静态分析无问题，Flutter 498 项测试通过、1 项跳过；Wear OS 单元测试与 Debug 构建、iOS Simulator 构建及原生手表本地接口测试通过。独立 Android 模拟器用本地 PCM 接口完成「合成请求 → 标准 WAV 封装 → 播放完成」回归。真实服务的 HTTP 200 与原始 WAV 播放失败来自调试日志；修复后的真实服务播放和配对设备仍需复核。
