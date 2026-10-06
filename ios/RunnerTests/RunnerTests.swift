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
}
