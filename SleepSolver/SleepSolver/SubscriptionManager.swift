//
//  SubscriptionManager.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import Foundation
import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // Product IDs
    static let monthlyProductID = "name.cadechristensen.SleepSolver.monthly"
    static let yearlyProductID = "name.cadechristensen.SleepSolver.yearly"
    
    // Published properties for UI binding
    @Published var isLoading = false
    @Published var isPremium = false
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var subscriptionStatus: SubscriptionStatus?
    @Published var errorMessage: String?
    
    // Offline fallback properties
    private let offlineGracePeriodHours: TimeInterval = 48 * 60 * 60 // 48 hours
    private let lastSuccessfulCheckKey = "lastSuccessfulPremiumCheck"
    private let cachedPremiumStatusKey = "cachedPremiumStatus"
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        print("🔧 SubscriptionManager: Initializing...")
        
        // Start listening for transaction updates
        startTransactionListener()
        
        // Load products and check subscription status
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        print("🔧 SubscriptionManager: Loading products...")
        isLoading = true
        errorMessage = nil
        
        do {
            let storeProducts = try await Product.products(for: [
                Self.monthlyProductID,
                Self.yearlyProductID
            ])
            
            print("🔧 SubscriptionManager: Found \(storeProducts.count) products")
            for product in storeProducts {
                print("   - Product ID: \(product.id)")
                print("   - Display Name: \(product.displayName)")
                print("   - Price: \(product.displayPrice)")
                
                // Check for introductory offers
                if let subscriptionInfo = product.subscription {
                    if let introOffer = subscriptionInfo.introductoryOffer {
                        print("   - Intro Offer: \(introOffer.period.value) \(introOffer.period.unit) at \(introOffer.displayPrice)")
                        print("   - Intro Offer Type: \(introOffer.paymentMode)")
                    } else {
                        print("   - No introductory offer configured")
                    }
                } else {
                    print("   - Not a subscription product")
                }
            }
            
            products = storeProducts.sorted { product1, product2 in
                // Sort by price (monthly first, then yearly)
                product1.price < product2.price
            }
            
        } catch {
            errorMessage = "Failed to load subscription options: \(error.localizedDescription)"
            print("❌ SubscriptionManager: Failed to load products: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Subscription Status Checking
    
    func updateSubscriptionStatus() async {
        print("🔧 SubscriptionManager: Updating subscription status...")
        
        do {
            // Primary method: Query StoreKit's current entitlements
            let entitlements = try await checkCurrentEntitlements()
            
            if let activeSubscription = entitlements {
                print("✅ SubscriptionManager: Found active subscription")
                print("   - Product ID: \(activeSubscription.productID)")
                print("   - Purchase Date: \(activeSubscription.purchaseDate)")
                print("   - Expiration Date: \(activeSubscription.expirationDate?.description ?? "nil")")
                print("   - Is in trial: \(activeSubscription.isInIntroOfferPeriod)")
                print("   - Renewal State: \(activeSubscription.renewalState)")
                
                isPremium = true
                subscriptionStatus = activeSubscription
                purchasedProductIDs.insert(activeSubscription.productID)
                
                // Cache successful check for offline fallback
                cacheSuccessfulPremiumCheck(isPremium: true)
                
            } else {
                print("❌ SubscriptionManager: No active subscription found")
                isPremium = false
                subscriptionStatus = nil
                purchasedProductIDs.removeAll()
                
                // Cache successful check for offline fallback
                cacheSuccessfulPremiumCheck(isPremium: false)
            }
            
            errorMessage = nil
            print("🔧 SubscriptionManager: Final isPremium status: \(isPremium)")
            
        } catch {
            print("❌ SubscriptionManager: Failed to check subscription status: \(error)")
            
            // Fallback to cached status if within grace period
            if let cachedStatus = getCachedPremiumStatus() {
                isPremium = cachedStatus
                print("🔄 SubscriptionManager: Using cached premium status: \(cachedStatus)")
                
                if let lastCheck = UserDefaults.standard.object(forKey: lastSuccessfulCheckKey) as? Date {
                    let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
                    print("   - Cache age: \(Int(timeSinceLastCheck / 3600)) hours")
                }
            } else {
                print("❌ SubscriptionManager: No valid cache available")
                // No cache or expired - default to non-premium
                isPremium = false
                subscriptionStatus = nil
                purchasedProductIDs.removeAll()
            }
            
            errorMessage = "Unable to verify subscription status"
        }
    }
    
    private func checkCurrentEntitlements() async throws -> SubscriptionStatus? {
        print("🔧 SubscriptionManager: Checking current entitlements...")
        
        var entitlementCount = 0
        
        // Check all current entitlements
        for await result in Transaction.currentEntitlements {
            entitlementCount += 1
            
            do {
                let transaction = try checkVerified(result)
                
                print("🔧 SubscriptionManager: Found entitlement #\(entitlementCount)")
                print("   - Product ID: \(transaction.productID)")
                print("   - Purchase Date: \(transaction.purchaseDate)")
                print("   - Expiration Date: \(transaction.expirationDate?.description ?? "nil")")
                print("   - Transaction ID: \(transaction.id)")
                print("   - Is subscription product: \(transaction.productID == Self.monthlyProductID || transaction.productID == Self.yearlyProductID)")
                
                // Check if this is one of our subscription products
                if transaction.productID == Self.monthlyProductID || transaction.productID == Self.yearlyProductID {
                    
                    // Additional validation: check if subscription is still active
                    if let expirationDate = transaction.expirationDate {
                        let isExpired = expirationDate < Date()
                        print("   - Expiration check: \(expirationDate) vs \(Date())")
                        print("   - Is expired: \(isExpired)")
                        
                        if isExpired {
                            print("   - Skipping expired subscription")
                            continue
                        }
                    } else {
                        print("   - No expiration date (lifetime or active subscription)")
                    }
                    
                    // Check offer details
                    if let offer = transaction.offer {
                        print("   - Offer type: \(offer.type)")
                        print("   - Offer ID: \(offer.id ?? "nil")")
                    } else {
                        print("   - No offer (regular pricing)")
                    }
                    
                    // Create subscription status
                    let status = SubscriptionStatus(
                        productID: transaction.productID,
                        purchaseDate: transaction.purchaseDate,
                        expirationDate: transaction.expirationDate,
                        isInIntroOfferPeriod: transaction.offer != nil,
                        renewalState: .subscribed // Simplified for now - active transaction means subscribed
                    )
                    
                    print("✅ SubscriptionManager: Created subscription status for \(transaction.productID)")
                    return status
                }
            } catch {
                print("❌ SubscriptionManager: Failed to verify transaction: \(error)")
            }
        }
        
        print("🔧 SubscriptionManager: Checked \(entitlementCount) total entitlements, none matched our products")
        return nil
    }
    
    // MARK: - Purchase Flow
    
    func purchase(_ product: Product) async -> PurchaseResult {
        print("🔧 SubscriptionManager: Starting purchase for \(product.id)")
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                print("✅ SubscriptionManager: Purchase successful")
                let transaction = try checkVerified(verification)
                print("   - Transaction ID: \(transaction.id)")
                print("   - Product ID: \(transaction.productID)")
                
                // Update subscription status
                await updateSubscriptionStatus()
                
                // Finish the transaction
                await transaction.finish()
                print("   - Transaction finished")
                
                isLoading = false
                return .success
                
            case .userCancelled:
                print("🔧 SubscriptionManager: Purchase cancelled by user")
                isLoading = false
                return .userCancelled
                
            case .pending:
                print("🔧 SubscriptionManager: Purchase pending")
                isLoading = false
                return .pending
                
            @unknown default:
                print("❌ SubscriptionManager: Unknown purchase result")
                isLoading = false
                return .unknown
            }
            
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("❌ SubscriptionManager: Purchase failed: \(error)")
            isLoading = false
            return .failed(error)
        }
    }
    
    func restorePurchases() async {
        print("🔧 SubscriptionManager: Restoring purchases...")
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            print("✅ SubscriptionManager: AppStore sync completed")
            await updateSubscriptionStatus()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("❌ SubscriptionManager: Restore failed: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Transaction Verification
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            print("❌ SubscriptionManager: Transaction verification failed - unverified")
            throw SubscriptionError.unverifiedTransaction
        case .verified(let safe):
            print("✅ SubscriptionManager: Transaction verified successfully")
            return safe
        }
    }
    
    // MARK: - Transaction Listener
    
    private func startTransactionListener() {
        print("🔧 SubscriptionManager: Starting transaction listener...")
        updateListenerTask = Task.detached {
            for await result in Transaction.updates {
                print("🔧 SubscriptionManager: Received transaction update")
                do {
                    let transaction = try await self.checkVerified(result)
                    print("   - Updated transaction for product: \(transaction.productID)")
                    
                    // Update subscription status on main actor
                    await self.updateSubscriptionStatus()
                    
                    // Finish the transaction
                    await transaction.finish()
                    print("   - Update transaction finished")
                } catch {
                    print("❌ SubscriptionManager: Transaction update verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Offline Caching
    
    private func cacheSuccessfulPremiumCheck(isPremium: Bool) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(Date(), forKey: lastSuccessfulCheckKey)
        userDefaults.set(isPremium, forKey: cachedPremiumStatusKey)
        
        print("🔧 SubscriptionManager: Cached premium status: \(isPremium)")
    }
    
    private func getCachedPremiumStatus() -> Bool? {
        let userDefaults = UserDefaults.standard
        
        guard let lastCheck = userDefaults.object(forKey: lastSuccessfulCheckKey) as? Date else {
            print("🔧 SubscriptionManager: No cached check date found")
            return nil
        }
        
        // Check if we're within the grace period
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
        guard timeSinceLastCheck <= offlineGracePeriodHours else {
            print("🔧 SubscriptionManager: Cache expired (age: \(Int(timeSinceLastCheck / 3600)) hours)")
            return nil // Cache expired
        }
        
        let cachedStatus = userDefaults.bool(forKey: cachedPremiumStatusKey)
        print("🔧 SubscriptionManager: Found valid cached status: \(cachedStatus) (age: \(Int(timeSinceLastCheck / 3600)) hours)")
        return cachedStatus
    }
    
    // MARK: - Convenience Methods
    
    // MARK: - Trial Eligibility
    
    func checkTrialEligibility(for productID: String) async -> Bool {
        print("🔧 SubscriptionManager: Checking trial eligibility for \(productID)")
        
        // First, check if the product actually has an introductory offer configured
        guard let product = products.first(where: { $0.id == productID }),
              let subscriptionInfo = product.subscription,
              let introOffer = subscriptionInfo.introductoryOffer else {
            print("🔧 SubscriptionManager: Product \(productID) has no introductory offer configured")
            return false // No intro offer available for this product
        }
        
        print("🔧 SubscriptionManager: Product \(productID) has intro offer: \(introOffer.period.value) \(introOffer.period.unit) at \(introOffer.displayPrice)")
        
        for await transaction in Transaction.all {
            guard case .verified(let verifiedTransaction) = transaction else {
                continue
            }
            
            // Check if user has used trial for any product in this subscription group
            if (verifiedTransaction.productID == Self.monthlyProductID || 
                verifiedTransaction.productID == Self.yearlyProductID) &&
               verifiedTransaction.offer?.type == .introductory {
                print("🔧 SubscriptionManager: Found previous trial usage - not eligible")
                return false
            }
        }
        
        print("🔧 SubscriptionManager: User is eligible for trial")
        return true
    }
    
    // MARK: - Debug Methods
    
    func debugSubscriptionState() {
        print("\n=== SUBSCRIPTION DEBUG INFO ===")
        print("isPremium: \(isPremium)")
        print("subscriptionStatus: \(subscriptionStatus?.productID ?? "nil")")
        print("purchasedProductIDs: \(purchasedProductIDs)")
        print("products loaded: \(products.count)")
        print("isLoading: \(isLoading)")
        print("errorMessage: \(errorMessage ?? "nil")")
        
        if let lastCheck = UserDefaults.standard.object(forKey: lastSuccessfulCheckKey) as? Date {
            let age = Date().timeIntervalSince(lastCheck)
            print("Last successful check: \(lastCheck) (\(Int(age / 3600)) hours ago)")
        } else {
            print("Last successful check: never")
        }
        
        let cachedPremium = UserDefaults.standard.bool(forKey: cachedPremiumStatusKey)
        print("Cached premium status: \(cachedPremium)")
        print("===============================\n")
    }
    
    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }
    
    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductID }
    }
    
    var isInFreeTrial: Bool {
        subscriptionStatus?.isInIntroOfferPeriod == true
    }
    
    var trialDaysRemaining: Int? {
        guard let status = subscriptionStatus,
              status.isInIntroOfferPeriod,
              let expirationDate = status.expirationDate else {
            return nil
        }
        
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
        return max(0, daysRemaining ?? 0)
    }
    
    func hasIntroductoryOffer(for productID: String) -> Bool {
        guard let product = products.first(where: { $0.id == productID }),
              let subscriptionInfo = product.subscription,
              subscriptionInfo.introductoryOffer != nil else {
            return false
        }
        return true
    }
}

// MARK: - Supporting Types

struct SubscriptionStatus {
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let isInIntroOfferPeriod: Bool
    let renewalState: RenewalState
    
    enum RenewalState {
        case subscribed
        case expired
        case inBillingRetryPeriod
        case revoked
    }
    
    var isActive: Bool {
        switch renewalState {
        case .subscribed, .inBillingRetryPeriod:
            return true
        case .expired, .revoked:
            return false
        }
    }
}

enum PurchaseResult {
    case success
    case userCancelled
    case pending
    case failed(Error)
    case unknown
}

enum SubscriptionError: LocalizedError {
    case unverifiedTransaction
    case noActiveSubscription
    
    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return "Transaction could not be verified"
        case .noActiveSubscription:
            return "No active subscription found"
        }
    }
}
