import Foundation

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var createdAt: Date
    var role: String // "user" or "agent"
    var content: String
    var status: String // "pending", "processing", "streaming", "completed", "error", "cancelled"
    var sessionId: UUID?
    var model: String?
    var userId: String?
    var clientType: String?
    var pairId: UUID?
    var parentMessageId: UUID?
    var isCancelled: Bool?

    /// Standalone in-app agent chat uses this client_type to keep
    /// messages out of the bridge pipeline.
    static let inAppAskClientType = "claudecodemobile-ask"

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case role
        case content
        case status
        case sessionId = "session_id"
        case model
        case userId = "user_id"
        case clientType = "client_type"
        case pairId = "pair_id"
        case parentMessageId = "parent_message_id"
        case isCancelled = "is_cancelled"
    }
}
