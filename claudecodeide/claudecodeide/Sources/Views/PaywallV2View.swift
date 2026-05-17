import SwiftUI
import StoreKit

struct PaywallV2View: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedProductId: String
    var subscribeButtonLabel: String = AppButtonLabels.subscribe
    var paywallSource: AnalyticsEvent.PaywallSource = .onboarding
    var onPurchaseSuccess: (() -> Void)?

    @ObservedObject private var storeManager = StoreManager.shared

    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showExitAlert = false

    private let accentBlue = Color.brandPrimary

    private var selectedProduct: Product? {
        storeManager.products.first { $0.id == selectedProductId }
    }

    private var monthlyProduct: Product? {
        storeManager.products.first { $0.id == StoreManager.monthlyProductID }
    }

    private var yearlyProduct: Product? {
        storeManager.products.first { $0.id == StoreManager.yearlyProductID }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.backgroundPrimary,
                    Color.backgroundPrimary,
                    accentBlue.opacity(0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Image("paywallV2Icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 164, height: 93)
                            .padding(.top, 8)

                        VStack(spacing: 10) {
                            Text("Unlock\nUnlimited Prompts")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.labelPrimary)
                                .multilineTextAlignment(.center)

                            Text("Get unlimited access to Claude Code")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.labelPrimary.opacity(0.65))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 28)

                        reviewsCarousel
                            .padding(.top, 28)

                        VStack(spacing: 10) {
                            planCard(
                                title: "Monthly",
                                isSelected: selectedProductId == StoreManager.monthlyProductID,
                                isBestOffer: false,
                                product: monthlyProduct,
                                priceLabel: monthlyPriceLabel,
                                introOffer: monthlyIntroOfferLabel,
                                action: { select(StoreManager.monthlyProductID) }
                            )

                            planCard(
                                title: "Annual",
                                isSelected: selectedProductId == StoreManager.yearlyProductID,
                                isBestOffer: true,
                                product: yearlyProduct,
                                priceLabel: yearlyPriceLabel,
                                introOffer: nil,
                                action: { select(StoreManager.yearlyProductID) }
                            )
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 20)

                        HStack(spacing: 6) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 13))
                                .foregroundColor(.labelPrimary.opacity(0.6))

                            Text("SECURED BY APPLE")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.labelPrimary.opacity(0.6))
                                .tracking(1)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.bottom, 20)
                }

                bottomSection
            }
        }
        .onAppear {
            if selectedProductId != StoreManager.monthlyProductID,
               selectedProductId != StoreManager.yearlyProductID {
                selectedProductId = StoreManager.yearlyProductID
            }
            Analytics.track(.paywallShown(source: paywallSource, version: .v2))
        }
        .alert(
            "Leave Premium?",
            isPresented: $showExitAlert,
            actions: {
                Button("Stay", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    dismiss()
                }
            },
            message: {
                Text("You'll lose access to unlimited prompts if you leave now.")
            }
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                showExitAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.labelPrimary.opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.labelPrimary.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var reviewsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                reviewCard(quote: "Magic for Engineers", logoImageName: "wiredLogo")
                reviewCard(quote: "The Future of Coding", logoImageName: "techCrunchLogo", logoHeight: 28)
                reviewCard(quote: "10x Your Workflow", logoImageName: "forbesLogo")
            }
            .padding(.horizontal, 20)
        }
    }

    private var monthlyPriceLabel: String? {
        guard let product = monthlyProduct else { return nil }
        return "\(product.displayPrice) / month"
    }

    private var yearlyPriceLabel: String? {
        guard let product = yearlyProduct else { return nil }
        if AppPaywallPriceConfig.showYearlyPricePerDay {
            let perDay = product.price / Decimal(365)
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale.current
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            let priceString = formatter.string(from: NSDecimalNumber(decimal: perDay)) ?? "\(perDay)"
            return "\(priceString) / day"
        }
        return "\(product.displayPrice) / year"
    }

    private var monthlyIntroOfferLabel: String? {
        guard let product = monthlyProduct,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return nil
        }

        return "\(formatPeriod(offer.period)) Free"
    }

    private var bottomSection: some View {
        VStack(spacing: 12) {
            if let err = purchaseError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.semanticWarning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: startPurchase) {
                HStack {
                    Spacer()
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.labelPrimary)
                    } else {
                        Text(subscribeButtonText)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.labelPrimary)
                    }
                    Spacer()
                }
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accentBlue)
                )
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedProduct == nil)
            .padding(.horizontal, 28)

            HStack(spacing: 24) {
                Link(destination: URL(string: AppLegalLinks.termsOfUse)!) {
                    Text("Terms of Use")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.labelPrimary.opacity(0.45))
                        .underline()
                }

                Button {
                    Analytics.track(.restorePurchasesClicked)
                    Task {
                        await storeManager.restorePurchases()
                        if !storeManager.purchasedProductIDs.isEmpty {
                            dismiss()
                            onPurchaseSuccess?()
                        }
                    }
                } label: {
                    Text("Restore")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.labelPrimary.opacity(0.45))
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)

                Link(destination: URL(string: AppLegalLinks.privacyPolicy)!) {
                    Text("Privacy Policy")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.labelPrimary.opacity(0.45))
                        .underline()
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.backgroundPrimary.opacity(0.95), location: 0.15),
                    .init(color: Color.backgroundPrimary, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -20)
            .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private var subscribeButtonText: String {
        if selectedProductId == StoreManager.monthlyProductID,
           monthlyIntroOfferLabel != nil {
            return "Start Free Trial"
        }
        return subscribeButtonLabel
    }

    private func select(_ productId: String) {
        selectedProductId = productId
        purchaseError = nil
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
                        Analytics.track(.subscriptionPurchased(plan: plan, paywallVersion: .v2))
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

    private func formatPeriod(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.value == 1 ? "1 day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "1 week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "1 month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "1 year" : "\(period.value) years"
        @unknown default:
            return ""
        }
    }

    private func reviewCard(quote: String, logoImageName: String, logoHeight: CGFloat = 20) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                }
            }

            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.labelPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Image(logoImageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: logoHeight)
        }
        .frame(width: 200)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.labelPrimary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.labelPrimary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func planCard(
        title: String,
        isSelected: Bool,
        isBestOffer: Bool,
        product: Product?,
        priceLabel: String?,
        introOffer: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.labelPrimary)

                    if isBestOffer {
                        Text("BEST OFFER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.labelPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "3AEA71"))
                            )
                    }

                    if let introOffer {
                        Text(introOffer)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.labelPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.semanticSuccess.opacity(0.7))
                            )
                    }
                }

                Spacer()

                if let priceLabel {
                    Text(priceLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.labelPrimary.opacity(0.8))
                        .multilineTextAlignment(.trailing)
                } else if product == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.labelPrimary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accentBlue.opacity(0.12) : Color.labelPrimary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? accentBlue : Color.labelPrimary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallV2View(selectedProductId: .constant(StoreManager.yearlyProductID))
}
