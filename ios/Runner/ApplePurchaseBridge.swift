import Flutter
import Foundation

@MainActor
final class ApplePurchaseBridge {
  static let shared = ApplePurchaseBridge()
  private var channels: [FlutterMethodChannel] = []

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "between_models/apple_purchases", binaryMessenger: messenger)
    channels.append(channel)
    let store = ApplePurchaseStore.shared
    store.onChange = { [weak self] in
      self?.channels.forEach { $0.invokeMethod("changed", arguments: store.snapshot) }
      AppleWatchBridge.shared.syncPurchases()
    }
    channel.setMethodCallHandler { call, result in
      Task { @MainActor in
        do {
          switch call.method {
          case "refresh":
            await store.refresh(loadProducts: (call.arguments as? [String: Any])?["products"] as? Bool == true)
            result(store.snapshot)
          case "purchase":
            guard let id = call.arguments as? String else { throw PurchaseFailure.invalidProduct }
            let outcome = try await store.purchase(id)
            result(["outcome": outcome, "state": store.snapshot])
          case "claimFreePermanent":
            let outcome = try await store.purchase(ApplePurchaseStore.permanentID, requireFree: true)
            result(["outcome": outcome, "state": store.snapshot])
          case "restore":
            try await store.restore()
            result(store.snapshot)
          default: result(FlutterMethodNotImplemented)
          }
        } catch {
          // No transaction receipts, identifiers, or payment details enter Flutter logs.
          result(FlutterError(code: "purchase_failed", message: "purchaseFailed", details: nil))
        }
      }
    }
    store.start()
  }
}
