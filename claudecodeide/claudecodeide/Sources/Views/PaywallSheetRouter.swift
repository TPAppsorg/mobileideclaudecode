import SwiftUI

struct PaywallSheetRouter: View {
    @Binding var selectedProductId: String
    var subscribeButtonLabel: String = AppButtonLabels.subscribe
    var paywallSource: AnalyticsEvent.PaywallSource = .onboarding
    var onPurchaseSuccess: (() -> Void)?

    @ObservedObject private var remoteConfig = RemoteConfigService.shared

    var body: some View {
        Group {
            if remoteConfig.isPaywallV2Enabled {
                PaywallV2View(
                    selectedProductId: $selectedProductId,
                    subscribeButtonLabel: subscribeButtonLabel,
                    paywallSource: paywallSource,
                    onPurchaseSuccess: onPurchaseSuccess
                )
            } else {
                PricingModalView(
                    selectedProductId: $selectedProductId,
                    subscribeButtonLabel: subscribeButtonLabel,
                    paywallSource: paywallSource,
                    onPurchaseSuccess: onPurchaseSuccess
                )
            }
        }
    }
}
