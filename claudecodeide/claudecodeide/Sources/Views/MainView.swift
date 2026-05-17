import SwiftUI
import AVFoundation

struct MainView: View {
    private static var agentSoundPlayer: AVAudioPlayer?
    @StateObject private var viewModel = MainViewModel()
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @FocusState private var isInputFocused: Bool
    @StateObject private var speechManager = SpeechManager()
    @State private var showingMenu = false
    @State private var shareURL: URL? = nil
    @State private var showPaywallFromBanner = false
    @State private var showGeminiChat = false
    @State private var showConnectHintPopup = false
    @State private var connectHintDismissWorkItem: DispatchWorkItem?
    
    private var isSubscribed: Bool {
        storeManager.purchasedProductIDs.contains(StoreManager.monthlyProductID)
            || storeManager.purchasedProductIDs.contains(StoreManager.yearlyProductID)
    }

    private var showLimitPaywallSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showPaywallForLimit && !remoteConfig.isPaywallV2Enabled },
            set: { viewModel.showPaywallForLimit = $0 }
        )
    }

    private var showLimitPaywallFullScreenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showPaywallForLimit && remoteConfig.isPaywallV2Enabled },
            set: { viewModel.showPaywallForLimit = $0 }
        )
    }

    private var showBannerPaywallSheetBinding: Binding<Bool> {
        Binding(
            get: { showPaywallFromBanner && !remoteConfig.isPaywallV2Enabled },
            set: { showPaywallFromBanner = $0 }
        )
    }

    private var showBannerPaywallFullScreenBinding: Binding<Bool> {
        Binding(
            get: { showPaywallFromBanner && remoteConfig.isPaywallV2Enabled },
            set: { showPaywallFromBanner = $0 }
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.edgesIgnoringSafeArea(.all)
                buildChatScreen()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if supabaseService.isConnected {
                        Menu {
                            if let userId = supabaseService.currentUserId {
                                Section("Device Info") {
                                    Button(action: {
                                        UIPasteboard.general.string = userId
                                        let impact = UIImpactFeedbackGenerator(style: .medium)
                                        impact.impactOccurred()
                                        Analytics.track(.connectionIdCopied)
                                    }) {
                                        Text("ID: \(userId.prefix(8))...")
                                    }
                                }
                            }

                            Section("Model") {
                                ForEach(supabaseService.availableModels) { model in
                                    Button(action: {
                                        supabaseService.selectModel(model.id)
                                    }) {
                                        HStack {
                                            Text(model.label)
                                            if supabaseService.selectedModel == model.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button(role: .destructive, action: {
                                Analytics.track(.connectionDisconnectClicked)
                                Task {
                                    await supabaseService.unlink()
                                }
                            }) {
                                Text("Disconnect")
                            }
                        } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(supabaseService.modelLabel(forId: supabaseService.selectedModel))
                                        .font(.dsHeadline)
                                        .foregroundColor(.labelPrimary)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.labelPrimary.opacity(0.7))
                                }
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.semanticSuccess)
                                        .frame(width: 6, height: 6)
                                    
                                    Text("Connected")
                                        .font(.caption2)
                                        .foregroundColor(.labelPrimary.opacity(0.5))
                                }
                            }
                        }
                    } else {
                        Button(action: {
                            Analytics.track(.connectionConnectClicked)
                            Task {
                                shareURL = await supabaseService.makeConnectURL()
                            }
                        }) {
                            VStack(spacing: 1) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.semanticError)
                                        .frame(width: 7, height: 7)
                                    
                                    Text("Disconnected")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.labelPrimary)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.labelSecondary.opacity(0.8))
                                }
                                
                                Text("tap to connect")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.labelSecondary)
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Analytics.track(.menuOpened)
                        showingMenu = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundColor(.labelPrimary.opacity(0.8))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Analytics.track(.agentChatOpened)
                        playAgentActivationSound()
                        showGeminiChat = true
                    }) {
                        Image("claude")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .foregroundColor(.labelPrimary.opacity(0.9))
                    }
                }
            }
            .sheet(isPresented: $showingMenu) {
                MenuView(
                    viewModel: viewModel,
                    onInsertPrompt: {
                        viewModel.newMessageText = $0
                        showingMenu = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(item: Binding(
                get: { shareURL.map { ShareItem(url: $0) } },
                set: { shareURL = $0?.url }
            )) { item in
                ActivityView(
                    url: item.url,
                    title: "Open link on your computer",
                    subtitle: "Connect Claude Code to Claude Code CLI on your computer"
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    // Schedule cleanup if the Mac never claims this pair
                    if let pairId = SupabaseService.pairIdFromConnectURL(item.url) {
                        supabaseService.schedulePendingPairRealtimeCleanupIfStillUnused(pairId: pairId)
                    }
                }
            }
        }
        .task {
            _ = await supabaseService.signInAnonymouslyIfNeeded()
        }
        .onAppear {
            viewModel.clearInputBlockIfSubscribed()
        }
        .onChange(of: supabaseService.isConnected) { old, isConnected in
            if isConnected {
                showingMenu = false
                shareURL = nil
                connectHintDismissWorkItem?.cancel()
                showConnectHintPopup = false
            } else {
                viewModel.markPendingUserMessagesAsError()
            }
        }
        .onChange(of: storeManager.purchasedProductIDs) { _, _ in
            viewModel.clearInputBlockIfSubscribed()
        }
        .sheet(isPresented: showLimitPaywallSheetBinding, onDismiss: { viewModel.onPaywallDismissed() }) {
            PaywallLimitSheet(
                selectedProductId: $viewModel.paywallSelectedProductId,
                paywallSource: .limitMain,
                onPurchaseSuccess: {
                    viewModel.purchasedFromPaywall = true
                    viewModel.showPaywallForLimit = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: showLimitPaywallFullScreenBinding, onDismiss: { viewModel.onPaywallDismissed() }) {
            PaywallLimitSheet(
                selectedProductId: $viewModel.paywallSelectedProductId,
                paywallSource: .limitMain,
                onPurchaseSuccess: {
                    viewModel.purchasedFromPaywall = true
                    viewModel.showPaywallForLimit = false
                }
            )
        }
        .sheet(isPresented: showBannerPaywallSheetBinding) {
            PaywallLimitSheet(
                selectedProductId: $viewModel.paywallSelectedProductId,
                paywallSource: .bannerMain,
                onPurchaseSuccess: { showPaywallFromBanner = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: showBannerPaywallFullScreenBinding) {
            PaywallLimitSheet(
                selectedProductId: $viewModel.paywallSelectedProductId,
                paywallSource: .bannerMain,
                onPurchaseSuccess: { showPaywallFromBanner = false }
            )
        }
        .sheet(isPresented: $showGeminiChat) {
            GeminiChatSheet(
                speechManager: speechManager
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }
    
    
    @ViewBuilder
    private func buildChatScreen() -> some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let hasChatMessages = viewModel.messages.contains { !$0.content.hasPrefix("SYSTEM:") }
                            let chatMessages = hasChatMessages ? viewModel.messages.filter { !$0.content.hasPrefix("SYSTEM:") || $0.content.hasPrefix("SYSTEM: Connection established") } : []
                            
                            ForEach(chatMessages) { message in
                                if message.content.hasPrefix("SYSTEM: Connection established") {
                                    connectionDivider(for: message.content)
                                } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                        MessageBubble(message: message, enableTyping: true)
                                        if message.role == "user" && message.status == "error" {
                                            HStack(spacing: 0) {
                                                TryAgainButton { viewModel.retryMessage(messageId: message.id) }
                                                Spacer()
                                                DeleteMessageButton { viewModel.deleteMessage(messageId: message.id) }
                                            }
                                        }
                                    }
                                    .id(message.id)
                                }
                            }
                            
                            if viewModel.isAwaitingAgentReply {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                                    .padding(.top, 4)
                            }
                            
                            // Anchor to always scroll to the absolute bottom
                            Color.clear.frame(height: 1)
                                .id("bottom-anchor")
                        }
                        .padding(.bottom, 8)
                        .padding(.top, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
                        // Initial scroll to bottom when view appears
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: viewModel.isSyncing) { old, isSyncing in
                        if !isSyncing {
                            // When sync finishes, force jump to bottom
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                    .onChange(of: viewModel.messages.count) { old, count in
                        scrollToBottom(proxy: proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: MessageBubble.shouldScrollToBottom)) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    
                    // Empty State Overlay
                    let hasChatMessages = viewModel.messages.contains { !$0.content.hasPrefix("SYSTEM:") }
                    if !hasChatMessages && !viewModel.isSyncing {
                        VStack {
                            Spacer()
                            if supabaseService.isConnected {
                                buildEmptyState(workspaceName: supabaseService.connectedWorkspaceName)
                            } else {
                                buildDisconnectedEmptyState()
                            }
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                    
                    if viewModel.isSyncing {
                        loadingOverlay()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
            }
            .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                buildInputBar()
            }
        }
    }

    
    @ViewBuilder
    private func buildEmptyState(workspaceName: String?) -> some View {
        VStack(spacing: 24) {
            Image("image 1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 60)
            
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text("Ready to Build")
                        .font(.title3.bold())
                        .foregroundColor(.labelPrimary.opacity(0.9))
                    
                    if let wsName = workspaceName {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Text(wsName)
                                .font(.subheadline)
                        }
                        .foregroundColor(.labelPrimary.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.labelPrimary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Text("Send a prompt to Claude Code CLI\nto start coding")
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    @ViewBuilder
    private func buildDisconnectedEmptyState() -> some View {
        VStack(spacing: 20) {
            Image("image 1 gray")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 60)
                .opacity(0.8)
            
            VStack(spacing: 8) {
                Text(String(localized: "connection.stub.title.not_connected"))
                    .font(.title3.bold())
                    .foregroundColor(.labelPrimary.opacity(0.9))
                
                Text(String(localized: "connection.stub.subtitle.pair_devices"))
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                Analytics.track(.connectionConnectClicked)
                Task {
                    shareURL = await supabaseService.makeConnectURL()
                }
            }) {
                Text(String(localized: "connection.stub.button.share_link"))
                    .font(.subheadline.bold())
                    .foregroundColor(.labelPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }


    private func connectionDivider(for content: String) -> some View {
        let parsedName = parseWorkspaceName(from: content)
        return Group {
            if let name = parsedName {
                HStack(spacing: 12) {
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.labelSecondary.opacity(0.3))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.labelPrimary.opacity(0.8))
                            .font(.caption2)
                        Text("Connected to \(name)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.labelSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color.backgroundPrimary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.labelSecondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.labelSecondary.opacity(0.3))
                }
            } else {
                HStack(spacing: 12) {
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.labelSecondary.opacity(0.3))
                    Text("New Session Started")
                        .font(.caption2)
                        .foregroundColor(.labelSecondary.opacity(0.7))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 12)
                        .lineLimit(1)
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.labelSecondary.opacity(0.3))
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func buildInputBar() -> some View {
        let isConnected = supabaseService.isConnected
        let isBlocked = viewModel.isInputBlockedDueToLimit
        
        VStack(spacing: 0) {
            if storeManager.hasCheckedPurchases && !isSubscribed {
                SubscribeBanner(onTap: { showPaywallFromBanner = true })
            }
            Divider()
            
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    isConnected
                    ? (speechManager.isRecording ? "Listening..." : "Ask anything...")
                    : "Connect to start chatting",
                    text: $viewModel.newMessageText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)
                .disabled(!isConnected || isBlocked)
                .opacity(isConnected && !isBlocked ? 1.0 : 0.6)
                .onChange(of: speechManager.recognizedText) { old, newValue in
                    if !isBlocked && speechManager.isRecording && !newValue.isEmpty {
                        viewModel.newMessageText = newValue
                    }
                }
                
                if viewModel.isAwaitingAgentReply {
                    Button(action: {
                        viewModel.stopCurrentGeneration()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.labelPrimary, Color.semanticError)
                    }
                    .padding(.bottom, 2)
                    .disabled(!isConnected || isBlocked)
                } else if !viewModel.newMessageText.isEmpty || speechManager.isRecording {
                    Button(action: {
                        if speechManager.isRecording {
                            Analytics.track(.speechRecordingStopped(source: .main))
                            viewModel.lastInputMethod = .voice
                            speechManager.stopRecording()
                        } else {
                            viewModel.sendMessage()
                        }
                    }) {
                        Image(systemName: speechManager.isRecording ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(speechManager.isRecording ? Color.labelPrimary : Color.labelPrimary, speechManager.isRecording ? Color.semanticError : Color.brandPrimary)
                    }
                    .padding(.bottom, 2)
                    .disabled(!isConnected || isBlocked)
                } else {
                    Button(action: {
                        speechManager.requestAuthorization { authorized in
                            if authorized {
                                Analytics.track(.speechRecordingStarted(source: .main))
                                speechManager.startRecording()
                            }
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.labelPrimary)
                    }
                    .padding(.bottom, 8)
                    .disabled(!isConnected || isBlocked)
                    .opacity(isConnected && !isBlocked ? 1.0 : 0.5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.backgroundPrimary)
            .overlay {
                if !isConnected {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showConnectHint()
                        }
                }
            }
        }
        .overlay(alignment: .top) {
            if showConnectHintPopup {
                Text("Connect to IDE first")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.labelPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.backgroundPrimary.opacity(0.8)))
                    .padding(.top, -40)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onDisappear {
            connectHintDismissWorkItem?.cancel()
        }
    }
    
    @ViewBuilder
    private func loadingOverlay() -> some View {
        Color.backgroundPrimary.opacity(0.85)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(spacing: 20) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse, options: .repeating)
                    
                    Text("Syncing Connection")
                        .font(.dsTitle3)
                        .fontWeight(.semibold)
                        .foregroundColor(.labelPrimary)
                    
                    Text(viewModel.syncStatusText)
                        .font(.subheadline)
                        .foregroundColor(.labelSecondary)
                        .animation(.easeInOut, value: viewModel.syncStatusText)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        .scaleEffect(1.2)
                }
            )
            .transition(.opacity)
    }
    
    private func determineIcon() -> String {
        if speechManager.isRecording {
            return "stop.circle.fill"
        } else if viewModel.newMessageText.isEmpty {
            return "mic.circle.fill"
        } else {
            return "arrow.up.circle.fill"
        }
    }
    
    private func parseWorkspaceName(from content: String) -> String? {
        guard content.contains("workspace:") else { return nil }
        let parts = content.components(separatedBy: "workspace:")
        guard parts.count >= 2 else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }
    
    private func playAgentActivationSound() {
        guard let url = Bundle.main.url(forResource: "Puzzle Game Gentle Transition", withExtension: "mp3") else {
            return
        }
        
        do {
            if MainView.agentSoundPlayer == nil {
                MainView.agentSoundPlayer = try AVAudioPlayer(contentsOf: url)
                MainView.agentSoundPlayer?.enableRate = true
                MainView.agentSoundPlayer?.rate = 1.15
                MainView.agentSoundPlayer?.volume = 0.6
                MainView.agentSoundPlayer?.prepareToPlay()
            }
            
            MainView.agentSoundPlayer?.currentTime = 0
            MainView.agentSoundPlayer?.volume = 0.6
            MainView.agentSoundPlayer?.play()
        } catch {
            // Если по какой-то причине не получилось проиграть — просто молча игнорируем
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        func performScroll() {
            if animated {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
        
        // Initial attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            performScroll()
        }
        
        // Secondary attempt for heavy loads/initial sync to be sure
        if !animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                performScroll()
            }
        }
    }
    
    private func showConnectHint() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        connectHintDismissWorkItem?.cancel()
        
        withAnimation(.easeOut(duration: 0.15)) {
            showConnectHintPopup = true
        }
        
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) {
                showConnectHintPopup = false
            }
        }
        connectHintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

/// Полноэкранный чат с Gemini 3 Flash, открывается из кнопки Agent в навбаре.
private struct GeminiChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var speechManager: SpeechManager
    @StateObject private var viewModel = GeminiChatViewModel()
    @ObservedObject private var storeManager = StoreManager.shared
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @State private var showPaywallFromBanner = false
    @FocusState private var isInputFocused: Bool
    @State private var hasPerformedInitialScroll = false
    @State private var showGlow = false

    private var showLimitPaywallSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showPaywallForLimit && !remoteConfig.isPaywallV2Enabled },
            set: { viewModel.showPaywallForLimit = $0 }
        )
    }

    private var showLimitPaywallFullScreenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showPaywallForLimit && remoteConfig.isPaywallV2Enabled },
            set: { viewModel.showPaywallForLimit = $0 }
        )
    }

    private var showBannerPaywallSheetBinding: Binding<Bool> {
        Binding(
            get: { showPaywallFromBanner && !remoteConfig.isPaywallV2Enabled },
            set: { showPaywallFromBanner = $0 }
        )
    }

    private var showBannerPaywallFullScreenBinding: Binding<Bool> {
        Binding(
            get: { showPaywallFromBanner && remoteConfig.isPaywallV2Enabled },
            set: { showPaywallFromBanner = $0 }
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Chat
                    ScrollViewReader { proxy in
                        ZStack {
                            VStack(spacing: 0) {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(viewModel.messages) { message in
                                            VStack(alignment: .leading, spacing: 0) {
                                                MessageBubble(message: message, enableTyping: false)
                                                if message.role == "user" && message.status == "error" {
                                                    HStack(spacing: 0) {
                                                        TryAgainButton { viewModel.retryMessage(messageId: message.id) }
                                                        Spacer()
                                                        DeleteMessageButton { viewModel.deleteMessage(messageId: message.id) }
                                                    }
                                                }
                                            }
                                            .id(message.id)
                                        }
                                        
                                        if viewModel.messages.last?.role == "user",
                                           viewModel.messages.last?.status != "error" {
                                            TypingIndicatorView()
                                                .id("typing-indicator")
                                                .padding(.top, 4)
                                        }
                                    }
                                    .padding(.bottom, 8)
                                    .padding(.top, 16)
                                }
                                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                                    guard newCount > 0 else { return }

                                    let scrollAction = {
                                        if let lastId = viewModel.messages.last?.id {
                                            proxy.scrollTo(lastId, anchor: .bottom)
                                        }
                                    }

                                    if !hasPerformedInitialScroll && oldCount == 0 {
                                        hasPerformedInitialScroll = true
                                        DispatchQueue.main.async {
                                            scrollAction()
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            scrollAction()
                                        }
                                    }
                                }
                                .scrollDismissesKeyboard(.interactively)
                            }
                            
                            if viewModel.messages.isEmpty {
                                VStack(spacing: 24) {
                                    Image("claude")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 48, height: 48)
                                        .foregroundColor(.labelSecondary)
                                    
                                    VStack(spacing: 8) {
                                        Text("Ready to Think")
                                            .font(.title3.bold())
                                            .foregroundColor(.labelPrimary.opacity(0.9))
                                        
                                        Text("Ask Agent anything\nabout your code or project")
                                            .font(.subheadline)
                                            .foregroundColor(.labelSecondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 40)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isInputFocused = false
                        }
                    }
                    .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        buildInputBar()
                    }
                }
            }
            .overlay(
                ZStack {
                    // Чёткий контур по краю sheet
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.labelPrimary.opacity(0.7),
                                    Color.purple.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                    
                    // Мягкое свечение, слегка размазанное
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.labelPrimary.opacity(0.8),
                                    Color.purple.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 9
                        )
                        .blur(radius: 10)
                        .opacity(0.6)
                }
                // Чуть выводим свечение за края по горизонтали (как внизу)
                .padding(.horizontal, -2)
                .padding(.vertical, -2)
                // Всегда тянем свечение на полный экран, даже когда клавиатура поднимается
                .ignoresSafeArea(.container, edges: .all)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .blendMode(.screen)
                .opacity(showGlow ? 1 : 0)
            )
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Analytics.track(.agentChatClosed)
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.labelPrimary.opacity(0.9))
                    }
                }
            }
            .sheet(isPresented: showLimitPaywallSheetBinding, onDismiss: { viewModel.onPaywallDismissed() }) {
                PaywallLimitSheet(
                    selectedProductId: $viewModel.paywallSelectedProductId,
                    paywallSource: .limitAgent,
                    onPurchaseSuccess: {
                        viewModel.purchasedFromPaywall = true
                        viewModel.showPaywallForLimit = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: showLimitPaywallFullScreenBinding, onDismiss: { viewModel.onPaywallDismissed() }) {
                PaywallLimitSheet(
                    selectedProductId: $viewModel.paywallSelectedProductId,
                    paywallSource: .limitAgent,
                    onPurchaseSuccess: {
                        viewModel.purchasedFromPaywall = true
                        viewModel.showPaywallForLimit = false
                    }
                )
            }
            .sheet(isPresented: showBannerPaywallSheetBinding) {
                PaywallLimitSheet(
                    selectedProductId: $viewModel.paywallSelectedProductId,
                    paywallSource: .bannerAgent,
                    onPurchaseSuccess: { showPaywallFromBanner = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: showBannerPaywallFullScreenBinding) {
                PaywallLimitSheet(
                    selectedProductId: $viewModel.paywallSelectedProductId,
                    paywallSource: .bannerAgent,
                    onPurchaseSuccess: { showPaywallFromBanner = false }
                )
            }
            .onAppear {
                showGlow = false
                // Небольшая задержка, чтобы дождаться полного раскрытия sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.75)) {
                        showGlow = true
                    }
                }
            }
            .onDisappear {
                showGlow = false
            }
        }
    }
    
    @ViewBuilder
    private func buildInputBar() -> some View {
        VStack(spacing: 0) {
            if storeManager.hasCheckedPurchases && !viewModel.isSubscribed {
                SubscribeBanner(onTap: { showPaywallFromBanner = true })
            }
            Divider()
            
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    speechManager.isRecording ? "Listening..." : "Ask anything...",
                    text: $viewModel.newMessageText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)
                .onChange(of: speechManager.recognizedText) { _, newValue in
                    if speechManager.isRecording && !newValue.isEmpty {
                        viewModel.newMessageText = newValue
                    }
                }
                
                if !viewModel.newMessageText.isEmpty || speechManager.isRecording {
                    Button(action: {
                        if speechManager.isRecording {
                            Analytics.track(.speechRecordingStopped(source: .agent))
                            viewModel.lastInputMethod = .voice
                            speechManager.stopRecording()
                        } else {
                            viewModel.sendMessage()
                        }
                    }) {
                        Image(systemName: speechManager.isRecording ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(speechManager.isRecording ? Color.labelPrimary : Color.labelPrimary, speechManager.isRecording ? Color.semanticError : Color.brandPrimary)
                    }
                    .padding(.bottom, 2)
                } else {
                    Button(action: {
                        speechManager.requestAuthorization { authorized in
                            if authorized {
                                Analytics.track(.speechRecordingStarted(source: .agent))
                                speechManager.startRecording()
                            }
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.labelPrimary)
                    }
                    .padding(.bottom, 8)
                    .opacity(1.0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.backgroundPrimary)
        }
    }
}

/// Баннер над инпутом для бесплатных пользователей. По тапу открывается пейвол.
private struct SubscribeBanner: View {
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "infinity")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                Text("Subscribe for unlimited prompts")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.labelPrimary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.labelSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundPrimary)
        }
        .buttonStyle(.plain)
    }
}

/// Пейвол при достижении дневного лимита (4-я попытка отправить).
private struct PaywallLimitSheet: View {
    @Binding var selectedProductId: String
    var paywallSource: AnalyticsEvent.PaywallSource = .limitMain
    var onPurchaseSuccess: () -> Void
    
    var body: some View {
        PaywallSheetRouter(
            selectedProductId: $selectedProductId,
            subscribeButtonLabel: AppButtonLabels.subscribe,
            paywallSource: paywallSource,
            onPurchaseSuccess: onPurchaseSuccess
        )
    }
}
