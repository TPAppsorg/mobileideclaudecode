import Foundation
import StoreKit
import Combine

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    /// True после первой проверки Transaction.currentEntitlements, чтобы не показывать баннер подписки премиум-юзеру до загрузки.
    @Published private(set) var hasCheckedPurchases = false
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    /// Product IDs must match App Store Connect and Subscriptions.storekit
    static let monthlyProductID = "uladluch.ClaudeCodeMobile.premium.monthly"
    static let yearlyProductID = "uladluch.ClaudeCodeMobile.premium.yearly"
    private let productIDs = [monthlyProductID, yearlyProductID]
    
    
    static let shared = StoreManager()
    
    private var updates: Task<Void, Never>? = nil

    init() {
        updates = Task.detached {
            for await result in Transaction.updates {
                await self.handleUpdate(result: result)
            }
        }
        
        Task {
            await fetchProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updates?.cancel()
    }

    func fetchProducts() async {
        print("🛒 StoreManager: Fetching ids: \(productIDs)")
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedProducts = try await Product.products(for: productIDs)
            print("🛒 StoreManager: Fetched \(fetchedProducts.count) results.")
            
            for p in fetchedProducts {
                print("🛒 StoreManager: Found product: \(p.id) - \(p.displayName)")
            }

            if fetchedProducts.isEmpty {
                #if targetEnvironment(simulator)
                print("🛒 StoreManager: WARNING - No products. Use Run on Simulator; check Scheme → Run → Options → StoreKit Configuration = Subscriptions.storekit.")
                #else
                print("🛒 StoreManager: WARNING - On device StoreKit uses App Store. Use Simulator for .storekit, or create products in App Store Connect for device.")
                #endif
                errorMessage = "No products found."
            }
            
            self.products = fetchedProducts.sorted { productIDs.firstIndex(of: $0.id) ?? 0 < productIDs.firstIndex(of: $1.id) ?? 0 }
            isLoading = false
        } catch {
            print("🛒 StoreManager: ERROR: \(error)")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return transaction
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }
    
    func updatePurchasedProducts() async {
        var newIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                newIDs.insert(transaction.productID)
            }
        }
        purchasedProductIDs = newIDs
        hasCheckedPurchases = true
    }

    /// Call to restore previous purchases (e.g. Restore button).
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("🛒 StoreManager: AppStore.sync() failed: \(error)")
        }
        await updatePurchasedProducts()
    }
    
    private func handleUpdate(result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await updatePurchasedProducts()
            await transaction.finish()
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
