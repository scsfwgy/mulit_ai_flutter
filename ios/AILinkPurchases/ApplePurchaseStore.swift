import Combine
import Foundation
import StoreKit
import OSLog
import Security
import Darwin

/// iPhone StoreKit is the purchase authority. Its paired watch only consumes
/// native entitlement snapshots; watch service configuration never grants access.
@MainActor
final class ApplePurchaseStore: ObservableObject {
  static let permanentID = "com.maxhall.ailink.permanent_unlock"
  static let trialID = "com.maxhall.ailink.trial_7_days"
  static let shared = ApplePurchaseStore()
  nonisolated static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

  let enabled: Bool
  @Published private(set) var ready = false
  @Published private var localPermanent = false
  @Published private var localTrialStart: Date?
  @Published private(set) var trialActiveRecord = false
  @Published private var localHadTrial = false
  @Published private(set) var products: [String: Product] = [:]
  @Published private(set) var errorCode = ""
  var onChange: (() -> Void)?
  private var listener: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var refreshAgain = false
  private var refreshProducts = false
  private var transactionRevision = 0
  private var revision = 0
  // Native StoreKit .verified results are delivered and saved before finish().
  // Keychain retains that verified evidence when StoreKit returns an empty cache.
  private var verifiedTransactions: [String: VerifiedPurchaseRecord] = [:]
  private var timeAnchor: PurchaseClockAnchor?
  private let savePhone: (Data) -> Void
  private let saveClock: (Data) -> Void
  private let uptime: () -> TimeInterval
  private let bootID: () -> String?
  private let useTestingClock: Bool
  private let readRecords: () async -> Records
  private let synchronize: () async throws -> Void
  private var restoreTask: Task<Void, Error>?
  private let clock: () async -> Date?
  private let acceptsCompanion: Bool
  private let saveCompanion: (Data) -> Void
  @Published private var companion: CompanionEntitlement?
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
       synchronize: @escaping () async throws -> Void = { try await AppStore.sync() },
       clock: @escaping () async -> Date? = ApplePurchaseStore.fetchAppleTime,
       acceptsCompanion: Bool = ApplePurchaseStore.isWatch,
       loadCompanion: () -> Data? = CompanionEntitlement.load,
       saveCompanion: @escaping (Data) -> Void = CompanionEntitlement.save,
       loadPhone: @escaping () -> Data? = { PurchaseKeychain.load("phone-verified-state") },
       savePhone: @escaping (Data) -> Void = { PurchaseKeychain.save($0, account: "phone-verified-state") },
       loadClock: () -> Data? = { PurchaseKeychain.load("watch-clock") },
       saveClock: @escaping (Data) -> Void = { PurchaseKeychain.save($0, account: "watch-clock") },
       uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
       bootID: @escaping () -> String? = PurchaseClockAnchor.currentBootID,
       useTestingClock: Bool = true) {
    self.readRecords = readRecords
    self.synchronize = synchronize
    self.clock = clock
    self.acceptsCompanion = acceptsCompanion
    self.saveCompanion = saveCompanion
    self.savePhone = savePhone
    self.saveClock = saveClock
    self.uptime = uptime
    self.bootID = bootID
    self.useTestingClock = useTestingClock
    if acceptsCompanion, let data = loadCompanion(),
       let saved = try? JSONDecoder().decode(CompanionEntitlement.self, from: data), saved.valid {
      companion = saved
    }
    #if DEBUG
    self.enabled = enabled ?? ProcessInfo.processInfo.arguments.contains("--storekit-test")
    #else
    self.enabled = enabled ?? (Bundle.main.bundleIdentifier == "com.maxhall.ailink" ||
      Bundle.main.bundleIdentifier == "com.maxhall.ailink.watchkitapp")
    #endif
    if self.enabled {
      if acceptsCompanion {
        if let data = loadClock(), let anchor = try? JSONDecoder().decode(PurchaseClockAnchor.self, from: data),
           anchor.now(uptime: uptime(), bootID: bootID()) != nil { timeAnchor = anchor }
        ready = companion != nil
      } else if let data = loadPhone(),
                let cache = try? JSONDecoder().decode(PhonePurchaseCache.self, from: data), cache.valid {
        verifiedTransactions = cache.records
        localHadTrial = cache.trialStart != nil
        localTrialStart = cache.trialStart
        localPermanent = cache.records[Self.permanentID]?.active == true
        trialActiveRecord = cache.records[Self.trialID]?.active == true
        if let anchor = cache.clock, anchor.now(uptime: uptime(), bootID: bootID()) != nil { timeAnchor = anchor }
        ready = true
      }
    }
  }

  deinit { listener?.cancel() }

  nonisolated static var isWatch: Bool {
    #if os(watchOS)
    return true
    #else
    return false
    #endif
  }

  private var activeCompanion: CompanionEntitlement? {
    guard let companion else { return nil }
    if companion.permanent { return companion }
    // HTTP Date has one-second precision; allow small inter-device clock skew.
    guard let now, let end = companion.validUntil,
          now.addingTimeInterval(5) >= companion.issuedAt, now < end else { return nil }
    return companion
  }
  var permanent: Bool {
    acceptsCompanion ? (activeCompanion?.permanent ?? false) : localPermanent
  }
  var hadTrial: Bool { acceptsCompanion ? companion?.trialStart != nil : localHadTrial }
  var trialStart: Date? {
    acceptsCompanion ? companion?.trialStart : localTrialStart
  }

  var now: Date? {
    guard let anchor = timeAnchor else { return nil }
    return anchor.date.addingTimeInterval(max(0, uptime() - anchor.uptime))
  }
  var trialEnd: Date? { trialStart?.addingTimeInterval(Self.trialDuration) }
  var canUse: Bool {
    if !enabled { return true }
    if permanent { return true }
    let trialActive = acceptsCompanion ? activeCompanion?.trialActive == true : trialActiveRecord
    guard ready, trialActive,
          let start = trialStart, let now else { return false }
    return Self.trialValid(start: start, now: now)
  }
  static func trialValid(start: Date, now: Date) -> Bool {
    now >= start && now < start.addingTimeInterval(trialDuration)
  }

  func start() {
    guard enabled else { return }
    if acceptsCompanion { Task { await refresh() }; return }
    guard listener == nil else { return }
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
    if acceptsCompanion {
      await refreshCompanionClock()
      ready = true
      publish()
      return
    }
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
    var current = verifiedTransactions
    for result in records.history + records.entitlements + records.latest {
      switch result {
      case .verified(let transaction):
        guard Self.isOurTransaction(transaction) else { continue }
        Self.merge(VerifiedPurchaseRecord(transaction, jws: result.jwsRepresentation), into: &current)
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
            testingTrial = useTestingClock && transaction.environment == "Xcode"
          }
          #endif
        }
    }
    // Trial time advances with uptime, not the user-changeable device clock.
    // Reuse a persisted same-boot anchor; a new boot requires fresh server time.
    if activeTrial && !ownsPermanent && timeAnchor == nil {
      if testingTrial { anchorTime(Date()) }
      else if let serverDate = await clock() {
        anchorTime(serverDate)
      }
    }
    var queryError = verificationFailed ? "verificationFailed" :
      (activeTrial && !ownsPermanent && timeAnchor == nil ? "clockUnavailable" : "")
    if !acceptsCompanion && (loadProducts || products.isEmpty) {
      do {
        products = Dictionary(uniqueKeysWithValues: try await Product.products(for: [Self.permanentID, Self.trialID])
          .filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
        if products.count != 2 && queryError.isEmpty { queryError = "productsUnavailable" }
      } catch { if queryError.isEmpty { queryError = "productsUnavailable" } }
    }
    // A callback can arrive while any query or clock/catalog request is suspended.
    // Do not publish its older snapshot over the just-verified transaction.
    guard startedRevision == transactionRevision else { refreshAgain = true; return }
    verifiedTransactions = current
    localPermanent = ownsPermanent
    trialActiveRecord = activeTrial
    localTrialStart = earliestTrial
    localHadTrial = sawTrial
    errorCode = queryError
    ready = true
    persistPhone()
    publish()
  }

  private static func isOurTransaction(_ transaction: Transaction) -> Bool {
    [permanentID, trialID].contains(transaction.productID) && transaction.productType == .nonConsumable
  }

  private static func merge(_ transaction: VerifiedPurchaseRecord, into records: inout [String: VerifiedPurchaseRecord]) {
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
    guard !acceptsCompanion else { return false }
    guard case .verified(let transaction) = result else {
      errorCode = "verificationFailed"
      publish()
      return false
    }
    guard Self.isOurTransaction(transaction) else { return false }
    Self.merge(VerifiedPurchaseRecord(transaction, jws: result.jwsRepresentation), into: &verifiedTransactions)
    let record = verifiedTransactions[transaction.productID]!
    transactionRevision += 1
    let active = record.revocationDate == nil && !record.isUpgraded
    if record.productID == Self.permanentID { localPermanent = active }
    else {
      localHadTrial = true
      localTrialStart = min(localTrialStart ?? record.originalPurchaseDate, record.originalPurchaseDate)
      trialActiveRecord = active
      #if DEBUG
      if #available(iOS 16.0, watchOS 9.0, *), useTestingClock, record.environment == "Xcode", timeAnchor == nil {
        anchorTime(Date())
      }
      #endif
    }
    ready = true
    errorCode = trialActiveRecord && !permanent && timeAnchor == nil ? "clockUnavailable" : ""
    Self.log.notice("Verified callback: permanent=\(self.permanent) trial=\(self.trialActiveRecord) revoked=\(record.revocationDate != nil)")
    persistPhone()
    publish()
    return true
  }

  private func anchorTime(_ date: Date) {
    timeAnchor = PurchaseClockAnchor(date: date, uptime: uptime(), bootID: bootID())
    if acceptsCompanion, let data = try? JSONEncoder().encode(timeAnchor) { saveClock(data) }
    else { persistPhone() }
  }

  private func persistPhone() {
    guard enabled, !acceptsCompanion, !verifiedTransactions.isEmpty else { return }
    let cache = PhonePurchaseCache(records: verifiedTransactions, trialStart: localTrialStart, clock: timeAnchor)
    if let data = try? JSONEncoder().encode(cache) { savePhone(data) }
  }

  private func publish() {
    revision += 1
    onChange?()
  }

  /// This is produced only by the native iPhone StoreKit controller, never by
  /// Flutter or a user-editable service configuration. Watch access retains the
  /// phone's permanent state and original seven-day trial deadline.
  func companionSnapshot() async -> [String: Any]? {
    guard enabled, ready, !acceptsCompanion else { return nil }
    if timeAnchor == nil, let date = await clock() {
      anchorTime(date)
    }
    guard let now else { return nil }
    let defaults = UserDefaults.standard
    let sequence = defaults.integer(forKey: "ai_link_purchase_companion_sequence") + 1
    defaults.set(sequence, forKey: "ai_link_purchase_companion_sequence")
    let state = CompanionEntitlement(sequence: sequence, issuedAt: now,
      validUntil: trialActiveRecord && !localPermanent ? localTrialStart?.addingTimeInterval(Self.trialDuration) : nil,
      permanent: localPermanent,
      permanentTransactionID: verifiedTransactions[Self.permanentID].map { String($0.id) },
      trialActive: trialActiveRecord, trialStart: localTrialStart,
      trialTransactionID: verifiedTransactions[Self.trialID].map { String($0.id) })
    guard let data = try? JSONEncoder().encode(state),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return value
  }

  /// Call only from the paired WCSession delegate, outside configuration parsing.
  /// Persist the native snapshot in Keychain for watch cold starts.
  @discardableResult
  func receiveCompanion(_ payload: [String: Any], livePhoneTime: Bool = false) -> Bool {
    guard enabled, acceptsCompanion,
          let data = try? JSONSerialization.data(withJSONObject: payload), data.count <= 4_096,
          let state = try? JSONDecoder().decode(CompanionEntitlement.self, from: data), state.valid else { return false }
    if let old = companion {
      guard state.issuedAt > old.issuedAt ||
        (state.issuedAt == old.issuedAt && state.sequence > old.sequence) else { return false }
    }
    companion = state
    saveCompanion(data)
    // The paired phone already checked trial time. Do not require an unrelated
    // HTTPS request from the watch before honoring its fresh assertion.
    if livePhoneTime, timeAnchor == nil || (now.map { state.issuedAt > $0 } ?? true) {
      anchorTime(state.issuedAt)
      if errorCode == "clockUnavailable" { errorCode = "" }
    }
    ready = true
    publish()
    return true
  }

  func refreshCompanionClock() async {
    guard acceptsCompanion, let companion, companion.trialActive, !companion.permanent,
          timeAnchor == nil else { return }
    if let date = await clock() {
      // A live paired-phone reply may have supplied time during this request.
      if timeAnchor == nil { anchorTime(date) }
      if errorCode == "clockUnavailable" { errorCode = "" }
    } else if timeAnchor == nil { errorCode = "clockUnavailable" }
    publish()
  }

  static func fetchAppleTime() async -> Date? {
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

  func purchase(_ id: String, requireFree: Bool = false) async throws -> String {
    guard !acceptsCompanion else { throw PurchaseFailure.unavailable }
    guard [Self.permanentID, Self.trialID].contains(id) else { throw PurchaseFailure.invalidProduct }
    if requireFree {
      guard enabled, id == Self.permanentID else { throw PurchaseFailure.unavailable }
      // Fetch a fresh Product for this tap. Never turn a free-claim action into
      // a paid purchase when the promotion ends or an old catalog is cached.
      guard let fresh = try await Product.products(for: [id]).first,
            fresh.type == .nonConsumable else { throw PurchaseFailure.unavailable }
      products[id] = fresh
      publish()
      guard fresh.price == 0 else { return "offerUnavailable" }
    }
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
        if let serverDate = await clock() {
          anchorTime(serverDate)
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
    guard !acceptsCompanion else { throw PurchaseFailure.unavailable }
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
    if let product = products[Self.permanentID] {
      value["permanentPrice"] = product.displayPrice
      value["permanentFree"] = product.price == 0
    }
    return value
  }
}

enum PurchaseFailure: Error { case invalidProduct, unavailable, unverified }

/// A delivery journal written only after native StoreKit verification. This is
/// trusted Keychain state, not a second verification of an arbitrary cached JWS.
struct VerifiedPurchaseRecord: Codable {
  let productID: String
  let id: UInt64
  let originalPurchaseDate: Date
  let purchaseDate: Date
  let signedDate: Date
  let revocationDate: Date?
  let isUpgraded: Bool
  let environment: String
  let jws: String

  init(_ transaction: Transaction, jws: String) {
    productID = transaction.productID
    id = transaction.id
    originalPurchaseDate = transaction.originalPurchaseDate
    purchaseDate = transaction.purchaseDate
    signedDate = transaction.signedDate
    revocationDate = transaction.revocationDate
    isUpgraded = transaction.isUpgraded
    if #available(iOS 16.0, watchOS 9.0, *) { environment = transaction.environment.rawValue }
    else { environment = "" }
    self.jws = jws
  }
  var active: Bool { revocationDate == nil && !isUpgraded }
  var valid: Bool {
    ["com.maxhall.ailink.permanent_unlock", "com.maxhall.ailink.trial_7_days"].contains(productID) &&
      id > 0 && jws.split(separator: ".", omittingEmptySubsequences: false).count == 3 &&
      !jws.isEmpty && jws.utf8.count < 100_000 &&
      [originalPurchaseDate, purchaseDate, signedDate].allSatisfy { $0.timeIntervalSince1970.isFinite } &&
      (revocationDate.map { $0.timeIntervalSince1970.isFinite } ?? true)
  }
}

struct PhonePurchaseCache: Codable {
  var version = 1
  var bundleID = Bundle.main.bundleIdentifier ?? ""
  let records: [String: VerifiedPurchaseRecord]
  let trialStart: Date?
  let clock: PurchaseClockAnchor?
  var valid: Bool {
    version == 1 && bundleID == Bundle.main.bundleIdentifier && !records.isEmpty && records.count <= 2 &&
      records.allSatisfy { $0.key == $0.value.productID && $0.value.valid } &&
      (trialStart.map { $0.timeIntervalSince1970.isFinite &&
        $0 <= (records["com.maxhall.ailink.trial_7_days"]?.originalPurchaseDate ?? $0) } ??
        (records["com.maxhall.ailink.trial_7_days"] == nil))
  }
}

/// Persisted uptime anchors survive process restarts. A new boot must obtain a
/// fresh server/paired-phone time; replaying an old anchor never resets a trial.
struct PurchaseClockAnchor: Codable {
  let date: Date
  let uptime: TimeInterval
  let bootID: String?
  func now(uptime current: TimeInterval, bootID currentBoot: String?) -> Date? {
    guard let bootID, bootID == currentBoot, date.timeIntervalSince1970.isFinite,
          uptime.isFinite, uptime >= 0, current.isFinite, current >= uptime else { return nil }
    return date.addingTimeInterval(current - uptime)
  }
  static func currentBootID() -> String? {
    var size = 0
    if sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 {
      var bytes = [CChar](repeating: 0, count: size)
      if sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 { return String(cString: bytes) }
    }
    var boot = timeval()
    size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
    return "\(boot.tv_sec):\(boot.tv_usec)"
  }
}

enum PurchaseKeychain {
  private static func key(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "com.maxhall.ailink.native.purchases",
     kSecAttrAccount as String: account]
  }
  static func load(_ account: String) -> Data? {
    var query = key(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
  }
  static func remove(_ account: String) { SecItemDelete(key(account) as CFDictionary) }
  static func save(_ data: Data, account: String) {
    let attributes = [kSecValueData as String: data]
    if SecItemUpdate(key(account) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
      var entry = key(account)
      entry[kSecValueData as String] = data
      entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(entry as CFDictionary, nil)
    }
  }
}

/// A native, authenticated paired-phone assertion, not an independently verified
/// StoreKit receipt. Only WCSession may import it. Trial expiry comes from iPhone.
struct CompanionEntitlement: Codable {
  var version = 1
  var sourceBundleID = "com.maxhall.ailink"
  let sequence: Int
  let issuedAt: Date
  let validUntil: Date?
  var permanent: Bool
  let permanentTransactionID: String?
  var trialActive: Bool
  let trialStart: Date?
  let trialTransactionID: String?

  var valid: Bool {
    version == 1 && sourceBundleID == "com.maxhall.ailink" && sequence > 0 &&
      issuedAt.timeIntervalSince1970.isFinite &&
      (!permanent || !(permanentTransactionID ?? "").isEmpty) &&
      (!trialActive || (trialStart != nil && !(trialTransactionID ?? "").isEmpty)) &&
      (trialStart.map { $0.timeIntervalSince1970.isFinite && $0 <= issuedAt } ?? true) &&
      (permanent || !trialActive ? validUntil == nil :
        validUntil == trialStart?.addingTimeInterval(ApplePurchaseStore.trialDuration))
  }

  private static var key: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "com.maxhall.ailink.watch.purchases",
     kSecAttrAccount as String: "paired-native-entitlement"]
  }
  static func load() -> Data? {
    var query = key
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
  }
  static func save(_ data: Data) {
    let attributes = [kSecValueData as String: data]
    if SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
      var entry = key
      entry[kSecValueData as String] = data
      entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(entry as CFDictionary, nil)
    }
  }
}
