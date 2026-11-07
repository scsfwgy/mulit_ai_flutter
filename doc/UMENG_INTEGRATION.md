# 友盟接入记录

接入日期：2026-11-07。工具：官方 umeng-cli 0.2.17、umeng-skills-index 1.12.1，按 umeng-onboarding 调度官方 Flutter 安装脚本，再做已获准的兼容与设置适配。没有增加聊天业务事件。

## 范围与依赖

| 平台 | AppKey | 渠道 | 新增原生 SDK |
| --- | --- | --- | --- |
| Android 手机 | `6aef1438863270068cba2f0c` | 官网包 `official`；`APP_CHANNEL=google_play` 的包映射为 `googleplay` | common 10.0.1、asms 1.8.7.2、apm 2.0.1 |
| iPhone | `6aef14986545637cd63e583c` | `App Store` | UMCommon 7.7.0、UMDevice 3.6.0、UMAPM 2.1.7 |

Flutter 使用官方 `umeng_common_sdk` 1.3.1、`umeng_apm_sdk` 2.3.7 的本地源码副本，位于 `third_party/`；来源和补丁见该目录 README。公共组件由包管理器合并，只解析一份。原有 Firebase 保留。SDK 不加入桌面、Wear OS 或 Apple Watch。

官方脚本对缓存包所作的修复已保存到仓库，避免只在当前电脑能编译。包括 HTTP 1.x 兼容、当前 Flutter binding、初始化回调，以及关闭采集时清理 Flutter 待发队列并阻止上传。根工程继续使用 HTTP 1.x，没有降级模型或语音请求依赖。

iOS 采用 CocoaPods；保留原有 Firebase SwiftPM 依赖。项目关闭 Flutter 插件的 SwiftPM 自动集成后，macOS 插件也通过 CocoaPods 构建，macOS 本身没有接入友盟。Podfile 的 UMAPM module map 修复会在安装依赖时重复生成。

## 启动与开关

1. Android Application / iOS AppDelegate 先配置原生 APM，关闭模型网络采集、日志回捞和广告归因相关开关；此时不由 Flutter 启动统计。
2. 保留原有 SQLite、语言、服务地区及应用初始化；首帧后读取本地统计偏好。原生存储优先，可从早期 SQLite 设置迁移，清空聊天不重置已保存的开关。
3. 新安装默认开启，没有首次启动同意弹窗；既有明确关闭的选择继续保持关闭。仅正式手机包或显式 QA 构建参与友盟采集。
4. 开启时先配置日志开关和 Common SDK（AppKey、渠道），再启用自动页面统计，最后启用 Flutter APM、页面观察与错误处理。复用已有 binding 和应用根节点，不重复 `runApp`。
5. 设置路径：设置 → 通用设置 → 数据与隐私 → 使用统计与诊断。开关统一控制 Firebase 和友盟；关闭后停止使用统计、Flutter 采集和待发报告。已经启动的原生监控没有完整热停止接口，其更改需完全退出并重新启动后完全生效；界面已说明。Android 原生统计关闭后重新开启也以重启后的状态为准。

不向统计附加聊天、提示词、密钥、附件、录音、模型地址或请求正文；Flutter 错误只保留类型和程序包代码堆栈。原生崩溃报告由 SDK 处理。没有为验证加入生产崩溃入口。

## 验证

- `flutter analyze --no-pub` 通过；整套 Flutter 测试 491 项通过、1 项跳过。
- Android 调试与正式包、iOS 配对模拟器、macOS 调试构建通过。用户另提供了 Android 两台设备、iPhone、macOS Release 全部覆盖安装成功的日志；该日志证明安装成功，不证明真机 SDK 上报或商店发布。
- Android 专用模拟器实际操作：默认开关开启；关闭后原生偏好保存为 false，重启没有 SDK 初始化标记；重新开启并重启后恢复 SDK 初始化。
- U-App 三个应用的运行前基线均为 0；本工程 Android、iPhone 均已查询到当日新增用户和启动次数增长。
- 仅在专用 Android / iPhone 模拟器触发测试崩溃。Android 当前崩溃压缩日志上传到 `errnewlog.umeng.com/upload`，SDK 返回 HTTP 200；iPhone 本次崩溃重启后读取并上传，目标进程的对应 HTTP 请求返回 200。
- Flutter 官方异常测试在隔离源码副本中运行：触发与 `captureException` 调用双标记均确认。当前 Android QA 设备未命中免费套餐的 5% Flutter 采样，因此 Dart 异常未实际上传；iPhone QA 日志也显示未命中采样。没有修改后台套餐或采样策略。临时测试源码已还原并删除，模拟器恢复不含触发代码的安装包。
- U-APM 免费套餐不支持当前后台查询接口；没有绕过权限或升级套餐。上述证据确认客户端上传成功，不等于确认控制台入库、聚合或符号化结果。控制台可在稍后查看测试记录。
- AI 自动事件能力不支持本工程的 Flutter 业务代码，本次没有增加 `um_ai_*` 事件。

网页隐私说明在 HomeTools 仓库同步了三种语言。Git 提交与推送不代表网站部署或应用商店发布成功，线上发布状态需另行核验。

## 文件清单

主要入口为 `lib/core/umeng_diagnostics.dart`、`lib/settings/diagnostics_startup.dart`、`lib/settings/privacy_screen.dart`、`lib/main.dart`，原生入口为 `MyApplication.kt`、`MainActivity.kt`、`AppDelegate.swift`。完整本次清单附后（含官方插件源码副本）。

<!-- generated-change-list -->

