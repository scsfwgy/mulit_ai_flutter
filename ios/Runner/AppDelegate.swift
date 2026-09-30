import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    AppleWatchBridge.shared.start()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
