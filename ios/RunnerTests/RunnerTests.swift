import XCTest
import StoreKit
import StoreKitTest
@testable import Runner

final class RunnerTests: XCTestCase {
  // Every test uses its own journal; never touch a user's Keychain purchases.
  @MainActor
  private func makeStore(enabled: Bool,
      readRecords: @escaping () async -> ApplePurchaseStore.Records = ApplePurchaseStore.storeKitRecords,
      synchronize: @escaping () async throws -> Void = { try await AppStore.sync() },
      clock: @escaping () async -> Date? = ApplePurchaseStore.fetchAppleTime,
      acceptsCompanion: Bool = false, loadCompanion: () -> Data? = { nil },
      saveCompanion: @escaping (Data) -> Void = { _ in },
      loadPhone: @escaping () -> Data? = { nil }, savePhone: @escaping (Data) -> Void = { _ in },
      loadClock: () -> Data? = { nil }, saveClock: @escaping (Data) -> Void = { _ in },
      uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
      bootID: @escaping () -> String? = PurchaseClockAnchor.currentBootID,
      useTestingClock: Bool = true) -> ApplePurchaseStore {
    ApplePurchaseStore(enabled: enabled, readRecords: readRecords, synchronize: synchronize,
      clock: clock, acceptsCompanion: acceptsCompanion, loadCompanion: loadCompanion,
      saveCompanion: saveCompanion, loadPhone: loadPhone, savePhone: savePhone,
      loadClock: loadClock, saveClock: saveClock, uptime: uptime, bootID: bootID, useTestingClock: useTestingClock)
  }

