import Flutter
import StoreKit
import UIKit

/// Each Flutter engine reads the same native storefront, including the worker.
@MainActor
final class AppleStorefrontBridge {
  static let shared = AppleStorefrontBridge()
  private var channels: [FlutterMethodChannel] = []
  private var countryCode: String?
  private var environment = "unknown"
  private var revision = 0
  private var refreshTask: Task<Void, Never>?
  private var updates: Task<Void, Never>?
  private var foregroundObserver: NSObjectProtocol?

  var restricted: Bool { environment != "production" || countryCode == nil || countryCode == "CHN" }
  private var snapshot: [String: Any] {
    ["countryCode": countryCode as Any? ?? NSNull(), "environment": environment, "revision": revision]
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "between_models/storefront", binaryMessenger: messenger)
    channels.append(channel)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "refresh", let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      Task { @MainActor in
        await self.refresh()
        result(self.snapshot)
      }
    }
    if updates == nil {
      updates = Task { @MainActor in
        for await _ in Storefront.updates {
          self.invalidate()
          await self.refresh()
        }
      }
      foregroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.invalidate()
          await self?.refresh()
        }
      }
    }
  }

  func refresh() async {
    if let refreshTask { await refreshTask.value; return }
    let task = Task { @MainActor in await self.readStorefront() }
    refreshTask = task
    await task.value
    refreshTask = nil
  }

  private func readStorefront() async {
    let generation = revision
    // Keep the native watch policy fail-closed too, even if StoreKit never replies.
    let evidence: (String?, String) = await withCheckedContinuation { continuation in
      var pending: CheckedContinuation<(String?, String), Never>? = continuation
      var read: Task<Void, Never>?
      var deadline: Task<Void, Never>?
      func finish(_ code: String?, _ environment: String) {
        let result = pending
        pending = nil
        read?.cancel()
        deadline?.cancel()
        result?.resume(returning: (code, environment))
      }
      read = Task { @MainActor in
        let storefront = await Storefront.current
        #if DEBUG
        finish(storefront?.countryCode, "development")
        #else
        // TestFlight/sandbox storefronts may differ from the user's real store.
        // Only a verified production app transaction confirms store distribution.
        if #available(iOS 16.0, *) {
          do {
            if case .verified(let transaction) = try await AppTransaction.shared {
              finish(storefront?.countryCode, transaction.environment == .production ? "production" : "sandbox")
            } else {
              finish(storefront?.countryCode, "unknown")
            }
          } catch {
            finish(storefront?.countryCode, "unknown")
          }
        } else {
          finish(storefront?.countryCode, "unknown")
        }
        #endif
      }
      deadline = Task { @MainActor in
        do { try await Task.sleep(nanoseconds: 4_000_000_000) }
        catch { return }
        finish(nil, "unknown")
      }
    }
    // A concurrent foreground/storefront update takes precedence over this read.
    guard revision == generation else { return }
    apply(evidence.0, environment: evidence.1)
  }

  private func invalidate() {
    countryCode = nil
    environment = "unknown"
    revision += 1
    channels.forEach { $0.invokeMethod("changed", arguments: snapshot) }
    AppleWatchBridge.shared.syncStorefrontRestriction()
  }

  private func apply(_ code: String?, environment newEnvironment: String) {
    let normalized = code?.uppercased()
    let country = normalized?.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil ? normalized : nil
    guard country != countryCode || environment != newEnvironment else { return }
    countryCode = country
    environment = newEnvironment
    revision += 1
    channels.forEach { $0.invokeMethod("changed", arguments: snapshot) }
    AppleWatchBridge.shared.syncStorefrontRestriction()
  }
}
