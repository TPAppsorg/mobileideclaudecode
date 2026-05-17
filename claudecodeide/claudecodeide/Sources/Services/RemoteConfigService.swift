import Foundation
import Combine

/// Stub RemoteConfig — replaces Firebase Remote Config.
@MainActor
class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()
    @Published var isPaywallV2Enabled: Bool = false

    func initialize() async {
        // No-op — add real remote config later
    }
}
