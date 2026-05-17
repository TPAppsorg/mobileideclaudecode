import Foundation
import Combine
import SwiftUI
import Supabase

@MainActor
class GeminiChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var newMessageText: String = ""
    @Published var showPaywallForLimit: Bool = false
    @Published var paywallSelectedProductId: String = StoreManager.yearlyProductID
    
    /// Free tier: 1 user message per day in Agent chat. Paid = unlimited.
    private let freeDailyAgentMessageLimit = 1
    var purchasedFromPaywall = false
    var lastInputMethod: AnalyticsEvent.InputMethod = .text
    
    var isSubscribed: Bool {
        let ids = StoreManager.shared.purchasedProductIDs
        return ids.contains(StoreManager.monthlyProductID) || ids.contains(StoreManager.yearlyProductID)
    }
    
    init() {
        Task {
            await loadHistory()
        }
    }
    
    private func loadHistory() async {
        guard let userId = SupabaseService.shared.currentUserId else { return }
        do {
            let rows: [ChatMessage] = try await SupabaseService.shared.client
                .from("agent_messages")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value
            
            self.messages = rows
        } catch {
            print("[GeminiChat] Failed to load history: \(error.localizedDescription)")
        }
    }
    
    func sendMessage() {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        guard let userId = SupabaseService.shared.currentUserId else { return }
        
        // Очищаем инпут сразу, чтобы не было визуальной задержки.
        newMessageText = ""
        
        Task {
            // Free tier limit for non-subscribed users: 1 agent question per day.
            if !isSubscribed {
                do {
                    let count = try await SupabaseService.shared.fetchTodaysAgentUserMessageCount(userId: userId)
                    if count >= freeDailyAgentMessageLimit {
                        Analytics.track(.chatLimitReached(source: .agent))
                        showPaywallForLimit = true
                        return
                    }
                } catch {
                    print("[GeminiChat] Failed to check daily agent limit: \(error.localizedDescription)")
                    return
                }
            }
            
            Analytics.track(.chatMessageSent(source: .agent, method: lastInputMethod, length: text.count))
            lastInputMethod = .text

            let userMessage = ChatMessage(
                id: UUID(),
                createdAt: Date(),
                role: "user",
                content: text,
                status: "pending",
                sessionId: nil,
                model: "gemini-3-flash-preview",
                userId: userId
            )
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.messages.append(userMessage)
                }
            }
            
            do {
                // Берём только последние ~10 сообщений истории, чтобы не раздувать промпт и не ловить таймауты.
                let recentContext = Array(self.messages.dropLast().suffix(10))
                let history: [GeminiChatService.HistoryItem] = recentContext.map {
                    GeminiChatService.HistoryItem(
                        role: $0.role == "user" ? "user" : "agent",
                        content: $0.content
                    )
                }
                
                let response = try await GeminiChatService.shared.send(
                    userId: userId,
                    message: text,
                    history: history
                )
                
                var messagesToPersist: [ChatMessage] = []
                
                await MainActor.run {
                    if let index = self.messages.firstIndex(where: { $0.id == userMessage.id }) {
                        self.messages[index].status = "completed"
                        self.messages[index].model = response.model ?? "gemini-3-flash-preview"
                        messagesToPersist.append(self.messages[index])
                    }
                    
                    let assistantMessage = ChatMessage(
                        id: UUID(),
                        createdAt: Date(),
                        role: "agent",
                        content: response.reply,
                        status: "completed",
                        sessionId: nil,
                        model: response.model ?? "gemini-3-flash-preview",
                        userId: userId
                    )
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.messages.append(assistantMessage)
                    }
                    messagesToPersist.append(assistantMessage)
                }
                
                // Persist last user+assistant messages in Supabase
                if !messagesToPersist.isEmpty {
                    do {
                        try await SupabaseService.shared.client
                            .from("agent_messages")
                            .insert(messagesToPersist)
                            .execute()
                    } catch {
                        print("[GeminiChat] Failed to persist messages: \(error.localizedDescription)")
                    }
                }
            } catch {
                print("[GeminiChat] Error: \(error.localizedDescription)")
                Analytics.track(.chatMessageFailed(source: .agent))
                await MainActor.run {
                    if let index = self.messages.firstIndex(where: { $0.id == userMessage.id }) {
                        self.messages[index].status = "error"
                    }
                }
            }
        }
    }
    
    func retryMessage(messageId: UUID) {
        guard let failed = messages.first(where: { $0.id == messageId && $0.role == "user" && $0.status == "error" }) else {
            return
        }
        Analytics.track(.chatMessageRetried(source: .agent))
        newMessageText = failed.content
        sendMessage()
    }
    
    func deleteMessage(messageId: UUID) {
        Analytics.track(.chatMessageDeleted(source: .agent))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.removeAll { $0.id == messageId }
        }
    }
    
    func onPaywallDismissed() {
        if !purchasedFromPaywall {
            newMessageText = ""
        }
        purchasedFromPaywall = false
    }
}

