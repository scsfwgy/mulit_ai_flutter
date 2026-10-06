import Combine
import Foundation
import StoreKit

/// Shared by the companion apps. Both devices verify their own StoreKit records;
/// a phone-supplied Boolean never grants watch access.
@MainActor
final class ApplePurchaseStore: ObservableObject {
  static let permanentID = "com.maxhall.ailink.permanent_unlock"
  static let trialID = "com.maxhall.ailink.trial_7_days"
  static let shared = ApplePurchaseStore()
  static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

  let enabled: Bool
  @Published private(set) var ready = false
  @Published private(set) var permanent = false
  @Published private(set) var trialStart: Date?
  @Published private(set) var trialActiveRecord = false
  @Published private(set) var hadTrial = false
  @Published private(set) var products: [String: Product] = [:]
  @Published private(set) var errorCode = ""
  var onChange: (() -> Void)?
  private var listener: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var timeAnchor: (date: Date, uptime: TimeInterval)?

  init(enabled: Bool? = nil) {
    #if DEBUG
    self.enabled = enabled ?? ProcessInfo.processInfo.arguments.contains("--storekit-test")
    #else
    self.enabled = enabled ?? (Bundle.main.bundleIdentifier == "com.maxhall.ailink" ||
      Bundle.main.bundleIdentifier == "com.maxhall.ailink.watchkitapp")
    #endif
  }

  deinit { listener?.cancel() }

  var now: Date? {
    guard let anchor = timeAnchor else { return nil }
    return anchor.date.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - anchor.uptime))
  }
  var trialEnd: Date? { trialStart?.addingTimeInterval(Self.trialDuration) }
  var canUse: Bool {
    if !enabled { return true }
    if permanent { return true }
    guard ready, trialActiveRecord, let start = trialStart, let now else { return false }
    return Self.trialValid(start: start, now: now)
  }
  static func trialValid(start: Date, now: Date) -> Bool {
    now >= start && now < start.addingTimeInterval(trialDuration)
  }

  func start() {
    guard enabled, listener == nil else { return }
    listener = Task { [weak self] in
      for await update in Transaction.updates {
        guard let self else { return }
        guard case .verified(let transaction) = update,
              [Self.permanentID, Self.trialID].contains(transaction.productID) else { continue }
        await self.refresh()
        await transaction.finish()
      }
    }
    Task { await refresh(loadProducts: true) }
  }

  func refresh(loadProducts: Bool = false) async {
    guard enabled else { ready = true; return }
    if let running = refreshTask { await running.value; return }
    let task = Task { await readPurchases(loadProducts: loadProducts) }
    refreshTask = task
    await task.value
    refreshTask = nil
  }

  private func readPurchases(loadProducts: Bool) async {
    var ownsPermanent = false
    var activeTrial = false
    var earliestTrial: Date?
    var sawTrial = false
    var testingTrial = false
    var verificationFailed = false
    // History prevents refunding/reinstalling the trial from creating a new trial.
    for await result in Transaction.all {
      guard case .verified(let transaction) = result else { continue }
      if transaction.productID == Self.trialID, transaction.productType == .nonConsumable {
        sawTrial = true
        earliestTrial = min(earliestTrial ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
      }
    }
    for await result in Transaction.currentEntitlements {
      switch result {
      case .verified(let transaction):
        guard transaction.productType == .nonConsumable,
              transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
        if transaction.productID == Self.permanentID { ownsPermanent = true }
        if transaction.productID == Self.trialID {
          activeTrial = true
          sawTrial = true
          earliestTrial = min(earliestTrial ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
          #if DEBUG
          if #available(iOS 16.0, watchOS 9.0, *) {
            testingTrial = transaction.environment == .xcode
          }
          #endif
        }
      case .unverified: verificationFailed = true
      }
    }
    // Trial time advances with uptime, not the user-changeable device clock.
    // A cold start needs an HTTPS server time. Read-only screens still work offline.
    if activeTrial && !ownsPermanent && timeAnchor == nil {
      if testingTrial { timeAnchor = (Date(), ProcessInfo.processInfo.systemUptime) }
      else if let serverDate = await Self.fetchAppleTime() {
        timeAnchor = (serverDate, ProcessInfo.processInfo.systemUptime)
      }
    }
    permanent = ownsPermanent
    trialActiveRecord = activeTrial
    trialStart = earliestTrial
    hadTrial = sawTrial
    errorCode = verificationFailed ? "verificationFailed" :
      (activeTrial && !ownsPermanent && timeAnchor == nil ? "clockUnavailable" : "")
    if loadProducts || products.isEmpty {
      do {
        products = Dictionary(uniqueKeysWithValues: try await Product.products(for: [Self.permanentID, Self.trialID])
          .filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
        if products.count != 2 && errorCode.isEmpty { errorCode = "productsUnavailable" }
      } catch { if errorCode.isEmpty { errorCode = "productsUnavailable" } }
    }
    ready = true
    onChange?()
  }

  private static func fetchAppleTime() async -> Date? {
    var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!,
                             cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
    request.httpMethod = "HEAD"
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCache = nil
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    do {
      let (_, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            http.url?.scheme == "https", http.url?.host == "www.apple.com",
            let dateText = http.value(forHTTPHeaderField: "Date") else { return nil }
      let parser = DateFormatter()
      parser.locale = Locale(identifier: "en_US_POSIX")
      parser.timeZone = TimeZone(secondsFromGMT: 0)
      parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
      guard let date = parser.date(from: dateText) else { return nil }
      // A shared HTTP cache may supply an older Date with an Age header.
      let age = TimeInterval(http.value(forHTTPHeaderField: "Age") ?? "0") ?? 0
      guard age >= 0, age.isFinite else { return nil }
      return date.addingTimeInterval(age)
    } catch { return nil }
  }

  func purchase(_ id: String) async throws -> String {
    guard [Self.permanentID, Self.trialID].contains(id) else { throw PurchaseFailure.invalidProduct }
    await refresh(loadProducts: true)
    if permanent { return "alreadyOwned" }
    if id == Self.trialID && hadTrial { return "alreadyClaimed" }
    guard let product = products[id] else { throw PurchaseFailure.unavailable }
    switch try await product.purchase() {
    case .success(let result):
      guard case .verified(let transaction) = result,
            transaction.productID == id, transaction.productType == .nonConsumable,
            transaction.revocationDate == nil else { throw PurchaseFailure.unverified }
      await refresh()
      await transaction.finish()
      return "success"
    case .pending: return "pending"
    case .userCancelled: return "cancelled"
    @unknown default: throw PurchaseFailure.unavailable
    }
  }

  func restore() async throws {
    try await AppStore.sync()
    await refresh(loadProducts: true)
  }

  var snapshot: [String: Any] {
    var value: [String: Any] = ["enabled": enabled, "ready": ready, "canUse": canUse,
      "permanent": permanent, "hadTrial": hadTrial, "error": errorCode,
      "trialAvailable": products[Self.trialID] != nil && !hadTrial && !permanent]
    if let end = trialEnd { value["trialEndMs"] = Int64(end.timeIntervalSince1970 * 1000) }
    if let product = products[Self.permanentID] { value["permanentPrice"] = product.displayPrice }
    return value
  }
}

enum PurchaseFailure: Error { case invalidProduct, unavailable, unverified }
