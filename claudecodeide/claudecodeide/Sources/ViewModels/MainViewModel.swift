import Foundation
import Combine
import Supabase
import SwiftUI

/// Free tier: 2 user messages per day (UTC). Paid = unlimited.
private let freeDailyMessageLimit = 2

@MainActor
class MainViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var newMessageText: String = ""
    @Published var isListening: Bool = false
    /// Показывать полноэкранный лоудер «Syncing Connection». Не показываем при первом запуске.
    @Published var isSyncing: Bool = false
    @Published var syncStatusText: String = ""
    /// Показывать пейвол при достижении дневного лимита.
    @Published var showPaywallForLimit = false
    /// Заблокировать ввод до подписки после закрытия пейвола без покупки.
    @Published var isInputBlockedDueToLimit = false
    
    /// Выбранный продукт в пейволе.
    @Published var paywallSelectedProductId = StoreManager.yearlyProductID
    /// Купил из пейвола — при onDismiss не стираем и не блокируем.
    var purchasedFromPaywall = false
    /// Tracks whether the current message was composed via voice input.
    var lastInputMethod: AnalyticsEvent.InputMethod = .text
    
    var isAwaitingAgentReply: Bool {
        guard let last = messages.last else { return false }
        if last.role == "user" && (last.status == "pending" || last.status == "processing") {
            return true
        }
        if last.role == "agent" && last.status == "streaming" {
            return true
        }
        return false
    }
    
    private var chatEventsCancellable: AnyCancellable?
    private var streamingByParentId: [UUID: UUID] = [:]
    
    var isSubscribed: Bool {
        let ids = StoreManager.shared.purchasedProductIDs
        return ids.contains(StoreManager.monthlyProductID) || ids.contains(StoreManager.yearlyProductID)
    }
    
    init() {
        // Subscribe to chat events from SupabaseService (private channel broadcasts)
        chatEventsCancellable = SupabaseService.shared.chatEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleChatEvent(event)
            }
        
        Task {
            print("[iOS Sync] 🚀 Initializing MainViewModel...")
            if let userId = await SupabaseService.shared.signInAnonymouslyIfNeeded() {
                print("[iOS Sync] 👤 Authenticated as \(userId). Starting sync...")
                await startSync(userId: userId, showLoader: false)
            } else {
                print("[iOS Sync] ❌ Failed to authenticate.")
                self.syncStatusText = "Auth Failed"
            }
        }
    }
    
    func startSync(userId: String, showLoader: Bool = false) async {
        if showLoader {
            self.isSyncing = true
            self.syncStatusText = "Connecting..."
        }
        defer { self.isSyncing = false }

        // Restore chat from the current active session (cold launch / app reopen)
        await restoreMessages(userId: userId)
    }

    func clearHistory() {
        Analytics.track(.clearHistoryClicked)
        self.messages.removeAll()
        Task {
            await SupabaseService.shared.clearHistory()
        }
    }

    /// Load messages for the currently active pair (project).
    /// Called only on app startup to restore chat after kill/reopen.
    private func restoreMessages(userId: String) async {
        let activePairId = SupabaseService.shared.activeSessions
            .first(where: { $0.id == SupabaseService.shared.selectedSessionId })?.pairId

        guard let pairId = activePairId else {
            print("[iOS Sync] 💬 No active session — starting with empty chat.")
            return
        }

        do {
            let fetched: [ChatMessage] = try await SupabaseService.shared.client
                .from("messages")
                .select()
                .eq("user_id", value: userId)
                .eq("pair_id", value: pairId.uuidString.lowercased())
                .eq("client_type", value: "claudecodemobile")
                .order("created_at", ascending: true)
                .execute()
                .value

            // Filter out SYSTEM messages
            let visible = fetched.filter { !$0.content.starts(with: "SYSTEM:") }
            self.messages = visible
            print("[iOS Sync] 💬 Restored \(visible.count) messages for current session.")
        } catch {
            print("[iOS Sync] ❌ Failed to restore messages: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Chat events handler
    
    private func handleChatEvent(_ event: ChatEvent) {
        switch event {
        case .sessionChanged:
            // New project or disconnect — start with a clean chat
            streamingByParentId.removeAll()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                messages.removeAll()
            }

        case .inserted(let record):
            // Skip all system messages — each session starts fresh
            if record.content.starts(with: "SYSTEM:") { return }
            
            // If it's an agent message but the parent doesn't exist, drop it (ghost from a cancelled message)
            if record.role == "agent", let parentId = record.parentMessageId, !messages.contains(where: { $0.id == parentId }) {
                return
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                // If this is the durable agent reply that finalizes a streaming ghost, update it in place
                if record.role == "agent",
                   let parentId = record.parentMessageId,
                   let ghostId = streamingByParentId[parentId],
                   let index = messages.firstIndex(where: { $0.id == ghostId }) {
                    messages[index].content = record.content
                    messages[index].status = record.status
                    messages[index].model = record.model
                    messages[index].userId = record.userId
                    messages[index].pairId = record.pairId
                    messages[index].sessionId = record.sessionId
                    messages[index].parentMessageId = record.parentMessageId
                    streamingByParentId[parentId] = nil
                    if let parentIndex = messages.firstIndex(where: { $0.id == parentId }) {
                        messages[parentIndex].status = "completed"
                    }
                    return
                }

                if let index = messages.firstIndex(where: { $0.id == record.id }) {
                    // Update existing (status change, content update)
                    messages[index] = record
                } else {
                    // Only append user messages if they are new (pending/processing). 
                    // If they are completed/error but missing, it means we intentionally deleted them locally via Stop/Delete!
                    if record.role == "user" && record.status != "pending" && record.status != "processing" {
                        return
                    }
                    messages.append(record)
                }
            }
            
        case .chunk(let parentMessageId, let delta):
            // Verify the parent (user) message exists
            guard let parentIndex = messages.firstIndex(where: { $0.id == parentMessageId }) else { return }
            let parent = messages[parentIndex]

            if let ghostId = streamingByParentId[parentMessageId],
               let index = messages.firstIndex(where: { $0.id == ghostId }) {
                messages[index].content += delta
                return
            }

            let ghost = ChatMessage(
                id: UUID(),
                createdAt: Date(),
                role: "agent",
                content: delta,
                status: "streaming",
                sessionId: parent.sessionId,
                model: SupabaseService.shared.selectedModel,
                userId: parent.userId,
                pairId: parent.pairId,
                parentMessageId: parentMessageId
            )
            streamingByParentId[parentMessageId] = ghost.id
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                messages.append(ghost)
            }
        }
    }
    
    /// Timeout (seconds) after which a pending user message is marked as error.
    private let sendPendingTimeoutSeconds: UInt64 = 30
    
    func sendMessage() {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        guard let userId = SupabaseService.shared.currentUserId else { return }
        
        // Resolve the active pair_id for RLS-scoped insert
        let activePairId = SupabaseService.shared.activeSessions
            .first(where: { $0.id == SupabaseService.shared.selectedSessionId })?.pairId
        
        Task {
            if !isSubscribed {
                do {
                    let count = try await SupabaseService.shared.fetchTodaysUserMessageCount(userId: userId)
                    if count >= freeDailyMessageLimit {
                        Analytics.track(.chatLimitReached(source: .main))
                        showPaywallForLimit = true
                        return
                    }
                } catch {
                    print("[iOS Sync] Failed to check daily limit: \(error.localizedDescription)")
                    return
                }
            }
            
            let resolvedContent = SupabaseService.shared.resolveCommandText(text)
            let message = ChatMessage(
                id: UUID(),
                createdAt: Date(),
                role: "user",
                content: resolvedContent,
                status: "pending",
                sessionId: nil,
                model: SupabaseService.shared.modelForMessages(),
                userId: userId,
                clientType: "claudecodemobile",
                pairId: activePairId,
                parentMessageId: nil,
                isCancelled: nil
            )
            
            Analytics.track(.chatMessageSent(source: .main, method: lastInputMethod, length: text.count))
            lastInputMethod = .text

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(message)
            }
            newMessageText = ""
            
            let isConnected = SupabaseService.shared.isConnected
            if !isConnected {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].status = "error"
                }
                Analytics.track(.chatMessageFailed(source: .main))
                return
            }
            
            do {
                try await SupabaseService.shared.client
                    .from("messages")
                    .insert(message)
                    .execute()
                startPendingTimeout(for: message.id)
            } catch {
                print("[iOS Sync] Error sending message: \(error.localizedDescription)")
                Analytics.track(.chatMessageFailed(source: .main))
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].status = "error"
                }
            }
        }
    }
    
    private func startPendingTimeout(for messageId: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: sendPendingTimeoutSeconds * 1_000_000_000)
            await MainActor.run {
                guard let index = messages.firstIndex(where: { $0.id == messageId }),
                      messages[index].role == "user",
                      messages[index].status == "pending" else { return }
                messages[index].status = "error"
            }
        }
    }
    
    func retryMessage(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].role == "user",
              messages[index].status == "error" else { return }
        let oldMessage = messages[index]
        guard let userId = oldMessage.userId ?? SupabaseService.shared.currentUserId,
              SupabaseService.shared.isConnected else { return }
        Analytics.track(.chatMessageRetried(source: .main))
        
        let activePairId = SupabaseService.shared.activeSessions
            .first(where: { $0.id == SupabaseService.shared.selectedSessionId })?.pairId
        
        let newMessage = ChatMessage(
            id: UUID(),
            createdAt: Date(),
            role: "user",
            content: oldMessage.content,
            status: "pending",
            sessionId: nil,
            model: SupabaseService.shared.modelForMessages(),
            userId: userId,
            clientType: "claudecodemobile",
            pairId: activePairId,
            parentMessageId: nil,
            isCancelled: nil
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages[index] = newMessage
        }
        
        Task {
            do {
                try await SupabaseService.shared.client
                    .from("messages")
                    .insert(newMessage)
                    .execute()
                startPendingTimeout(for: newMessage.id)
            } catch {
                print("[iOS Sync] Retry send failed: \(error.localizedDescription)")
                await MainActor.run {
                    if let i = messages.firstIndex(where: { $0.id == newMessage.id }) {
                        messages[i].status = "error"
                    }
                }
            }
        }
    }

    /// Вызвать при закрытии пейвола: если не купил — стереть ввод.
    func onPaywallDismissed() {
        if !purchasedFromPaywall {
            newMessageText = ""
        }
        purchasedFromPaywall = false
    }
    
    /// Разблокировать ввод, если пользователь оформил подписку.
    func clearInputBlockIfSubscribed() {
        if isSubscribed {
            isInputBlockedDueToLimit = false
        }
    }
    
    /// Все pending пользовательские сообщения → error.
    func markPendingUserMessagesAsError() {
        for index in messages.indices where messages[index].role == "user" && messages[index].status == "pending" {
            messages[index].status = "error"
        }
    }
    
    /// Удалить сообщение из списка и из БД.
    func deleteMessage(messageId: UUID) {
        Analytics.track(.chatMessageDeleted(source: .main))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.removeAll { $0.id == messageId }
        }
        Task {
            do {
                try await SupabaseService.shared.deleteMessage(id: messageId)
            } catch {
                print("[iOS Sync] Failed to delete message in DB: \(error.localizedDescription)")
            }
        }
    }
    
    /// Остановка текущей генерации
    func stopCurrentGeneration() {
        guard let lastUserMessage = messages.last(where: { $0.role == "user" }),
              let pairId = SupabaseService.shared.activeSessions.first(where: { $0.id == SupabaseService.shared.selectedSessionId })?.pairId ?? SupabaseService.shared.activeSessions.first?.pairId else {
            return
        }
        
        let restoredText = lastUserMessage.content
        let userMsgId = lastUserMessage.id
        
        // Analytics.track(.chatGenerationStopped(source: .main)) // Not implemented in ClaudeMobile yet
        
        let ghostId = streamingByParentId.removeValue(forKey: userMsgId)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let ghostId {
                messages.removeAll { $0.id == ghostId }
            }
            // Remove agent streaming ghosts if any
            messages.removeAll { m in
                m.parentMessageId == userMsgId && m.role == "agent" && m.status == "streaming"
            }
            // Remove user message
            messages.removeAll { $0.id == userMsgId }
        }
        
        if newMessageText.isEmpty {
            newMessageText = restoredText
        }

        Task {
            await SupabaseService.shared.cancelMessage(messageId: userMsgId, in: pairId)
            
            do {
                try await SupabaseService.shared.deleteUserMessageAndReplies(userMessageId: userMsgId)
            } catch {
                print("[iOS Sync] Failed to delete cancelled message: \(error.localizedDescription)")
            }
        }
    }
}
