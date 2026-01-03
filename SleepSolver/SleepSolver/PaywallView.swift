//
//  PaywallView.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    @State private var selectedProductID: String = SubscriptionManager.yearlyProductID
    @State private var showingPurchaseConfirmation = false
    @State private var trialEligibility: [String: Bool] = [:]
    
    let feature: PremiumFeature
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Section
                    VStack(spacing: 12) {
                        // Premium Icon
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 6) {
                            Text("Unlock Premium")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(feature.unlockMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 16)
                    
                    // Feature Benefits
                    VStack(spacing: 12) {
                        ForEach(PremiumFeature.allBenefits, id: \.title) { benefit in
                            FeatureBenefitRow(
                                icon: benefit.icon,
                                title: benefit.title,
                                description: benefit.description,
                                isHighlighted: benefit.title == feature.primaryBenefit
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Subscription Options
                    VStack(spacing: 10) {
                        Text("Choose Your Plan")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if subscriptionManager.products.isEmpty {
                            if subscriptionManager.isLoading {
                                ProgressView("Loading plans...")
                                    .frame(height: 120)
                            } else {
                                Text("Unable to load subscription plans")
                                    .foregroundColor(.secondary)
                                    .frame(height: 120)
                            }
                        } else {
                            VStack(spacing: 6) {
                                ForEach(subscriptionManager.products) { product in
                                    SubscriptionOptionCard(
                                        product: product,
                                        isSelected: selectedProductID == product.id,
                                        onSelect: { selectedProductID = product.id }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 8)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // Bottom Action Section
                VStack(spacing: 12) {
                    // Primary CTA Button
                    Button(action: {
                        Task {
                            await handlePurchase()
                        }
                    }) {
                        HStack {
                            if subscriptionManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text(primaryButtonText)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(subscriptionManager.isLoading || selectedProduct == nil)
                    
                    // Secondary Actions
                    HStack(spacing: 8) {
                        Button("Restore Purchases") {
                            Task {
                                await subscriptionManager.restorePurchases()
                            }
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Button("Terms") {
                            if let url = URL(string: AppConfiguration.termsOfServiceURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                        
                        Text("•")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Button("Privacy") {
                            if let url = URL(string: AppConfiguration.privacyPolicyURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                    }
                    
                    // Subscription Details
                    if let product = selectedProduct {
                        Text(subscriptionDetailsText(for: product))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
            }
        }
        .alert("Purchase Successful!", isPresented: $showingPurchaseConfirmation) {
            Button("Continue") {
                dismiss()
            }
        } message: {
            Text("Welcome to SleepSolver Premium! You now have access to all premium features.")
        }
        .onAppear {
            // Pre-select the yearly option for better value
            if !subscriptionManager.products.isEmpty {
                selectedProductID = subscriptionManager.yearlyProduct?.id ?? subscriptionManager.products.first?.id ?? ""
            }
            
            // Check trial eligibility for all products
            Task {
                await checkTrialEligibility()
            }
        }
    }
    
    private var selectedProduct: Product? {
        subscriptionManager.products.first { $0.id == selectedProductID }
    }
    
    private var primaryButtonText: String {
        guard let product = selectedProduct else { return "Select Plan" }
        
        let isTrialEligible = trialEligibility[product.id] ?? true
        
        if product.id == SubscriptionManager.monthlyProductID {
            return isTrialEligible ? "Start 7-Day Free Trial" : "Subscribe for \(product.displayPrice)/month"
        } else {
            return isTrialEligible ? "Start 7-Day Free Trial" : "Subscribe for \(product.displayPrice)/year"
        }
    }
    
    private func subscriptionDetailsText(for product: Product) -> String {
        let price = product.displayPrice
        let isTrialEligible = trialEligibility[product.id] ?? true
        
        if product.id == SubscriptionManager.monthlyProductID {
            return isTrialEligible ? 
                "Free for 7 days, then \(price)/month. Cancel anytime." :
                "Billed monthly at \(price). Cancel anytime."
        } else {
            return isTrialEligible ?
                "Free for 7 days, then \(price)/year. Cancel anytime." :
                "Billed yearly at \(price). Cancel anytime."
        }
    }
    
    private func handlePurchase() async {
        guard let product = selectedProduct else { return }
        
        // The purchase will still show Apple's confirmation dialog, but our PaywallView
        // provides all the detailed information the user needs to make the decision
        let result = await subscriptionManager.purchase(product)
        
        switch result {
        case .success:
            showingPurchaseConfirmation = true
        case .userCancelled:
            // User cancelled the Apple payment confirmation, do nothing
            break
        case .pending:
            // Purchase is pending (e.g., Ask to Buy), could show a message
            break
        case .failed(let error):
            print("Purchase failed: \(error)")
            // Error is already stored in subscriptionManager.errorMessage
        case .unknown:
            print("Unknown purchase result")
        }
    }
    
    private func checkTrialEligibility() async {
        for product in subscriptionManager.products {
            let isEligible = await checkTrialEligibility(for: product)
            await MainActor.run {
                trialEligibility[product.id] = isEligible
            }
        }
    }
    
    private func checkTrialEligibility(for product: Product) async -> Bool {
        // First, check if the product actually has an introductory offer configured
        guard let subscriptionInfo = product.subscription,
              let introOffer = subscriptionInfo.introductoryOffer else {
            print("🔧 PaywallView: Product \(product.id) has no introductory offer configured")
            return false // No intro offer available for this product
        }
        
        print("🔧 PaywallView: Product \(product.id) has intro offer: \(introOffer.period.value) \(introOffer.period.unit) at \(introOffer.displayPrice)")
        
        // Check transaction history to see if user has used a trial before
        for await transaction in Transaction.all {
            // Verify the transaction
            guard case .verified(let verifiedTransaction) = transaction else {
                continue
            }
            
            // Check if this transaction was for the same subscription group
            // and was an introductory offer (trial)
            if (verifiedTransaction.productID == SubscriptionManager.monthlyProductID || 
                verifiedTransaction.productID == SubscriptionManager.yearlyProductID) &&
               verifiedTransaction.offer?.type == .introductory {
                print("🔧 PaywallView: Found previous trial usage for product \(verifiedTransaction.productID)")
                return false // User has used trial before
            }
        }
        
        print("🔧 PaywallView: User is eligible for trial on product \(product.id)")
        return true // Product has intro offer AND user hasn't used trial before
    }
}

struct FeatureBenefitRow: View {
    let icon: String
    let title: String
    let description: String
    let isHighlighted: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isHighlighted ? 
                          LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isHighlighted ? .white : .primary)
            }
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(isHighlighted ? .semibold : .medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct SubscriptionOptionCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var isYearly: Bool {
        product.id == SubscriptionManager.yearlyProductID
    }
    
    private var savingsText: String? {
        if isYearly {
            // Calculate actual savings dynamically
            return calculateSavings()
        }
        return nil
    }
    
    private func calculateSavings() -> String? {
        // This would need access to both products to calculate actual savings
        // For now, keeping the hardcoded value but making it more obvious
        return "Save 50%" // TODO: Calculate from actual monthly vs yearly pricing
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(product.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if let savings = savingsText {
                            Text(savings)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.green)
                                .cornerRadius(3)
                        }
                        
                        Spacer()
                    }
                    
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    PriceRow(product: product, isYearly: isYearly)
                }
                
                SelectionIndicator(isSelected: isSelected)
            }
            .padding(12)
            .background(cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
    }
}

struct PriceRow: View {
    let product: Product
    let isYearly: Bool
    
    var body: some View {
        HStack {
            Text(product.displayPrice)
                .font(.headline)
                .fontWeight(.bold)
            
            if isYearly {
                Text("• $\(String(format: "%.2f", NSDecimalNumber(decimal: product.price).doubleValue / 12))/mo")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct SelectionIndicator: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)
            
            if isSelected {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(feature: .streaks)
            .environmentObject(SubscriptionManager.shared)
    }
}
