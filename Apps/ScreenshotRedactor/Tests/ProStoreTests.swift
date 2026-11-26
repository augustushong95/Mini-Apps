import Foundation
import MenuBarKit
import StoreKitTest
import Testing
@testable import ScreenshotRedactor

/// The Pro purchase (MenuBarKit's `ProStore`), against Apple's local StoreKit
/// test environment (`ScreenshotRedactor.storekit`): no real money, no
/// account, and no network entitlement needed.
@Suite(.serialized)
struct ProStoreTests {
    private final class BundleMarker {}

    private func eventually(_ pro: ProStore, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<50 {
            await pro.refresh()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    @Test func owningProUnlocksItAndARefundTakesItAway() async throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "ScreenshotRedactor", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let defaults = Fixtures.defaults()
        let pro = ProStore(productID: AppModel.proProductID, debugDefaults: defaults)

        await pro.loadProduct()
        #expect(pro.product?.id == AppModel.proProductID)
        #expect(pro.priceText.contains("9.99"))

        await pro.refresh()
        #expect(!pro.isPro, "Free until bought")

        let transaction = try await session.buyProduct(identifier: AppModel.proProductID)
        #expect(await eventually(pro) { pro.isPro }, "Unlocked by the purchase")

        // Pro lifts the daily limit.
        let allowance = DailyAllowance(defaults: defaults)
        allowance.isUnlimited = pro.isPro
        for _ in 0..<(DailyAllowance.freePerDay + 3) { allowance.recordExport(Fixtures.document()) }
        #expect(allowance.canExport(Fixtures.document()))

        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(await eventually(pro) { !pro.isPro }, "Locked again after a refund")
    }
}