  @MainActor
  private func waitForStoreKitRecord(_ id: String, revoked: Bool = false) async throws {
    // StoreKitTest actions return before the daemon necessarily publishes the
    // corresponding signed record. Wait for that evidence before asserting UI.
    for _ in 0..<60 {
      if case .verified(let transaction) = await Transaction.latest(for: id),
         (transaction.revocationDate != nil) == revoked { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("StoreKitTest did not publish the expected signed record")
    throw PurchaseFailure.unavailable
  }

  @MainActor
  func testFreeClaimCannotStartPaidPurchase() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    let store = makeStore(enabled: true)
    await store.refresh(loadProducts: true)
    XCTAssertEqual(store.snapshot["permanentFree"] as? Bool, false)
    let outcome = try await store.purchase(ApplePurchaseStore.permanentID, requireFree: true)
    XCTAssertEqual(outcome, "offerUnavailable")
    XCTAssertTrue(session.allTransactions().isEmpty)
    XCTAssertFalse(store.permanent)
  }

  @MainActor
  func testFreePermanentClaimRestoresWithoutTrialClock() async throws {
    let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "AI-Link", withExtension: "storekit"))
    var configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
    var products = try XCTUnwrap(configuration["products"] as? [[String: Any]])
    let index = try XCTUnwrap(products.firstIndex { $0["productID"] as? String == ApplePurchaseStore.permanentID })
    products[index]["displayPrice"] = "0"
    configuration["products"] = products
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("free-\(UUID().uuidString).storekit")
    try JSONSerialization.data(withJSONObject: configuration).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let session = try SKTestSession(contentsOf: file)
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    let store = makeStore(enabled: true)
    await store.refresh(loadProducts: true)
    XCTAssertEqual(store.snapshot["permanentFree"] as? Bool, true)
    XCTAssertFalse(store.permanent)
    let outcome = try await store.purchase(ApplePurchaseStore.permanentID, requireFree: true)
    XCTAssertEqual(outcome, "success")
    XCTAssertTrue(store.permanent)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    // The entitlement is the signed non-consumable transaction, not today's price.
    let restored = makeStore(enabled: true, clock: { nil })
    await restored.refresh()
    XCTAssertTrue(restored.permanent)
    XCTAssertTrue(restored.canUse)
  }

  @MainActor
  func testTrialBoundaryAndClockRollback() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    XCTAssertFalse(ApplePurchaseStore.trialValid(start: start, now: start.addingTimeInterval(-1)))
    XCTAssertTrue(ApplePurchaseStore.trialValid(start: start, now: start))
    XCTAssertTrue(ApplePurchaseStore.trialValid(start: start, now: start.addingTimeInterval(604799)))
    XCTAssertFalse(ApplePurchaseStore.trialValid(start: start, now: start.addingTimeInterval(604800)))
  }

  @MainActor
  func testVerifiedPurchaseRestoreRefundAndTrialHistory() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions() // Only this local StoreKit configuration's test records.
    defer { session.clearTransactions(); session.resetToDefaultState() }
    let store = makeStore(enabled: true)
    store.start()
    await store.refresh(loadProducts: true)
    XCTAssertFalse(store.canUse)
    XCTAssertEqual(store.products.count, 2)
    XCTAssertTrue(store.snapshot["trialAvailable"] as? Bool == true)
    let outcome1 = try await store.purchase(ApplePurchaseStore.trialID)
    XCTAssertEqual(outcome1, "success")
    XCTAssertTrue(store.canUse)
    XCTAssertTrue(store.hadTrial)
    XCTAssertFalse(store.permanent)
    let originalEnd = store.trialEnd
    let outcome2 = try await store.purchase(ApplePurchaseStore.trialID)
    XCTAssertEqual(outcome2, "alreadyClaimed")
    await store.refresh()
    XCTAssertEqual(store.trialEnd, originalEnd)
    // A new controller models a reinstall: only signed StoreKit history matters.
    let restored = makeStore(enabled: true)
    await restored.refresh()
    XCTAssertTrue(restored.canUse)
    XCTAssertEqual(restored.trialEnd, originalEnd)
    let outcome3 = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome3, "success")
    XCTAssertTrue(store.permanent)
    let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ApplePurchaseStore.permanentID })
    try session.refundTransaction(identifier: purchase.identifier)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID, revoked: true)
    await store.refresh()
    XCTAssertFalse(store.permanent)
    let trial = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ApplePurchaseStore.trialID })
    try session.refundTransaction(identifier: trial.identifier)
    try await waitForStoreKitRecord(ApplePurchaseStore.trialID, revoked: true)
    await store.refresh()
    XCTAssertFalse(store.canUse)
    XCTAssertTrue(store.hadTrial)
    let outcome4 = try await store.purchase(ApplePurchaseStore.trialID)
    XCTAssertEqual(outcome4, "alreadyClaimed")
  }

  @MainActor
  func testPendingApprovalDoesNotUnlock() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.askToBuyEnabled = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    let store = makeStore(enabled: true)
    store.start()
    await store.refresh(loadProducts: true)
    let outcome5 = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome5, "pending")
    XCTAssertFalse(store.canUse)
    let pending = try XCTUnwrap(session.allTransactions().first)
    try session.approveAskToBuyTransaction(identifier: pending.identifier)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    await store.refresh()
    XCTAssertTrue(store.permanent)
  }

  @MainActor
  func testVerifiedPurchaseSurvivesEmptyQueriesButRevocationRemovesAccess() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    var records = ApplePurchaseStore.Records()
    let store = makeStore(enabled: true, readRecords: { records })
    await store.refresh(loadProducts: true)
    let outcome = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome, "success")
    XCTAssertTrue(store.permanent, "The verified purchase return must deliver access immediately")
    await store.refresh()
    XCTAssertTrue(store.permanent, "An empty cache query must not erase a just-verified purchase")
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    let originalResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let originalPurchase = try XCTUnwrap(originalResult)
    let bought = try XCTUnwrap(session.allTransactions().first)
    try session.refundTransaction(identifier: bought.identifier)
    var revoked = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    // StoreKitTest's refund call returns before the daemon has necessarily
    // published its signed revocation. Wait for that evidence, not a timer alone.
    for _ in 0..<20 {
      if case .verified(let transaction) = revoked, transaction.revocationDate != nil { break }
      try await Task.sleep(nanoseconds: 50_000_000)
      revoked = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    }
    guard case .verified(let transaction) = revoked, transaction.revocationDate != nil else {
      return XCTFail("StoreKitTest did not provide the signed refund")
    }
    records.latest = [try XCTUnwrap(revoked)]
    await store.refresh()
    XCTAssertFalse(store.permanent)
    XCTAssertFalse(store.canUse)
    records = ApplePurchaseStore.Records()
    await store.refresh()
    XCTAssertFalse(store.permanent, "An older purchase callback must not resurrect a refund")
    XCTAssertTrue(store.receive(originalPurchase))
    XCTAssertFalse(store.permanent, "Replaying the original signed purchase must not erase its refund")
  }

  @MainActor
  @available(iOS 17.0, *)
  func testPurchaseArrivingDuringRefreshCannotBeOverwrittenByItsOlderSnapshot() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    _ = try await session.buyProduct(identifier: ApplePurchaseStore.permanentID)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    let purchaseResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let verified = try XCTUnwrap(purchaseResult)
    var suspended: CheckedContinuation<ApplePurchaseStore.Records, Never>?
    var queries = 0
    let store = makeStore(enabled: true, readRecords: {
      queries += 1
      if queries == 1 {
        return await withCheckedContinuation { suspended = $0 }
      }
      return ApplePurchaseStore.Records()
    })
    let refresh = Task { await store.refresh() }
    while suspended == nil { await Task.yield() }
    XCTAssertTrue(store.receive(verified))
    XCTAssertTrue(store.permanent)
    suspended?.resume(returning: ApplePurchaseStore.Records())
    await refresh.value
    XCTAssertTrue(store.permanent)
    XCTAssertGreaterThanOrEqual(queries, 2, "The invalidated read must run again")
    // Unverified callbacks are never sufficient to unlock another controller.
    guard case .verified(let transaction) = verified else { return XCTFail("Expected a local verified transaction") }
    let unverifiedStore = makeStore(enabled: true, readRecords: { ApplePurchaseStore.Records() })
    XCTAssertFalse(unverifiedStore.receive(.unverified(transaction, .invalidSignature)))
    XCTAssertFalse(unverifiedStore.canUse)
    XCTAssertEqual(unverifiedStore.errorCode, "verificationFailed")
  }

  @MainActor
  @available(iOS 17.0, *)
  func testColdControllerCanRecoverFromProductSpecificVerifiedQuery() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    _ = try await session.buyProduct(identifier: ApplePurchaseStore.permanentID)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    let latestResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let latest = try XCTUnwrap(latestResult)
    let records = ApplePurchaseStore.Records(latest: [latest])
    let store = makeStore(enabled: true, readRecords: { records }, synchronize: {})
    try await store.restore()
    XCTAssertTrue(store.permanent)
    XCTAssertTrue(store.canUse)
    let empty = makeStore(enabled: true, readRecords: { ApplePurchaseStore.Records() })
    await empty.refresh()
    XCTAssertFalse(empty.canUse, "A cold start cannot invent an entitlement from a local Boolean")
  }

  @MainActor
  func testPairedPhoneTrialSurvivesEmptyWatchStoreKitAndColdStart() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let start = now.addingTimeInterval(-3600)
    let state = CompanionEntitlement(sequence: 1, issuedAt: now,
      validUntil: start.addingTimeInterval(604800), permanent: false, permanentTransactionID: nil,
      trialActive: true, trialStart: start, trialTransactionID: "trial-1")
    let data = try JSONEncoder().encode(state)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var saved: Data?
    let watch = makeStore(enabled: true, readRecords: {
      XCTFail("The watch must not query StoreKit; only its paired phone verifies purchases")
      return .init()
    }, clock: { now },
      acceptsCompanion: true, loadCompanion: { nil }, saveCompanion: { saved = $0 })
    XCTAssertTrue(watch.receiveCompanion(payload))
    await watch.refreshCompanionClock()
    XCTAssertTrue(watch.canUse)
    XCTAssertFalse(watch.permanent)
    XCTAssertEqual(watch.trialEnd, start.addingTimeInterval(604800))
    await watch.refresh()
    XCTAssertTrue(watch.canUse, "Refresh must keep the paired phone's trial state")
    let cold = makeStore(enabled: true, readRecords: { .init() }, clock: { now },
      acceptsCompanion: true, loadCompanion: { saved }, saveCompanion: { _ in })
    await cold.refresh()
    XCTAssertTrue(cold.canUse)
    XCTAssertEqual(cold.trialEnd, watch.trialEnd, "Cold start must not restart the seven days")
    let expired = makeStore(enabled: true, readRecords: { .init() },
      clock: { start.addingTimeInterval(604800) }, acceptsCompanion: true,
      loadCompanion: { saved }, saveCompanion: { _ in })
    await expired.refresh()
    XCTAssertFalse(expired.canUse, "The original seven-day trial must expire")
  }

  @MainActor
  func testPairedTrialCannotExtendItsOriginalSevenDaysOrBypassTrustedClock() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let state = CompanionEntitlement(sequence: 1, issuedAt: now,
      validUntil: now, permanent: false, permanentTransactionID: nil,
      trialActive: true, trialStart: now.addingTimeInterval(-604800), trialTransactionID: "trial-1")
    let data = try JSONEncoder().encode(state)
    let expired = makeStore(enabled: true, readRecords: { .init() }, clock: { now },
      acceptsCompanion: true, loadCompanion: { data }, saveCompanion: { _ in })
    await expired.refresh()
    XCTAssertFalse(expired.canUse)
    XCTAssertTrue(expired.hadTrial)
    let noClock = makeStore(enabled: true, readRecords: { .init() }, clock: { nil },
      acceptsCompanion: true, loadCompanion: { data }, saveCompanion: { _ in })
    await noClock.refresh()
    XCTAssertFalse(noClock.canUse)
    XCTAssertEqual(noClock.errorCode, "clockUnavailable")
  }

  @MainActor
  func testPairedSnapshotRejectsFlagsMalformedUpdatesAndOlderRestores() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var state = CompanionEntitlement(sequence: 2, issuedAt: now,
      validUntil: nil, permanent: true, permanentTransactionID: "purchase-1",
      trialActive: false, trialStart: nil, trialTransactionID: nil)
    func payload(_ state: CompanionEntitlement) throws -> [String: Any] {
      try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
    let watch = makeStore(enabled: true, readRecords: { .init() }, clock: { now },
      acceptsCompanion: true, loadCompanion: { nil }, saveCompanion: { _ in })
    XCTAssertFalse(watch.receiveCompanion(["permanent": true, "canUse": true]))
    XCTAssertTrue(watch.receiveCompanion(try payload(state)))
    await watch.refreshCompanionClock()
    XCTAssertTrue(watch.permanent)
    let old = try payload(state)
    state = CompanionEntitlement(sequence: 3, issuedAt: now,
      validUntil: nil, permanent: false, permanentTransactionID: "purchase-1",
      trialActive: false, trialStart: nil, trialTransactionID: nil)
    XCTAssertTrue(watch.receiveCompanion(try payload(state)))
    XCTAssertFalse(watch.canUse)
    XCTAssertFalse(watch.receiveCompanion(old), "A delayed restore reply must not resurrect removed access")
    state.sourceBundleID = "other.app"
    XCTAssertFalse(watch.receiveCompanion(try payload(state)))
    let phone = makeStore(enabled: true, readRecords: { .init() }, acceptsCompanion: false)
    XCTAssertFalse(phone.receiveCompanion(old), "Watch messages must never grant iPhone purchases")
  }

  @MainActor
  @available(iOS 17.0, *)
  func testNativePhoneExportsVerifiedTrialAndRefundToWatch() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    _ = try await session.buyProduct(identifier: ApplePurchaseStore.trialID)
    try await waitForStoreKitRecord(ApplePurchaseStore.trialID)
    let trialResult = await Transaction.latest(for: ApplePurchaseStore.trialID)
    let trial = try XCTUnwrap(trialResult)
    guard case .verified(let transaction) = trial else { return XCTFail("Expected signed trial") }
    let now = transaction.originalPurchaseDate.addingTimeInterval(3600)
    var records = ApplePurchaseStore.Records(latest: [trial])
    let phone = makeStore(enabled: true, readRecords: { records }, clock: { now },
      acceptsCompanion: false)
    await phone.refresh()
    let phonePayload = await phone.companionSnapshot()
    let payload = try XCTUnwrap(phonePayload)
    let watch = makeStore(enabled: true, readRecords: { .init() }, clock: { now },
      acceptsCompanion: true, loadCompanion: { nil }, saveCompanion: { _ in })
    XCTAssertTrue(watch.receiveCompanion(payload))
    await watch.refresh()
    XCTAssertTrue(watch.canUse)
    XCTAssertEqual(watch.trialEnd, phone.trialEnd)
    try session.refundTransaction(identifier: try XCTUnwrap(session.allTransactions().first).identifier)
    var refunded = await Transaction.latest(for: ApplePurchaseStore.trialID)
    for _ in 0..<20 {
      if case .verified(let t) = refunded, t.revocationDate != nil { break }
      try await Task.sleep(nanoseconds: 50_000_000)
      refunded = await Transaction.latest(for: ApplePurchaseStore.trialID)
    }
    guard case .verified(let t) = refunded, t.revocationDate != nil else { return XCTFail("Expected refund") }
    records = .init(latest: [try XCTUnwrap(refunded)])
    await phone.refresh()
    let removedPayload = await phone.companionSnapshot()
    let removed = try XCTUnwrap(removedPayload)
    XCTAssertTrue(watch.receiveCompanion(removed))
    XCTAssertFalse(watch.canUse)
    XCTAssertTrue(watch.hadTrial)
    XCTAssertFalse(watch.receiveCompanion(payload))
    XCTAssertFalse(watch.receive(trial), "Even a valid watch StoreKit record must not override the phone's revoked state")
    XCTAssertFalse(watch.canUse)
  }
  @MainActor
  @available(iOS 17.0, *)
  func testVerifiedPhonePurchasesSurviveRepeatedColdStartsAndEmptyStoreKit() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    for id in [ApplePurchaseStore.trialID, ApplePurchaseStore.permanentID] {
      _ = try await session.buyProduct(identifier: id)
      try await waitForStoreKitRecord(id)
      let latest = await Transaction.latest(for: id)
      let result = try XCTUnwrap(latest)
      let account = "regression-\(UUID().uuidString)"
      defer { PurchaseKeychain.remove(account) }
      var journal: Data? { PurchaseKeychain.load(account) }
      var ticks = 100.0
      let serverNow = Date()
      let hot = makeStore(enabled: true, readRecords: { .init() }, clock: { serverNow },
        savePhone: { PurchaseKeychain.save($0, account: account) }, uptime: { ticks }, bootID: { "boot-a" },
        useTestingClock: false)
      XCTAssertTrue(hot.receive(result))
      await hot.refresh()
      XCTAssertTrue(hot.canUse)
      XCTAssertNotNil(journal, "Verified delivery must persist before transaction.finish")
      let originalEnd = hot.trialEnd
      for _ in 0..<3 {
        ticks += 10
        let cold = makeStore(enabled: true, readRecords: { .init() }, clock: { nil },
          loadPhone: { journal }, savePhone: { PurchaseKeychain.save($0, account: account) },
          uptime: { ticks }, bootID: { "boot-a" }, useTestingClock: false)
        XCTAssertTrue(cold.canUse, "Cold start must deliver cached verified ownership before a query")
        await cold.refresh()
        XCTAssertTrue(cold.canUse, "An empty StoreKit query cannot revoke a paid transaction")
        XCTAssertEqual(cold.permanent, id == ApplePurchaseStore.permanentID)
        XCTAssertEqual(cold.trialEnd, originalEnd)
      }
      if id == ApplePurchaseStore.trialID {
        ticks += ApplePurchaseStore.trialDuration
        let expired = makeStore(enabled: true, readRecords: { .init() }, clock: { nil },
          loadPhone: { journal }, uptime: { ticks }, bootID: { "boot-a" }, useTestingClock: false)
        await expired.refresh()
        XCTAssertFalse(expired.canUse)
        XCTAssertTrue(expired.hadTrial)
      }
    }
  }

  @MainActor
  @available(iOS 17.0, *)
  func testColdPhoneUsesVerifiedHistoryAndPersistsRefundAgainstOldCallbacks() async throws {
    let session = try SKTestSession(configurationFileNamed: "AI-Link")
    session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
    defer { session.clearTransactions(); session.resetToDefaultState() }
    _ = try await session.buyProduct(identifier: ApplePurchaseStore.permanentID)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID)
    let boughtResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let bought = try XCTUnwrap(boughtResult)
    var journal: Data?
    var records = ApplePurchaseStore.Records(history: [bought])
    let store = makeStore(enabled: true, readRecords: { records }, savePhone: { journal = $0 })
    await store.refresh()
    XCTAssertTrue(store.permanent, "Verified history is ownership evidence even if current/latest are empty")
    records = .init()
    await store.refresh()
    XCTAssertTrue(store.permanent, "An empty later query must preserve previously verified history")
    try session.refundTransaction(identifier: try XCTUnwrap(session.allTransactions().first).identifier)
    try await waitForStoreKitRecord(ApplePurchaseStore.permanentID, revoked: true)
    let refundResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let refund = try XCTUnwrap(refundResult)
    records = .init(history: [refund])
    await store.refresh()
    XCTAssertFalse(store.permanent)
    XCTAssertTrue(store.receive(bought))
    XCTAssertFalse(store.permanent, "An old callback cannot override a refund read from history")
    let cold = makeStore(enabled: true, readRecords: { .init(history: [bought]) },
      loadPhone: { journal }, savePhone: { journal = $0 })
    await cold.refresh()
    XCTAssertFalse(cold.canUse, "Old StoreKit history cannot resurrect a persisted signed refund")
    XCTAssertTrue(cold.receive(bought))
    XCTAssertFalse(cold.permanent)
  }

  @MainActor
  func testWatchTrialUsesLivePhoneTimeWithoutWatchInternetAndKeepsExpiryOnColdStart() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000.123)
    let start = now.addingTimeInterval(-3600)
    let state = CompanionEntitlement(sequence: 1, issuedAt: now,
      validUntil: start.addingTimeInterval(604800), permanent: false, permanentTransactionID: nil,
      trialActive: true, trialStart: start, trialTransactionID: "trial-1")
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    var saved: Data?
    var clockJournal: Data?
    var ticks = 100.0
    var clockCalls = 0
    let watch = makeStore(enabled: true, readRecords: { XCTFail("Watch must not query StoreKit"); return .init() },
      clock: { clockCalls += 1; return nil }, acceptsCompanion: true,
      saveCompanion: { saved = $0 }, saveClock: { clockJournal = $0 },
      uptime: { ticks }, bootID: { "watch-boot-a" })
    XCTAssertTrue(watch.receiveCompanion(payload, livePhoneTime: true))
    XCTAssertTrue(watch.canUse, "Phone-authorized trial must work immediately with no watch HTTPS")
    await watch.refresh()
    XCTAssertEqual(clockCalls, 0)
    ticks += 100
    let cold = makeStore(enabled: true, readRecords: { .init() }, clock: { clockCalls += 1; return nil },
      acceptsCompanion: true, loadCompanion: { saved }, loadClock: { clockJournal },
      uptime: { ticks }, bootID: { "watch-boot-a" })
    XCTAssertTrue(cold.canUse)
    await cold.refresh()
    XCTAssertEqual(cold.trialEnd, start.addingTimeInterval(604800))
    XCTAssertEqual(clockCalls, 0)
    ticks += 604800
    XCTAssertFalse(cold.canUse, "A persisted phone clock must continue advancing through app restarts")
    let rebooted = makeStore(enabled: true, readRecords: { .init() }, clock: { nil },
      acceptsCompanion: true, loadCompanion: { saved }, loadClock: { clockJournal },
      uptime: { 10 }, bootID: { "watch-boot-b" })
    await rebooted.refresh()
    XCTAssertFalse(rebooted.canUse, "Replaying saved applicationContext after reboot must not restart a trial")
  }

  @MainActor
  func testMissingOrMalformedPhoneJournalCannotUnlock() async throws {
    for data in [Data(), Data("{\"permanent\":true}".utf8)] {
      let store = makeStore(enabled: true, readRecords: { .init() }, loadPhone: { data })
      await store.refresh()
      XCTAssertFalse(store.canUse)
    }
    XCTAssertNotNil(PurchaseClockAnchor.currentBootID(), "This simulator must expose a stable boot identity for cold-start clock tests")
    let anchor = PurchaseClockAnchor(date: Date(), uptime: 100, bootID: "boot-a")
    XCTAssertNotNil(anchor.now(uptime: 120, bootID: "boot-a"))
    XCTAssertNil(anchor.now(uptime: 10, bootID: "boot-b"))
    XCTAssertNil(anchor.now(uptime: 90, bootID: "boot-a"))
  }

}
