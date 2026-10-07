import XCTest
import StoreKit
import StoreKitTest
@testable import Runner

final class RunnerTests: XCTestCase {
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
    let store = ApplePurchaseStore(enabled: true)
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
    let restored = ApplePurchaseStore(enabled: true)
    await restored.refresh()
    XCTAssertTrue(restored.canUse)
    XCTAssertEqual(restored.trialEnd, originalEnd)
    let outcome3 = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome3, "success")
    XCTAssertTrue(store.permanent)
    let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ApplePurchaseStore.permanentID })
    try session.refundTransaction(identifier: purchase.identifier)
    await store.refresh()
    XCTAssertFalse(store.permanent)
    let trial = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ApplePurchaseStore.trialID })
    try session.refundTransaction(identifier: trial.identifier)
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
    let store = ApplePurchaseStore(enabled: true)
    store.start()
    await store.refresh(loadProducts: true)
    let outcome5 = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome5, "pending")
    XCTAssertFalse(store.canUse)
    let pending = try XCTUnwrap(session.allTransactions().first)
    try session.approveAskToBuyTransaction(identifier: pending.identifier)
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
    let store = ApplePurchaseStore(enabled: true, readRecords: { records })
    await store.refresh(loadProducts: true)
    let outcome = try await store.purchase(ApplePurchaseStore.permanentID)
    XCTAssertEqual(outcome, "success")
    XCTAssertTrue(store.permanent, "The verified purchase return must deliver access immediately")
    await store.refresh()
    XCTAssertTrue(store.permanent, "An empty cache query must not erase a just-verified purchase")
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
    let purchaseResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let verified = try XCTUnwrap(purchaseResult)
    var suspended: CheckedContinuation<ApplePurchaseStore.Records, Never>?
    var queries = 0
    let store = ApplePurchaseStore(enabled: true, readRecords: {
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
    let unverifiedStore = ApplePurchaseStore(enabled: true, readRecords: { ApplePurchaseStore.Records() })
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
    let latestResult = await Transaction.latest(for: ApplePurchaseStore.permanentID)
    let latest = try XCTUnwrap(latestResult)
    let records = ApplePurchaseStore.Records(latest: [latest])
    let store = ApplePurchaseStore(enabled: true, readRecords: { records }, synchronize: {})
    try await store.restore()
    XCTAssertTrue(store.permanent)
    XCTAssertTrue(store.canUse)
    let empty = ApplePurchaseStore(enabled: true, readRecords: { ApplePurchaseStore.Records() })
    await empty.refresh()
    XCTAssertFalse(empty.canUse, "A cold start cannot invent an entitlement from a local Boolean")
  }
}