- `analysis_options.yaml`
- `android/app/build.gradle.kts`
- `android/app/proguard-rules.pro`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/maxhall/ailink/MainActivity.kt`
- `android/app/src/main/kotlin/com/maxhall/ailink/MyApplication.kt`
- `assets/i18n/en.json`
- `assets/i18n/zh-TW.json`
- `assets/i18n/zh.json`
- `doc/UMENG_INTEGRATION.md`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Podfile`
- `ios/Podfile.lock`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner.xcworkspace/contents.xcworkspacedata`
- `ios/Runner/AppDelegate.swift`
- `lib/core/app_platform.dart`
- `lib/core/umeng_diagnostics.dart`
- `lib/main.dart`
- `lib/settings/diagnostics_startup.dart`
- `lib/settings/privacy_screen.dart`
- `macos/Flutter/Flutter-Debug.xcconfig`
- `macos/Flutter/Flutter-Release.xcconfig`
- `macos/Podfile`
- `macos/Podfile.lock`
- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner.xcworkspace/contents.xcworkspacedata`
- `pubspec.lock`
- `pubspec.yaml`
- `test/umeng_diagnostics_test.dart`
- `third_party/README.md`
- `third_party/umeng_apm_sdk/CHANGELOG.md`
- `third_party/umeng_apm_sdk/LICENSE`
- `third_party/umeng_apm_sdk/README.md`
- `third_party/umeng_apm_sdk/android/build.gradle`
- `third_party/umeng_apm_sdk/android/gradle.properties`
- `third_party/umeng_apm_sdk/android/gradle/wrapper/gradle-wrapper.properties`
- `third_party/umeng_apm_sdk/android/settings.gradle`
- `third_party/umeng_apm_sdk/android/src/main/AndroidManifest.xml`
- `third_party/umeng_apm_sdk/android/src/main/java/com/umeng/umeng_apm_sdk/UmengApmSdkPlugin.java`
- `third_party/umeng_apm_sdk/ios/Classes/UmengApmSdkPlugin.h`
- `third_party/umeng_apm_sdk/ios/Classes/UmengApmSdkPlugin.m`
- `third_party/umeng_apm_sdk/ios/umeng_apm_sdk.podspec`
- `third_party/umeng_apm_sdk/lib/src/core/apm_cloud_config_manager.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_event_observer.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_flutter_error.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_init_options.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_log_queue_manager.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_method_channel.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_performance.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_performance_event_center.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_pubsub_event_center.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_report_log.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_request.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_schedule_center.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_scroll_controller.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_setup_trace.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_shared.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_typedef.dart`
- `third_party/umeng_apm_sdk/lib/src/core/apm_widgets_flutter_binding.dart`
- `third_party/umeng_apm_sdk/lib/src/data/api_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/common_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/exception_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/header_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/page_fps_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/page_perf_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/pre_process_data.dart`
- `third_party/umeng_apm_sdk/lib/src/data/pv_data.dart`
- `third_party/umeng_apm_sdk/lib/src/event/app_lifecycle_event.dart`
- `third_party/umeng_apm_sdk/lib/src/event/base_event.dart`
- `third_party/umeng_apm_sdk/lib/src/event/event.dart`
- `third_party/umeng_apm_sdk/lib/src/event/render_event.dart`
- `third_party/umeng_apm_sdk/lib/src/event/router_event.dart`
- `third_party/umeng_apm_sdk/lib/src/observer/flutter_boost_page_observer.dart`
- `third_party/umeng_apm_sdk/lib/src/observer/navigator_observer.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/api_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/common_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/exception_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/page_fps_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/page_perf_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/processor/pv_data_processor.dart`
- `third_party/umeng_apm_sdk/lib/src/recorder/base_recorder.dart`
- `third_party/umeng_apm_sdk/lib/src/recorder/page_fps_recorder.dart`
- `third_party/umeng_apm_sdk/lib/src/recorder/page_perf_recorder.dart`
- `third_party/umeng_apm_sdk/lib/src/recorder/recorder.dart`
- `third_party/umeng_apm_sdk/lib/src/recorder/request_recorder.dart`
- `third_party/umeng_apm_sdk/lib/src/store/global.dart`
- `third_party/umeng_apm_sdk/lib/src/trace/exception_trace.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/cover_caclculate.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/fps_calculate.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/fps_hepler.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/helpers.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/ignore_widget.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/logger.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/render_view_validator.dart`
- `third_party/umeng_apm_sdk/lib/src/utils/utils.dart`
- `third_party/umeng_apm_sdk/lib/umeng_apm_sdk.dart`
- `third_party/umeng_apm_sdk/pubspec.yaml`
- `third_party/umeng_common_sdk/CHANGELOG.md`
- `third_party/umeng_common_sdk/LICENSE`
- `third_party/umeng_common_sdk/README.md`
- `third_party/umeng_common_sdk/android/build.gradle`
- `third_party/umeng_common_sdk/android/gradle.properties`
- `third_party/umeng_common_sdk/android/settings.gradle`
- `third_party/umeng_common_sdk/android/src/main/AndroidManifest.xml`
- `third_party/umeng_common_sdk/android/src/main/java/com/umeng/umeng_common_sdk/UmengCommonSdkPlugin.java`
- `third_party/umeng_common_sdk/android/src/test/kotlin/com/umeng/umeng_common_sdk/UmengCommonSdkPluginTest.kt`
- `third_party/umeng_common_sdk/ios/Classes/UmengCommonSdkPlugin.h`
- `third_party/umeng_common_sdk/ios/Classes/UmengCommonSdkPlugin.m`
- `third_party/umeng_common_sdk/ios/Resources/PrivacyInfo.xcprivacy`
- `third_party/umeng_common_sdk/ios/umeng_common_sdk.podspec`
- `third_party/umeng_common_sdk/lib/umeng_common_sdk.dart`
- `third_party/umeng_common_sdk/pubspec.yaml`
