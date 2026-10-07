import Combine
import Foundation
import StoreKit
import OSLog

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
  private var refreshAgain = false
  private var refreshProducts = false
  private var transactionRevision = 0
  private var revision = 0
  // Only verified purchase/update callbacks enter this process-local fallback.
  // Nothing is persisted as an ownership Boolean; cold starts query StoreKit.
  private var receivedTransactions: [String: Transaction] = [:]
  private var timeAnchor: (date: Date, uptime: TimeInterval)?
  private let readRecords: () async -> Records
  private let synchronize: () async throws -> Void
  private var restoreTask: Task<Void, Error>?
  private static let log = Logger(subsystem: "com.maxhall.ailink", category: "Purchases")

  struct Records {
    var history: [VerificationResult<Transaction>] = []
    var entitlements: [VerificationResult<Transaction>] = []
    var latest: [VerificationResult<Transaction>] = []
  }

  static func storeKitRecords() async -> Records {
    var records = Records()
    for await result in Transaction.all { records.history.append(result) }
    for await result in Transaction.currentEntitlements { records.entitlements.append(result) }
    // A product-specific query also includes revoked transactions. An empty
    // entitlement list alone cannot describe a refund or a delayed purchase.
    for id in [permanentID, trialID] {
      if let result = await Transaction.latest(for: id) { records.latest.append(result) }
    }
    return records
  }

  init(enabled: Bool? = nil,
       readRecords: @escaping () async -> Records = ApplePurchaseStore.storeKitRecords,
       synchronize: @escaping () async throws -> Void = { try await AppStore.sync() }) {
    self.readRecords = readRecords
    self.synchronize = synchronize
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
        guard self.receive(update), case .verified(let transaction) = update else { continue }
        await transaction.finish()
        await self.refresh()
      }
    }
    Task { await refresh(loadProducts: true) }
  }

  func refresh(loadProducts: Bool = false) async {
    guard enabled else { ready = true; return }
    refreshProducts = refreshProducts || loadProducts
    if let running = refreshTask {
      refreshAgain = true
      await running.value
      return
    }
    let task = Task {
      repeat {
        refreshAgain = false
        let load = refreshProducts
        refreshProducts = false
        await readPurchases(loadProducts: load)
      } while refreshAgain
    }
    refreshTask = task
    await task.value
    refreshTask = nil
  }

  private func readPurchases(loadProducts: Bool) async {
    let startedRevision = transactionRevision
    let records = await readRecords()
    Self.log.notice("Query completed: history=\(records.history.count) current=\(records.entitlements.count) latest=\(records.latest.count)")
    var ownsPermanent = false
    var activeTrial = false
    var earliestTrial: Date?
    var sawTrial = false
    var testingTrial = false
    var verificationFailed = false
    // History prevents refunding/reinstalling the trial from creating a new trial.
    for result in records.history {
      guard case .verified(let transaction) = result else { continue }
      if transaction.productID == Self.trialID, transaction.productType == .nonConsumable {
        sawTrial = true
        earliestTrial = min(earliestTrial ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
      }
    }
    var current = receivedTransactions
    for result in records.entitlements + records.latest {
      switch result {
      case .verified(let transaction):
        guard Self.isOurTransaction(transaction) else { continue }
        Self.merge(transaction, into: &current)
      case .unverified: verificationFailed = true
      }
    }
    for transaction in current.values {
        if transaction.productID == Self.trialID {
          sawTrial = true
          earliestTrial = min(earliestTrial ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
        }
        guard transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
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
    }
    // Trial time advances with uptime, not the user-changeable device clock.
    // A cold start needs an HTTPS server time. Read-only screens still work offline.
    if activeTrial && !ownsPermanent && timeAnchor == nil {
      if testingTrial { timeAnchor = (Date(), ProcessInfo.processInfo.systemUptime) }
      else if let serverDate = await Self.fetchAppleTime() {
        timeAnchor = (serverDate, ProcessInfo.processInfo.systemUptime)
      }
    }
    var queryError = verificationFailed ? "verificationFailed" :
      (activeTrial && !ownsPermanent && timeAnchor == nil ? "clockUnavailable" : "")
    if loadProducts || products.isEmpty {
      do {
        products = Dictionary(uniqueKeysWithValues: try await Product.products(for: [Self.permanentID, Self.trialID])
          .filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
        if products.count != 2 && queryError.isEmpty { queryError = "productsUnavailable" }
      } catch { if queryError.isEmpty { queryError = "productsUnavailable" } }
    }
    // A callback can arrive while any query or clock/catalog request is suspended.
    // Do not publish its older snapshot over the just-verified transaction.
    guard startedRevision == transactionRevision else { refreshAgain = true; return }
    for id in Array(receivedTransactions.keys) {
      receivedTransactions[id] = current[id]
    }
    permanent = ownsPermanent
    trialActiveRecord = activeTrial
    trialStart = earliestTrial
    hadTrial = sawTrial
    errorCode = queryError
    ready = true
    publish()
  }

  private static func isOurTransaction(_ transaction: Transaction) -> Bool {
    [permanentID, trialID].contains(transaction.productID) && transaction.productType == .nonConsumable
  }

  private static func merge(_ transaction: Transaction, into records: inout [String: Transaction]) {
    if let old = records[transaction.productID] {
      if transaction.id == old.id {
        // A signed refund for this exact purchase wins over its cached original,
        // including StoreKitTest records whose signing timestamps can differ.
        if old.revocationDate != nil && transaction.revocationDate == nil { return }
        if transaction.revocationDate == nil && transaction.signedDate < old.signedDate { return }
      } else if transaction.purchaseDate != old.purchaseDate {
        // Refunding an older purchase must not revoke a later re-purchase.
        guard transaction.purchaseDate > old.purchaseDate else { return }
      } else {
        guard transaction.signedDate > old.signedDate ||
          (transaction.signedDate == old.signedDate && transaction.revocationDate != nil) else { return }
      }
    }
    records[transaction.productID] = transaction
  }

  // Shared by the purchase return value and Transaction.updates; never accept
  // unsafePayloadValue or a system dialog as evidence of ownership.
  @discardableResult
  func receive(_ result: VerificationResult<Transaction>) -> Bool {
    guard case .verified(let transaction) = result else {
      errorCode = "verificationFailed"
      publish()
      return false
    }
    guard Self.isOurTransaction(transaction) else { return false }
    Self.merge(transaction, into: &receivedTransactions)
    let record = receivedTransactions[transaction.productID]!
    transactionRevision += 1
    let active = record.revocationDate == nil && !record.isUpgraded
    if record.productID == Self.permanentID { permanent = active }
    else {
      hadTrial = true
      trialStart = min(trialStart ?? record.originalPurchaseDate, record.originalPurchaseDate)
      trialActiveRecord = active
      #if DEBUG
      if #available(iOS 16.0, watchOS 9.0, *), record.environment == .xcode, timeAnchor == nil {
        timeAnchor = (Date(), ProcessInfo.processInfo.systemUptime)
      }
      #endif
    }
    ready = true
    errorCode = trialActiveRecord && !permanent && timeAnchor == nil ? "clockUnavailable" : ""
    Self.log.notice("Verified callback: permanent=\(self.permanent) trial=\(self.trialActiveRecord) revoked=\(record.revocationDate != nil)")
    publish()
    return true
  }

  private func publish() {
    revision += 1
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
    if products[id] == nil { await refresh(loadProducts: true) }
    if permanent { return "alreadyOwned" }
    if id == Self.trialID && hadTrial { return "alreadyClaimed" }
    guard let product = products[id] else { throw PurchaseFailure.unavailable }
    switch try await product.purchase() {
    case .success(let result):
      guard case .verified(let transaction) = result,
            transaction.productID == id, transaction.productType == .nonConsumable,
            transaction.revocationDate == nil else { throw PurchaseFailure.unverified }
      receive(result)
      if id == Self.trialID, timeAnchor == nil, !permanent {
        // A replayed trial transaction can have an old signedDate. Obtain fresh
        // server time rather than letting a re-purchase restart an expired trial.
        if let serverDate = await Self.fetchAppleTime() {
          timeAnchor = (serverDate, ProcessInfo.processInfo.systemUptime)
          errorCode = ""
          publish()
        }
      }
      await transaction.finish()
      Task { await refresh() }
      return "success"
    case .pending: return "pending"
    case .userCancelled: return "cancelled"
    @unknown default: throw PurchaseFailure.unavailable
    }
  }

  func restore() async throws {
    Self.log.notice("Restore requested")
    // A UI timeout must not start a second concurrent StoreKit authentication.
    if let running = restoreTask { try await running.value }
    else {
      let task = Task { try await synchronize() }
      restoreTask = task
      do { try await task.value; restoreTask = nil }
      catch {
        restoreTask = nil
        Self.log.error("Restore sync failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
        throw error
      }
    }
    await refresh(loadProducts: true)
    Self.log.notice("Restore completed: permanent=\(self.permanent) trial=\(self.canUse && !self.permanent)")
  }

  var snapshot: [String: Any] {
    var value: [String: Any] = ["enabled": enabled, "ready": ready, "canUse": canUse,
      "permanent": permanent, "hadTrial": hadTrial, "error": errorCode, "revision": revision,
      "trialAvailable": products[Self.trialID] != nil && !hadTrial && !permanent]
    if let end = trialEnd { value["trialEndMs"] = Int64(end.timeIntervalSince1970 * 1000) }
    if let product = products[Self.permanentID] { value["permanentPrice"] = product.displayPrice }
    return value
  }
}

enum PurchaseFailure: Error { case invalidProduct, unavailable, unverified }
