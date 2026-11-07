import Flutter
import FirebaseCore
import FirebaseAnalytics
import UIKit
import UMCommon
import UMAPM

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var agentBackgroundTask: UIBackgroundTaskIdentifier = .invalid

  private func beginAgentBackground() {
    if agentBackgroundTask != .invalid { return }
    agentBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AI Link Agent") {
      [weak self] in
      self?.endAgentBackground()
    }
  }

  private func endAgentBackground() {
    let task = agentBackgroundTask
    guard task != .invalid else { return }
    agentBackgroundTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
        // 友盟APM采集开关配置
        let config = UMAPMConfig.default()
        config.crashAndBlockMonitorEnable = true
        config.launchMonitorEnable = true
        config.memMonitorEnable = false
        config.oomMonitorEnable = false
        config.networkEnable = false
        config.logCollectEnable = false
        config.javaScriptBridgeEnable = false
        UMConfigure.setASAEnabled(false)
        UMConfigure.setSKANEnabled(false)
        UMCrashConfigure.setAPMConfig(config)


    // The downloaded Firebase app is registered for the production bundle only.
    // Debug/Profile bundles retain their own data and do not emit Analytics.
    if Bundle.main.bundleIdentifier == "com.maxhall.ailink" {
      FirebaseApp.configure()
      // Wait for the persisted app preference from Flutter before collecting.
      Analytics.setAnalyticsCollectionEnabled(false)
    }
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    AppleWatchBridge.shared.start()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "between_models/diagnostics",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      if call.method == "getEnabled" {
        result(UserDefaults.standard.object(forKey: "shareUsageDiagnostics") as? Bool)
        return
      }
      guard call.method == "setEnabled", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      UserDefaults.standard.set(enabled, forKey: "shareUsageDiagnostics")
      if FirebaseApp.app() != nil {
        Analytics.setAnalyticsCollectionEnabled(enabled)
      }
      UMConfigure.setAnalyticsEnabled(enabled)
      result(nil)
    }
    ApplePurchaseBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    AppleStorefrontBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    SystemVoiceBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    AppleWatchBridge.shared.attachCompanionChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    FlutterMethodChannel(
      name: "between_models/incoming_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "peek":
          if let args = call.arguments as? [String: String], let language = args["language"] {
            UserDefaults(suiteName: ShareInbox.group)?.set(language, forKey: "language")
          }
          result(try ShareInbox.first())
        case "clear":
          if let root = ShareInbox.root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
          }
          result(nil)
        case "ack":
          if let args = call.arguments as? [String: String], let id = args["id"] {
            try ShareInbox.acknowledge(id)
          }
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "share_failed", message: "Share inbox unavailable", details: nil))
      }
    }
    FlutterMethodChannel(
      name: "between_models/agent_background",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        self?.beginAgentBackground()
        result(nil)
      case "end":
        self?.endAgentBackground()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterMethodChannel(
      name: "between_models/clipboard",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      guard call.method == "setHtml" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: String],
            let plain = arguments["plain"],
            let html = arguments["html"] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing clipboard content", details: nil))
        return
      }
      UIPasteboard.general.setItems([[
        "public.utf8-plain-text": plain,
        "public.html": Data(html.utf8)
      ]])
      result(nil)
    }
  }
}
