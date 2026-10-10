import Flutter
import FirebaseCore
import FirebaseAnalytics
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The downloaded Firebase app is registered for the production bundle only.
    // Debug/Profile bundles retain their own data and do not emit Analytics.
    if Bundle.main.bundleIdentifier == "com.maxhall.ailink" {
      FirebaseApp.configure()
      Analytics.setAnalyticsCollectionEnabled(true)
    }
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    AppleWatchBridge.shared.start()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ApplePurchaseBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    AppleStorefrontBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    AppleWatchBridge.shared.attachCompanionChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
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
