import Foundation

/// Stub analytics — replaces Firebase analytics for Claude Code Mobile.
/// Add real analytics later as needed.
enum Analytics {
    static func track(_ event: AnalyticsEvent) {
        #if DEBUG
        print("[Analytics] \(event)")
        #endif
    }

    static func setUserProperty(_ value: String?, for property: AnalyticsUserProperty) {
        // No-op stub
    }
}

enum AnalyticsUserProperty {
    case appVersion, platform
}

enum AnalyticsEvent: CustomStringConvertible {
    case appOpened, appBackgrounded
    case menuOpened
    case connectionConnectClicked, connectionDisconnectClicked, connectionIdCopied
    case agentChatOpened
    case clearHistoryClicked
    case chatMessageSent(source: ChatSource, method: InputMethod, length: Int)
    case chatMessageFailed(source: ChatSource)
    case chatMessageRetried(source: ChatSource)
    case chatMessageDeleted(source: ChatSource)
    case chatLimitReached(source: ChatSource)
    case codeBlockCopied
    case speechRecordingStarted(source: ChatSource)
    case speechRecordingStopped(source: ChatSource)
    case onboardingPageViewed(pageIndex: Int)
    case onboardingDismissed
    case onboardingCompleted(method: OnboardingMethod)
    case onboardingRestoreClicked
    case onboardingViewAllPlansClicked
    case subscriptionPurchased(plan: SubscriptionPlan, paywallVersion: PaywallVersion = .v1)
    case restorePurchasesClicked
    case paywallShown(source: PaywallSource, version: PaywallVersion)
    case settingsLinkTapped(link: String)
    case promptBookOpened(section: String)
    case promptViewed(promptTitle: String)
    case tipViewed(tipTitle: String)
    case promptCopied(promptTitle: String)
    case promptUsedInAntigravity(promptTitle: String)
    case agentChatClosed

    enum ChatSource: String { case main, agent }
    enum InputMethod: String { case text, voice }
    enum OnboardingMethod: String { case dismiss, subscribe, restore, fallback }
    enum SubscriptionPlan: String { case monthly, yearly }
    enum PaywallSource: String { case onboarding, limitMain, bannerMain, limitAgent, bannerAgent }
    enum PaywallVersion: String { case v1, v2 }

    var description: String {
        switch self {
        case .appOpened: return "app_opened"
        case .appBackgrounded: return "app_backgrounded"
        case .menuOpened: return "menu_opened"
        case .connectionConnectClicked: return "connection_connect_clicked"
        case .connectionDisconnectClicked: return "connection_disconnect_clicked"
        case .connectionIdCopied: return "connection_id_copied"
        case .agentChatOpened: return "agent_chat_opened"
        case .agentChatClosed: return "agent_chat_closed"
        case .clearHistoryClicked: return "clear_history_clicked"
        case .chatMessageSent(let s, let m, let l): return "chat_message_sent(\(s),\(m),\(l))"
        case .chatMessageFailed(let s): return "chat_message_failed(\(s))"
        case .chatMessageRetried(let s): return "chat_message_retried(\(s))"
        case .chatMessageDeleted(let s): return "chat_message_deleted(\(s))"
        case .chatLimitReached(let s): return "chat_limit_reached(\(s))"
        case .codeBlockCopied: return "code_block_copied"
        case .speechRecordingStarted(let s): return "speech_recording_started(\(s))"
        case .speechRecordingStopped(let s): return "speech_recording_stopped(\(s))"
        case .onboardingPageViewed(let i): return "onboarding_page_viewed(\(i))"
        case .onboardingDismissed: return "onboarding_dismissed"
        case .onboardingCompleted(let m): return "onboarding_completed(\(m))"
        case .onboardingRestoreClicked: return "onboarding_restore_clicked"
        case .onboardingViewAllPlansClicked: return "onboarding_view_all_plans_clicked"
        case .subscriptionPurchased(let p, let v): return "subscription_purchased(\(p),\(v))"
        case .restorePurchasesClicked: return "restore_purchases_clicked"
        case .paywallShown(let s, let v): return "paywall_shown(\(s),\(v))"
        case .settingsLinkTapped(let l): return "settings_link_tapped(\(l))"
        case .promptBookOpened(let s): return "prompt_book_opened(\(s))"
        case .promptViewed(let t): return "prompt_viewed(\(t))"
        case .tipViewed(let t): return "tip_viewed(\(t))"
        case .promptCopied(let t): return "prompt_copied(\(t))"
        case .promptUsedInAntigravity(let t): return "prompt_used(\(t))"
        }
    }
}
