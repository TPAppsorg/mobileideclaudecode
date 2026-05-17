import Foundation
import UIKit
import OSLog

@MainActor
final class AppRatingService {
    static let shared = AppRatingService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClaudeCodeMobile", category: "AppRating")
    private let appStoreID = "6770138041"
    
    private init() {}
    
    func appStoreRatingURL() -> URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
    
    func openAppStoreReview() {
        guard let url = appStoreRatingURL() else {
            logger.error("Failed to create App Store review URL")
            return
        }
        
        UIApplication.shared.open(url, options: [:]) { [logger] success in
            if success {
                logger.info("Opened App Store review URL")
            } else {
                logger.error("Failed to open App Store review URL")
            }
        }
    }
}
