import SwiftUI
import StoreKit
import Combine

/// Текст «By proceeding…» с подчёркнутыми кликабельными ссылками (открывают плейсхолдер-URL).
private struct LegalDisclaimerText: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("By proceeding, you accept our ")
            Link(destination: URL(string: AppLegalLinks.termsOfUse)!) {
                Text("Terms of Use").underline().foregroundColor(.labelSecondary)
            }
            .font(.caption2)
            .tint(.labelSecondary)
            Text(" and ")
            Link(destination: URL(string: AppLegalLinks.privacyPolicy)!) {
                Text("Privacy Policy").underline().foregroundColor(.labelSecondary)
            }
            .font(.caption2)
            .tint(.labelSecondary)
        }
        .font(.caption2)
        .foregroundColor(.labelSecondary)
    }
}

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @State private var currentPage = 0
    
    let onboardingItems = [
        OnboardingItem(title: "Control Claude Code from iPhone", subtitle: "Send prompts to Claude Code CLI running on your computer — from anywhere."),
        OnboardingItem(title: "Agentic Coding on the Go", subtitle: "Claude writes, edits, and runs code in your project while you're away from the desk."),
        OnboardingItem(title: "Learn to Prompt Efficiently", subtitle: "Explore the Prompt Book — curated prompts for code review, refactoring, and more."),
        OnboardingItem(title: "Unlimited Prompts", subtitle: "Get unlimited access to the Mobile IDE for Claude Code AI and unlock agentic coding from anywhere.")
    ]
    
    @ObservedObject var storeManager = StoreManager.shared
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    
    @State private var showingPricingModal = false
    @State private var selectedProductId = StoreManager.monthlyProductID
    
    private var currentProduct: Product? {
        storeManager.products.first { $0.id == selectedProductId }
    }

    private var showingPricingModalSheetBinding: Binding<Bool> {
        Binding(
            get: { showingPricingModal && !remoteConfig.isPaywallV2Enabled },
            set: { showingPricingModal = $0 }
        )
    }

    private var showingPricingModalFullScreenBinding: Binding<Bool> {
        Binding(
            get: { showingPricingModal && remoteConfig.isPaywallV2Enabled },
            set: { showingPricingModal = $0 }
        )
    }
    
    private var priceLabel: String {
        guard let p = currentProduct else {
            return "..."
        }
        if AppPaywallPriceConfig.showYearlyPricePerDay, p.id == StoreManager.yearlyProductID {
            let perDay = p.price / Decimal(365)
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale.current
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            let str = formatter.string(from: NSDecimalNumber(decimal: perDay)) ?? "\(perDay)"
            return "\(str) / day"
        }
        return "\(p.displayPrice) / \(p.id == StoreManager.yearlyProductID ? "year" : "month")"
    }
    
    var body: some View {
        ZStack {
            Color.backgroundPrimary.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top Bar with Dismiss Button (only on last page)
                HStack {
                    if currentPage == onboardingItems.count - 1 {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            Analytics.track(.onboardingDismissed)
                            Analytics.track(.onboardingCompleted(method: .dismiss))
                            withAnimation {
                                hasCompletedOnboarding = true
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.labelPrimary.opacity(0.3))
                                .padding(8)
                        }
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    if currentPage == onboardingItems.count - 1 {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            Analytics.track(.onboardingRestoreClicked)
                            Task {
                                await storeManager.restorePurchases()
                                if !storeManager.purchasedProductIDs.isEmpty {
                                    Analytics.track(.onboardingCompleted(method: .restore))
                                    withAnimation { hasCompletedOnboarding = true }
                                }
                            }
                        }) {
                            Text("Restore")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.labelPrimary.opacity(0.3))
                                .padding(8)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .frame(height: 44)
                
                // Static Header Section for Page Indicator
                VStack(alignment: .leading, spacing: 0) {
                    // Content Switcher
                    TabView(selection: $currentPage) {
                        ForEach(0..<onboardingItems.count, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(onboardingItems[index].title)
                                    .font(.dsLargeTitle)
                                    .foregroundColor(.labelPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Text(onboardingItems[index].subtitle)
                                    .font(.body)
                                    .foregroundColor(.labelSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 160)
                    .disabled(true) // Disable manual swipe gestures
                    
                    // Fixed Page Indicator - Now stays exactly under subtitle
                    HStack(spacing: 8) {
                        ForEach(0..<onboardingItems.count, id: \.self) { stepIndex in
                            Capsule()
                                .fill(currentPage == stepIndex ? Color.labelPrimary : Color.labelSecondary.opacity(0.3))
                                .frame(width: currentPage == stepIndex ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                
                // Middle zone: image at bottom on all pages (same level); on last page price block on top of image
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    Image("o_\(currentPage + 1)")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.25), value: currentPage)
                    if currentPage == onboardingItems.count - 1 {
                        VStack(spacing: 0) {
                            Text(priceLabel)
                                .font(.dsHeadline)
                                .foregroundColor(.labelPrimary)
                                .padding(.bottom, 4)
                            Text("Cancel Anytime")
                                .font(.subheadline)
                                .foregroundColor(.labelSecondary)
                                .padding(.bottom, 16)
                            Button(action: {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                Analytics.track(.onboardingViewAllPlansClicked)
                                showingPricingModal = true
                            }) {
                                Text("View all plans")
                                    .font(.subheadline)
                                    .foregroundColor(.labelSecondary)
                                    .underline()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
                
                // Bottom Section: button and legal
                VStack(spacing: 0) {
                    // Continue / Subscribe Button
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        
                        if currentPage < onboardingItems.count - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                            Analytics.track(.onboardingPageViewed(pageIndex: currentPage))
                        } else {
                            if let product = currentProduct {
                                Task {
                                    do {
                                        if try await storeManager.purchase(product) != nil {
                                            let plan: AnalyticsEvent.SubscriptionPlan = product.id == StoreManager.yearlyProductID ? .yearly : .monthly
                                            Analytics.track(.subscriptionPurchased(plan: plan))
                                            Analytics.track(.onboardingCompleted(method: .subscribe))
                                            await MainActor.run {
                                                withAnimation { hasCompletedOnboarding = true }
                                            }
                                        }
                                    } catch {
                                        print("Purchase failed: \(error)")
                                    }
                                }
                            } else {
                                Analytics.track(.onboardingCompleted(method: .fallback))
                                withAnimation {
                                    hasCompletedOnboarding = true
                                }
                            }
                        }
                    }) {
                        Text(currentPage == onboardingItems.count - 1 ? AppButtonLabels.subscribe : "Continue")
                            .font(.dsHeadline)
                            .foregroundColor(.labelPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.brandPrimary)
                            .clipShape(Capsule())
                            .padding(.horizontal, 24)
                    }
                    
                    LegalDisclaimerText()
                        .padding(.top, 12)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            Analytics.track(.onboardingPageViewed(pageIndex: 0))
        }
        .sheet(isPresented: showingPricingModalSheetBinding) {
            PaywallSheetRouter(
                selectedProductId: $selectedProductId,
                subscribeButtonLabel: AppButtonLabels.subscribe,
                paywallSource: .onboarding
            ) {
                hasCompletedOnboarding = true
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: showingPricingModalFullScreenBinding) {
            PaywallSheetRouter(
                selectedProductId: $selectedProductId,
                subscribeButtonLabel: AppButtonLabels.subscribe,
                paywallSource: .onboarding
            ) {
                hasCompletedOnboarding = true
            }
        }
    }
}

struct PricingModalView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedProductId: String
    var subscribeButtonLabel: String = AppButtonLabels.subscribe
    @ObservedObject var storeManager = StoreManager.shared
    var paywallSource: AnalyticsEvent.PaywallSource = .onboarding
    var onPurchaseSuccess: (() -> Void)?
    
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    
    private var selectedProduct: Product? {
        storeManager.products.first { $0.id == selectedProductId }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Text("Choose your plan")
                    .font(.dsTitle2)
                    .foregroundColor(.labelPrimary)
                    .padding(.top, 32)
                
                VStack(spacing: 12) {
                    if !storeManager.products.isEmpty {
                        let monthlyPrice = storeManager.products.first(where: { $0.id == StoreManager.monthlyProductID })?.price
                        ForEach(storeManager.products) { product in
                            PlanRow(product: product, isSelected: selectedProductId == product.id, monthlyPrice: monthlyPrice) {
                                selectedProductId = product.id
                                purchaseError = nil
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            if let error = storeManager.errorMessage {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.semanticWarning)
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.labelSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Button("Retry") {
                                    Task { await storeManager.fetchProducts() }
                                }
                                .font(.caption.bold())
                                .foregroundColor(.semanticInfo)
                            } else {
                                ProgressView()
                                    .tint(.labelSecondary)
                                Text("Loading plans...")
                                    .foregroundColor(.labelSecondary)
                            }
                        }
                    }
                    
                    if let err = purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.semanticWarning)
                            .multilineTextAlignment(.center)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "shield")
                            .font(.footnote)
                        Text("Secured by Apple")
                            .font(.footnote)
                    }
                    .foregroundColor(.labelSecondary)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                
                Button(action: startPurchase) {
                    Group {
                        if isPurchasing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .labelPrimary))
                        } else {
                            Text(subscribeButtonLabel)
                        }
                    }
                    .font(.dsHeadline)
                    .foregroundColor(.labelPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedProduct != nil && !isPurchasing ? Color.brandPrimary : Color.labelTertiary)
                    .clipShape(Capsule())
                }
                .disabled(isPurchasing || selectedProduct == nil)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                HStack(spacing: 12) {
                    Link(destination: URL(string: AppLegalLinks.privacyPolicy)!) {
                        Text("Privacy Policy").underline().foregroundColor(.labelSecondary)
                    }
                    .font(.caption2)
                    .tint(.labelSecondary)
                    Text("·").foregroundColor(.labelSecondary).font(.caption2)
                    Button(action: {
                        Analytics.track(.restorePurchasesClicked)
                        Task {
                            await storeManager.restorePurchases()
                            if !storeManager.purchasedProductIDs.isEmpty {
                                dismiss()
                                onPurchaseSuccess?()
                            }
                        }
                    }) {
                        Text("Restore").underline().foregroundColor(.labelSecondary)
                    }
                    .font(.caption2)
                    Text("·").foregroundColor(.labelSecondary).font(.caption2)
                    Link(destination: URL(string: AppLegalLinks.termsOfUse)!) {
                        Text("Terms of Use").underline().foregroundColor(.labelSecondary)
                    }
                    .font(.caption2)
                    .tint(.labelSecondary)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            Analytics.track(.paywallShown(source: paywallSource, version: .v1))
        }
    }
    
    private func startPurchase() {
        guard let product = selectedProduct else { return }
        purchaseError = nil
        isPurchasing = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        Task {
            do {
                let transaction = try await storeManager.purchase(product)
                await MainActor.run {
                    isPurchasing = false
                    if transaction != nil {
                        let plan: AnalyticsEvent.SubscriptionPlan = product.id == StoreManager.yearlyProductID ? .yearly : .monthly
                        Analytics.track(.subscriptionPurchased(plan: plan, paywallVersion: .v1))
                        dismiss()
                        onPurchaseSuccess?()
                    }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseError = error.localizedDescription
                }
            }
        }
    }
}

