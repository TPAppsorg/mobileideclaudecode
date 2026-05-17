import Foundation
import Supabase
import OSLog

@MainActor
final class RatingFeedbackService {
    static let shared = RatingFeedbackService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClaudeCodeMobile", category: "RatingFeedback")
    
    private init() {}
    
    func saveFeedback(
        _ feedback: String,
        source: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let trimmedFeedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFeedback.isEmpty else {
            completion?(.success(()))
            return
        }
        
        let userId = SupabaseService.shared.currentUserId ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        logger.info("Rating feedback from user \(userId) (v\(appVersion)): \(trimmedFeedback)")
        
        // Save to Supabase instead of Firestore
        Task {
            do {
                try await SupabaseService.shared.client
                    .from("rating_feedback")
                    .insert([
                        "user_id": userId,
                        "feedback": trimmedFeedback,
                        "app_version": appVersion,
                        "source": source,
                    ])
                    .execute()
                completion?(.success(()))
            } catch {
                logger.error("Failed to save rating feedback: \(error.localizedDescription)")
                // Silently succeed — don't block the user
                completion?(.success(()))
            }
        }
    }
}
