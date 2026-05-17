import Foundation
import Combine
import Security
import Supabase
import SwiftUI
import UIKit

/// Model descriptor fetched from `system_info` ("available_models").
struct BridgeModel: Codable, Identifiable, Equatable {
    let id: String
    let label: String
}

/// Slash-command descriptor from `system_info` ("available_commands").
struct BridgeCommand: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let prompt: String
    var id: String { key }
}

struct BridgeSession: Codable, Identifiable, Equatable {
    let id: UUID
    let pairId: UUID
    let projectName: String?
    let projectPath: String?
    let startedAt: Date
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case pairId = "pair_id"
        case projectName = "project_name"
        case projectPath = "project_path"
        case startedAt = "started_at"
        case isActive = "is_active"
    }

    var displayTitle: String {
        let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let path = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return name.isEmpty ? "Session" : name
        }
        let base = URL(fileURLWithPath: path).lastPathComponent
        return base.isEmpty ? (name.isEmpty ? "Session" : name) : base
    }
}

/// Stores a stable per-install identifier in Keychain, **synchronized via
/// iCloud Keychain** so the same id follows the user across reinstalls,
/// device resets, and new iPhones.
///
/// Used by `rebind_ios_user_by_device` Supabase RPC to re-bind existing
/// `device_pairs` to a fresh anonymous `auth.uid()`, so chat history
/// survives reinstall / device migration.
private enum InstallationStore {
    private static let service = "dev.luch.claudecodemobile"
    private static let account = "installation_id"

    static func getOrCreateInstallationId() -> String {
        if let existing = read(synchronizable: true), !existing.isEmpty {
            return existing
        }
        if let legacy = read(synchronizable: false), !legacy.isEmpty {
            write(legacy, synchronizable: true)
            return legacy
        }
        let newId = UUID().uuidString.lowercased()
        write(newId, synchronizable: true)
        return newId
    }

