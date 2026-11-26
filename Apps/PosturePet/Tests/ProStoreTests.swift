import Foundation
import StoreKitTest
import Testing
@testable import PosturePet

/// The Pro purchase, against Apple's local StoreKit test environment
/// (`PosturePet.storekit`): no real money, no App Store account.
@Suite(.serialized)
struct ProStoreTests {
    private final class BundleMarker {}

    /// StoreKit's test environment can take a moment to list a new or
    /// refunded transaction; re-check (as the app does on every update) for
    /// up to five seconds.
    private func eventually(_ pro: ProStore, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<50 {
            await pro.refresh()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    /// The purchase sheet itself needs a window, which tests don't have, so
    /// the purchase is made through the StoreKit test session (as if bought
    /// on another Mac with the same account). What's tested is what the app
    /// relies on: owning the product unlocks Pro, and losing it locks it.
    @Test func owningProUnlocksItAndARefundTakesItAway() async throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "PosturePet", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let suite = "PosturePetProTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let pro = ProStore(debugDefaults: UserDefaults(suiteName: suite)!)

        await pro.loadProduct()
        #expect(pro.product?.id == ProStore.productID)
        #expect(pro.priceText.contains("4.99"))

        await pro.refresh()
        #expect(!pro.isPro, "Free until bought")

        let transaction = try await session.buyProduct(identifier: ProStore.productID)
        await pro.refresh()
        #expect(await eventually(pro) { pro.isPro }, "Unlocked by the purchase")

        try session.refundTransaction(identifier: UInt(transaction.id))
        await pro.refresh()
        #expect(await eventually(pro) { !pro.isPro }, "Locked again after a refund")
        // And it stays locked once StoreKit's own update has been handled.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(!pro.isPro)

        session.clearTransactions()
        await pro.refresh()
        #expect(!pro.isPro, "Gone once the transaction is")
    }
}