struct PlanOption: Identifiable {
    let id: String
    let name: String
    let price: String
    let period: String
    let saveText: String?
}

struct PlanRow: View {
    let product: Product
    let isSelected: Bool
    var monthlyPrice: Decimal?
    let action: () -> Void
    
    private var planTitle: String {
        if !product.displayName.isEmpty { return product.displayName }
        return product.id == StoreManager.yearlyProductID ? "Yearly Access" : "Monthly Access"
    }
    
    private var savingsPercent: Int? {
        guard product.id == StoreManager.yearlyProductID,
              let monthly = monthlyPrice, monthly > 0 else { return nil }
        let fullYearCost = monthly * 12
        let saved = fullYearCost - product.price
        let percent = (saved / fullYearCost) * 100
        return Int(NSDecimalNumber(decimal: percent).rounding(accordingToBehavior: nil).intValue)
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(planTitle)
                            .font(.dsHeadline)
                            .foregroundColor(.labelPrimary)
                        
                        if let percent = savingsPercent, percent > 0 {
                            Text("Save \(percent)%")
                                .font(.caption2.bold())
                                .foregroundColor(.semanticSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.semanticSuccess.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("\(product.displayPrice) / \(product.id == StoreManager.monthlyProductID ? "month" : "year")")
                        .font(.subheadline)
                        .foregroundColor(.labelSecondary)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.brandPrimary : Color.labelSecondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.brandPrimary.opacity(0.1) : Color.labelPrimary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.brandPrimary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }
}


struct OnboardingItem {
    let title: String
    let subtitle: String
}

#Preview {
    OnboardingView()
}