    private static func read(synchronizable: Bool) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func write(_ value: String, synchronizable: Bool) {
        let data = Data(value.utf8)
        let accessibility: CFString = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessibility
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

/// Presence state advertised by the bridge on `pair:<pairId>` channel.
private struct BridgePresenceState: Codable {
    let role: String?
    let projectName: String?
    let projectPath: String?
    let sessionId: String?
    let startedAt: String?

    enum CodingKeys: String, CodingKey {
        case role
        case projectName = "project_name"
        case projectPath = "project_path"
        case sessionId = "session_id"
        case startedAt = "started_at"
    }
}

/// Advertised on `pair:<id>` so the Mac bridge can detect when the phone leaves.
private struct IosClientPresence: Codable {
    let role: String
    init() { role = "ios" }
}

/// Events published by SupabaseService to consumers (mainly MainViewModel)
/// in place of the old postgres_changes subscription.
enum ChatEvent {
    /// A new durable message arrived via the broadcast_changes trigger.
    case inserted(ChatMessage)
    /// A streaming chunk for an in-flight agent reply.
    case chunk(parentMessageId: UUID, delta: String)
    /// The active session/project changed — UI should clear local chat.
    case sessionChanged
}

/// All Supabase access for the app. Drives the chat over a single private
/// channel per pair (`pair:<pairId>`) carrying:
///   - presence: bridge online/offline state
///   - broadcast: streaming chunks, cancel signals
///   - broadcast_changes (DB trigger on `messages`): durable inserts/updates
///
/// Connection state, message stream, and project list are all derived from
/// channel events — no polling or heartbeat fallbacks.
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client = SupabaseClient(
        supabaseURL: URL(string: "https://dmlrznfuccnlpafprbxu.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRtbHJ6bmZ1Y2NubHBhZnByYnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5NTUyNzksImV4cCI6MjA5NDUzMTI3OX0.NqOvxYOQj9Iu_ksWAS8TGgFnu6fQ5DSeO7Dm4LUa-i8"
    )

    @Published var currentUserId: String?
    @Published var errorMessage: String?
    @Published var isConnected: Bool = false
    @Published var connectedWorkspaceName: String?
    @Published var availableModels: [BridgeModel]
    @Published var availableCommands: [BridgeCommand] = []
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Self.selectedModelStorageKey) }
    }
    @Published var activeSessions: [BridgeSession] = []
    @Published var selectedSessionId: UUID?

    /// Stream of chat-relevant events for MainViewModel.
    let chatEvents = PassthroughSubject<ChatEvent, Never>()

    private static let availableModelsInfoId = "available_models"
    private static let availableCommandsInfoId = "available_commands"
    private static let globalCatalogUserId = "global"
    private static let pairingTokenLifetimeSeconds: TimeInterval = 15 * 60
    private static let selectedModelStorageKey = "selectedClaudeModel"
    private static let selectedSessionStorageKey = "selected_session_id"
    private static let defaultModels: [BridgeModel] = [
        BridgeModel(id: "claude-sonnet-4-6", label: "Sonnet"),
        BridgeModel(id: "claude-opus-4-6", label: "Opus"),
        BridgeModel(id: "claude-haiku-3-5-20241022", label: "Haiku"),
    ]

    private struct SessionDisconnectUpdate: Encodable {
        let is_active: Bool
        let ended_at: String
    }

    private struct PairingInsert: Encodable {
        let ios_auth_user_id: String
        let ios_device_id: String
        let pairing_token: String
        let pairing_token_expires_at: String
        let is_active: Bool
    }

    private struct PairIdRow: Decodable {
        let id: UUID
    }

    private struct DBChangePayload: Decodable {
        let record: ChatMessage?
    }

    private struct ChunkPayload: Decodable {
        let messageId: UUID
        let delta: String
    }

    private struct CancelBroadcastPayload: Codable {
        let messageId: String
    }

    private struct BroadcastEnvelope<T: Decodable>: Decodable {
        let payload: T
    }

    /// One realtime channel per owned pair.
    private var pairChannels: [UUID: RealtimeChannelV2] = [:]
    /// Pairs created by iOS but not yet visible in active sessions list.
    private var pendingPairIds: Set<UUID> = []
    /// Pair ids whose bridge is currently online (presence sync).
    private var onlineBridges: Set<UUID> = []
    private var bootstrapTask: Task<String?, Never>?
    /// Cleanup tasks for expired pending pairs.
    private var pendingPairRealtimeCleanupTasks: [UUID: Task<Void, Never>] = [:]

    private init() {
        let persistedModel = UserDefaults.standard.string(forKey: Self.selectedModelStorageKey) ?? ""
        self.availableModels = Self.defaultModels
        self.selectedModel = persistedModel
        let persistedSessionId = UserDefaults.standard.string(forKey: Self.selectedSessionStorageKey)
        self.selectedSessionId = persistedSessionId.flatMap(UUID.init(uuidString:))

        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async -> String? {
        do {
            let session = try await client.auth.signInAnonymously()
            let authUid = session.user.id.uuidString.lowercased()
            await MainActor.run { self.currentUserId = authUid }
            await client.realtimeV2.setAuth(session.accessToken)

            await rebindOwnedPairsIfNeeded()
            await refreshBridgeCatalog()
            await refreshActiveSessions()
            return authUid
        } catch {
            let detailed = "Anonymous sign-in failed: \(error.localizedDescription)"
            await MainActor.run { self.errorMessage = detailed }
            return nil
        }
    }

    private func rebindOwnedPairsIfNeeded() async {
        let installationId = InstallationStore.getOrCreateInstallationId()
        do {
            let _: Int = try await client
                .rpc("rebind_ios_user_by_device", params: ["p_installation_id": installationId])
                .execute()
                .value
        } catch {
            // Not fatal: missing RPC just means we proceed without recovery.
        }
    }

    @MainActor
    func signInAnonymouslyIfNeeded() async -> String? {
        if let userId = currentUserId { return userId }
        if let task = bootstrapTask, let userId = await task.value {
            return userId
        }
        let retryTask = Task { [weak self] in
            await self?.bootstrap()
        }
        bootstrapTask = retryTask
        return await retryTask.value
    }

    // MARK: - Model & command catalog

    @MainActor
    func selectModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedModel = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.selectedModelStorageKey)
    }

    func modelForMessages() -> String {
        if availableModels.contains(where: { $0.id == selectedModel }) {
            return selectedModel
        }
        return availableModels.first?.id ?? Self.defaultModels[0].id
    }

    /// Display label for a model id. Falls back to the id itself.
    func modelLabel(forId id: String) -> String {
        if id.isEmpty { return "Auto" }
        return availableModels.first(where: { $0.id == id })?.label ?? id
    }

    /// Resolve `/command args` into a full prompt using command templates.
    func resolveCommandText(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return rawText }
        let body = trimmed.dropFirst()
        let parts = body.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let token = parts.first, !token.isEmpty else { return rawText }
        let commandKey = token.lowercased()
        guard let command = availableCommands.first(where: { $0.key.lowercased() == commandKey }) else {
            return rawText
        }
        let args = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if command.prompt.contains("{{args}}") {
            return command.prompt.replacingOccurrences(of: "{{args}}", with: args)
        }
        return args.isEmpty ? command.prompt : "\(command.prompt)\n\nContext: \(args)"
    }

    @MainActor
    func refreshBridgeCatalog() async {
        struct ModelsRowJSON: Decodable { let data: [BridgeModel] }
        struct CommandsRow: Decodable { let data: [BridgeCommand] }

        do {
            let modelRows: [ModelsRowJSON] = try await client
                .from("system_info")
                .select("data")
                .eq("id", value: Self.availableModelsInfoId)
                .eq("user_id", value: Self.globalCatalogUserId)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let first = modelRows.first, !first.data.isEmpty {
                self.availableModels = first.data
            }

            // Make sure the selected model is still valid.
            if !self.availableModels.contains(where: { $0.id == self.selectedModel }) {
                self.selectModel(self.availableModels.first?.id ?? Self.defaultModels[0].id)
            }

            let commandRows: [CommandsRow] = try await client
                .from("system_info")
                .select("data")
                .eq("id", value: Self.availableCommandsInfoId)
                .eq("user_id", value: Self.globalCatalogUserId)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let firstCommands = commandRows.first {
                self.availableCommands = firstCommands.data.filter {
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        } catch {
            // Fallback to defaults — don't crash.
            if !self.availableModels.contains(where: { $0.id == self.selectedModel }) {
                self.selectModel(self.availableModels.first?.id ?? Self.defaultModels[0].id)
            }
        }
    }

    // MARK: - Pairing link generation

    /// Create a fresh `device_pairs` row owned by this iOS user with a
    /// short-lived token; returns the deep link the bridge will receive.
    @MainActor
    func makeConnectURL() async -> URL? {
        guard let userId = await signInAnonymouslyIfNeeded() else {
            print("[Connect] ❌ signIn failed")
            if errorMessage == nil || errorMessage?.isEmpty == true {
                errorMessage = "Anonymous sign-in failed. Please reopen the app and try again."
            }
            return nil
        }
        print("[Connect] ✅ userId: \(userId)")

        let token = Self.generatePairingToken()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiresIso = formatter.string(from: Date().addingTimeInterval(Self.pairingTokenLifetimeSeconds))
        let deviceId = InstallationStore.getOrCreateInstallationId()
        let payload = PairingInsert(
            ios_auth_user_id: userId,
            ios_device_id: deviceId,
            pairing_token: token,
            pairing_token_expires_at: expiresIso,
            is_active: false
        )

        do {
            let inserted: [PairIdRow] = try await client
                .from("device_pairs")
                .insert(payload)
                .select("id")
                .execute()
                .value
            guard let pairId = inserted.first?.id else {
                print("[Connect] ❌ insert returned empty")
                return nil
            }
            print("[Connect] ✅ pairId: \(pairId)")
            pendingPairIds.insert(pairId)
            await joinPairChannel(pairId: pairId)

            var components = URLComponents(string: "https://luch.dev/claude.html")
            let expiresUnix = Int(Date().addingTimeInterval(Self.pairingTokenLifetimeSeconds).timeIntervalSince1970)
            components?.queryItems = [
                URLQueryItem(name: "pair", value: pairId.uuidString.lowercased()),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "expires", value: String(expiresUnix)),
            ]
            errorMessage = nil
            let url = components?.url
            print("[Connect] ✅ URL: \(url?.absoluteString ?? "nil")")
            return url
        } catch {
            let message = "Failed to create connect link: \(error.localizedDescription)"
            print("[Connect] ❌ \(message)")
            errorMessage = message
            return nil
        }
    }

    private static func generatePairingToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Sessions & channels

    @MainActor
    func selectSession(_ id: UUID?) {
        let previous = selectedSessionId
        selectedSessionId = id
        if let id {
            UserDefaults.standard.set(id.uuidString.lowercased(), forKey: Self.selectedSessionStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedSessionStorageKey)
        }
        recomputeConnectionState()
        // Notify UI to clear chat when switching to a different project
        if id != previous {
            chatEvents.send(.sessionChanged)
        }
    }

    func selectedSessionName() -> String {
        guard let id = selectedSessionId,
              let session = activeSessions.first(where: { $0.id == id }) else {
            return connectedWorkspaceName ?? "Session"
        }
        return session.displayTitle
    }

    @MainActor
    func refreshActiveSessions() async {
        guard let userId = currentUserId else { return }
        do {
            struct PairRow: Decodable { let id: UUID }
            let pairs: [PairRow] = try await client
                .from("device_pairs")
                .select("id")
                .eq("ios_auth_user_id", value: userId)
                .eq("is_active", value: true)
                .execute()
                .value
            let pairIds = Set(pairs.map(\.id))

            let sessions: [BridgeSession]
            if pairIds.isEmpty {
                sessions = []
            } else {
                let fetched: [BridgeSession] = try await client
                    .from("bridge_sessions")
                    .select("id,pair_id,project_name,project_path,started_at,is_active")
                    .eq("is_active", value: true)
                    .order("started_at", ascending: false)
                    .execute()
                    .value
                sessions = fetched.filter { pairIds.contains($0.pairId) }
            }
            self.activeSessions = sessions

            // Drop channels for pairs that disappeared.
            let currentPairIds = Set(sessions.map(\.pairId)).union(pairIds).union(pendingPairIds)
            for (pid, channel) in pairChannels where !currentPairIds.contains(pid) {
                Task { await self.teardownPairChannel(channel) }
                pairChannels[pid] = nil
                onlineBridges.remove(pid)
            }
            // Open channels for new pairs.
            for pid in currentPairIds where pairChannels[pid] == nil {
                Task { await self.joinPairChannel(pairId: pid) }
            }

            // Pick a default selected session if none / stale.
            if let selected = selectedSessionId, sessions.contains(where: { $0.id == selected }) {
                // keep
            } else {
                selectSession(sessions.first?.id)
            }

            // Remove no-longer-needed pending placeholders.
            let activePairIds = Set(sessions.map(\.pairId))
            pendingPairIds = pendingPairIds.subtracting(activePairIds)

            recomputeConnectionState()
        } catch {
            // Silently fail
        }
    }

    @MainActor
    private func teardownPairChannel(_ channel: RealtimeChannelV2) async {
        await channel.untrack()
        await channel.unsubscribe()
    }

    /// Subscribe to a pair's private channel: presence + broadcasts +
    /// DB-broadcast inserts. Idempotent.
    @MainActor
    private func joinPairChannel(pairId: UUID) async {
        if pairChannels[pairId] != nil { return }
        let topic = "pair:\(pairId.uuidString.lowercased())"
        let channel = client.realtimeV2.channel(topic) { config in
            config.isPrivate = true
        }
        pairChannels[pairId] = channel

        let presenceStream = channel.presenceChange()
        let insertStream = channel.broadcastStream(event: "INSERT")
        let updateStream = channel.broadcastStream(event: "UPDATE")
        let chunkStream = channel.broadcastStream(event: "chunk")

        // Presence: bridge joins/leaves
        Task { [weak self] in
            for await action in presenceStream {
                guard let self = self else { return }
                let joins = (try? action.decodeJoins(as: BridgePresenceState.self)) ?? []
                let leaves = (try? action.decodeLeaves(as: BridgePresenceState.self)) ?? []
                let bridgeJoined = joins.contains(where: { ($0.role ?? "") == "bridge" })
                let bridgeLeft = leaves.contains(where: { ($0.role ?? "") == "bridge" })
                await MainActor.run {
                    if bridgeJoined { self.onlineBridges.insert(pairId) }
                    if bridgeLeft && !bridgeJoined { self.onlineBridges.remove(pairId) }
                    self.recomputeConnectionState()
                }
                if bridgeJoined {
                    await self.refreshActiveSessions()
                }
            }
        }

        // Message INSERT broadcast (from broadcast_changes trigger)
        Task { [weak self] in
            for await event in insertStream {
                guard let self = self else { return }
                guard let envelope = try? event.decode(as: BroadcastEnvelope<DBChangePayload>.self),
                      let record = envelope.payload.record else { continue }
                self.chatEvents.send(.inserted(record))
            }
        }

        // Message UPDATE broadcast (status changes, cancel)
        Task { [weak self] in
            for await event in updateStream {
                guard let self = self else { return }
                guard let envelope = try? event.decode(as: BroadcastEnvelope<DBChangePayload>.self),
                      let record = envelope.payload.record else { continue }
                self.chatEvents.send(.inserted(record)) // reuse inserted — VM upserts by id
            }
        }

        // Streaming chunks
        Task { [weak self] in
            for await event in chunkStream {
                guard let self = self else { return }
                guard let envelope = try? event.decode(as: BroadcastEnvelope<ChunkPayload>.self) else { continue }
                self.chatEvents.send(.chunk(parentMessageId: envelope.payload.messageId, delta: envelope.payload.delta))
            }
        }

        try? await channel.subscribeWithError()
        do {
            try await channel.track(IosClientPresence())
        } catch {
            // Best-effort presence tracking
        }

        // Probe for already-online bridge (e.g. iOS app was killed & restarted
        // while bridge kept running). The presence join event may have fired
        // before our stream listener was ready, so we request a fresh sync
        // by re-tracking after a short delay.
        Task { @MainActor [weak self] in
            for delay in [UInt64(2_000_000_000), UInt64(5_000_000_000)] {
                try? await Task.sleep(nanoseconds: delay)
                guard let self = self, self.pairChannels[pairId] != nil else { return }
                if self.onlineBridges.contains(pairId) { return }

                // Re-track to trigger a presence sync round-trip;
                // the presenceChange stream will then fire with current state.
                do {
                    try await channel.track(IosClientPresence())
                } catch { }
            }
        }
    }

    @MainActor
    private func recomputeConnectionState() {
        let selectedPairId = activeSessions.first(where: { $0.id == selectedSessionId })?.pairId
        let online = selectedPairId.map { onlineBridges.contains($0) } ?? false
        if isConnected != online {
            withAnimation(.spring()) {
                isConnected = online
                connectedWorkspaceName = online
                    ? activeSessions.first(where: { $0.id == selectedSessionId })?.displayTitle
                    : nil
            }
        }
    }

    // MARK: - Cancel message

    /// Cancel an in-flight message via broadcast + durable DB update.
    @MainActor
    func cancelMessage(messageId: UUID, in pairId: UUID) async {
        let messageIdString = messageId.uuidString.lowercased()

        if let channel = pairChannels[pairId] {
            do {
                try await channel.broadcast(
                    event: "cancel",
                    message: CancelBroadcastPayload(messageId: messageIdString)
                )
            } catch { }
        }

        await persistMessageCancelled(messageId: messageId)
    }

    /// Durable cancel flag without a realtime broadcast.
    @MainActor
    func persistMessageCancelled(messageId: UUID) async {
        struct CancelUpdate: Encodable { let is_cancelled: Bool; let cancelled_at: String }
        let messageIdString = messageId.uuidString.lowercased()
        let nowIso = ISO8601DateFormatter().string(from: Date())
        do {
            try await client
                .from("messages")
                .update(CancelUpdate(is_cancelled: true, cancelled_at: nowIso))
                .eq("id", value: messageIdString)
                .execute()
        } catch { }
    }

    // MARK: - Disconnect

    @MainActor
    func disconnectSession(_ session: BridgeSession) async {
        do {
            let payload = SessionDisconnectUpdate(
                is_active: false,
                ended_at: ISO8601DateFormatter().string(from: Date())
            )
            try await client
                .from("bridge_sessions")
                .update(payload)
                .eq("id", value: session.id.uuidString.lowercased())
                .execute()
            _ = try? await client
                .from("device_pairs")
                .update(["is_active": false])
                .eq("id", value: session.pairId.uuidString.lowercased())
                .execute()

            if let channel = pairChannels[session.pairId] {
                Task { await self.teardownPairChannel(channel) }
                pairChannels[session.pairId] = nil
            }
            onlineBridges.remove(session.pairId)

            await refreshActiveSessions()

            // Clear chat on disconnect — next connection gets a fresh view
            chatEvents.send(.sessionChanged)
        } catch { }
    }

    /// `pair` query value from a connect link produced by `makeConnectURL`.
    static func pairIdFromConnectURL(_ url: URL) -> UUID? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "pair" })?.value
        else { return nil }
        return UUID(uuidString: raw)
    }

    /// Called when the share sheet is dismissed: after TTL, release realtime
    /// if the Mac never claimed this pair.
    @MainActor
    func schedulePendingPairRealtimeCleanupIfStillUnused(pairId: UUID) {
        pendingPairRealtimeCleanupTasks[pairId]?.cancel()
        let lifetimeNanos = UInt64(Self.pairingTokenLifetimeSeconds * 1_000_000_000)
        pendingPairRealtimeCleanupTasks[pairId] = Task { @MainActor in
            defer { self.pendingPairRealtimeCleanupTasks[pairId] = nil }
            do {
                try await Task.sleep(nanoseconds: lifetimeNanos)
            } catch { return }
            await self.refreshActiveSessions()
            guard self.pendingPairIds.contains(pairId) else { return }
            let hasSession = self.activeSessions.contains { $0.pairId == pairId }
            guard !hasSession else { return }
            await self.abandonPendingPairRealtimeResources(pairId: pairId)
        }
    }

    @MainActor
    func cancelAllPendingPairRealtimeCleanupTasks() {
        for task in pendingPairRealtimeCleanupTasks.values { task.cancel() }
        pendingPairRealtimeCleanupTasks.removeAll()
    }

    @MainActor
    private func abandonPendingPairRealtimeResources(pairId: UUID) async {
        pendingPairIds.remove(pairId)
        if let channel = pairChannels.removeValue(forKey: pairId) {
            await teardownPairChannel(channel)
        }
        onlineBridges.remove(pairId)
        recomputeConnectionState()
    }

    @MainActor
    func unlink() async {
        guard let userId = currentUserId else { return }

        cancelAllPendingPairRealtimeCleanupTasks()

        for (_, channel) in pairChannels {
            Task { await self.teardownPairChannel(channel) }
        }
        pairChannels.removeAll()
        onlineBridges.removeAll()

        _ = try? await client
            .from("device_pairs")
            .update(["is_active": false])
            .eq("ios_auth_user_id", value: userId)
            .execute()

        self.activeSessions = []
        selectSession(nil)
        recomputeConnectionState()
    }

    // MARK: - Chat history utilities

    @MainActor
    func clearHistory() async {
        guard let userId = currentUserId else { return }

        // Signal bridge to start a fresh Claude Code CLI session
        for (_, channel) in pairChannels {
            await channel.broadcast(
                    event: "reset_session",
                    message: ["reset": true]
                )
        }

        do {
            try await client
                .from("messages")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch { }
    }

    func deleteMessage(id: UUID) async throws {
        try await client
            .from("messages")
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }


    /// Stop-button cleanup: drop the user's pending row and any agent replies.
    func deleteUserMessageAndReplies(userMessageId: UUID) async throws {
        let key = userMessageId.uuidString.lowercased()
        _ = try? await client
            .from("messages")
            .delete()
            .eq("parent_message_id", value: key)
            .execute()
        try await client
            .from("messages")
            .delete()
            .eq("id", value: key)
            .execute()
    }

    func fetchTodaysUserMessageCount(userId: String) async throws -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let startOfTodayUTC = cal.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let from = formatter.string(from: startOfTodayUTC)

        struct IdOnly: Decodable { let id: UUID }
        let rows: [IdOnly] = try await client
            .from("messages")
            .select("id")
            .eq("user_id", value: userId)
            .eq("client_type", value: "claudecodemobile")
            .eq("role", value: "user")
            .gte("created_at", value: from)
            .execute()
            .value
        return rows.count
    }

    func fetchTodaysAgentUserMessageCount(userId: String) async throws -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let startOfTodayUTC = cal.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let from = formatter.string(from: startOfTodayUTC)

        struct IdOnly: Decodable { let id: UUID }
        let rows: [IdOnly] = try await client
            .from("agent_messages")
            .select("id")
            .eq("user_id", value: userId)
            .eq("role", value: "user")
            .gte("created_at", value: from)
            .execute()
            .value
        return rows.count
    }
}
