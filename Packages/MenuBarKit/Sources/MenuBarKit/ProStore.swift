import AppKit
import Foundation
import Observation
import OSLog
import StoreKit

/// An app's one-time "Pro" purchase (StoreKit 2, non-consumable).
///
/// Ownership comes from `Transaction.currentEntitlements`, which StoreKit
/// caches on the Mac, so Pro keeps working offline. Refunds and Family
/// Sharing changes arrive through `Transaction.updates`. StoreKit runs in
/// system processes, so the app itself needs no network entitlement.
@MainActor
@Observable
public final class ProStore {
    /// Must match the product in App Store Connect and the app's `.storekit` file.
    public let productID: String

    public private(set) var isPro = false
    public private(set) var product: Product?
    public private(set) var isPurchasing = false
    public private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    /// Refreshes can overlap (a StoreKit update arrives while one is running);
    /// only the most recently started one may apply its result.
    @ObservationIgnored private var refreshGeneration = 0

    /// - Parameters:
    ///   - productID: the non-consumable's product identifier.
    ///   - debugDefaults: where debug builds keep the "pretend Pro" switch;
    ///     tests pass their own so they never see a developer's setting.
    public init(productID: String, debugDefaults: UserDefaults = .standard) {
        self.productID = productID
        #if DEBUG
        self.debugDefaults = debugDefaults
        debugPro = debugDefaults.bool(forKey: "DebugPro")
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProduct()
        }
    }

    public var priceText: String {
        product?.displayPrice ?? "—"
    }

    public func loadProduct() async {
        do {
            product = try await Product.products(for: [productID]).first
        } catch {
            Logger.menuBarKit.error("Couldn't load products: \(error)")
        }
    }

    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        #if DEBUG
        owned = owned || debugPro
        #endif
        // A newer refresh started meanwhile: its answer is fresher than ours.
        guard generation == refreshGeneration else { return }
        isPro = owned
    }

    public func purchase() async {
        message = nil
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            message = "The App Store isn't reachable right now. Try again in a moment."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchaseResult(for: product) {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                } else {
                    message = "The purchase couldn't be verified."
                }
                await refresh()
            case .pending:
                message = "Waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Attaches the App Store confirmation to our window where the system
    /// supports it: a menu bar app has no main window for it to find.
    private func purchaseResult(for product: Product) async throws -> Product.PurchaseResult {
        if #available(macOS 15.2, *), let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            return try await product.purchase(confirmIn: window)
        }
        return try await product.purchase()
    }

    public func restore() async {
        message = nil
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
        }
        await refresh()
        if !isPro, message == nil {
            message = "No previous purchase found for this Apple Account."
        }
    }

    #if DEBUG
    @ObservationIgnored private let debugDefaults: UserDefaults
    @ObservationIgnored private var debugPro: Bool

    public func debugTogglePro() {
        debugPro.toggle()
        debugDefaults.set(debugPro, forKey: "DebugPro")
        Task { await refresh() }
    }
    #endif
}
