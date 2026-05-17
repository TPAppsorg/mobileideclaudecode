import SwiftUI
import MarkdownUI
import Splash

struct MessageBubble: View {
    let message: ChatMessage
    let enableTyping: Bool
    
    var isUser: Bool { message.role == "user" }
    
    @State private var hasAppeared = false
    @State private var displayedContent: String = ""
    @State private var typingTask: Task<Void, Never>? = nil
    @State private var lastScrollPostTime: Date = .distantPast
    private let scrollThrottleInterval: TimeInterval = 0.08

    // Notification name to signal the parent to scroll
    static let shouldScrollToBottom = Notification.Name("MessageBubbleShouldScrollToBottom")

    /// Parsed `[thought: true] … [thought: false]` segments for the agent bubble.
    private var parsedAgentDisplay: ParsedAgentDisplay {
        AgentReasoningParser.parse(
            displayedContent.isEmpty ? " " : displayedContent,
            isStreaming: message.status == "streaming",
        )
    }

    /// `true` → main answer first, thinking below. Only when both segments exist **and** the stream had a substantive lead before the first `[thought: true]` (see parser).
    private var agentAnswerBeforeReasoning: Bool {
        guard !isUser else { return false }
        let p = parsedAgentDisplay
        let r = (p.reasoningText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let a = p.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, !a.isEmpty else { return false }
        return p.preferAnswerBeforeReasoning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isUser {
                HStack(spacing: 8) {
                    Image("image 1")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 16)
                    
                    Text("Claude Code")
                        .font(.body)
                        .foregroundColor(.labelPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            if !isUser {
                let parsed = parsedAgentDisplay
                if agentAnswerBeforeReasoning {
                    agentAnswerMarkdown(parsed: parsed)
                    agentReasoningBlock(parsed: parsed, extraTopPadding: 12)
                } else {
                    agentReasoningBlock(parsed: parsed, extraTopPadding: 6)
                    agentAnswerMarkdown(parsed: parsed)
                }
            } else {
                Markdown(displayedContent.isEmpty ? " " : displayedContent)
                    .markdownTheme(markdownTheme(muted: false))
                    .markdownCodeSyntaxHighlighter(.splash(theme: .midnight(withFont: .init(size: 14))))
                    .lineSpacing(6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.colorScheme, .dark)
            }
        }
        .background(isUser ? SwiftUI.Color.backgroundSecondary : SwiftUI.Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: isUser ? 20 : 0))
        .padding(.horizontal, isUser ? 12 : 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .offset(y: hasAppeared ? 0 : 5)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            setupInitialContent()
            withAnimation(.easeOut(duration: 0.3)) {
                hasAppeared = true
            }
        }
        .onChange(of: message.content) { old, newContent in
            if isUser || !enableTyping {
                displayedContent = newContent
            } else {
                startTyping(to: newContent)
            }
        }
    }

    @ViewBuilder
    private func agentAnswerMarkdown(parsed: ParsedAgentDisplay) -> some View {
        let answerText = parsed.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answerText.isEmpty {
            Markdown(answerText)
                .markdownTheme(markdownTheme(muted: false))
                .markdownCodeSyntaxHighlighter(.splash(theme: .midnight(withFont: .init(size: 14))))
                .lineSpacing(6)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.colorScheme, .dark)
                .transaction { txn in
                    if message.status == "streaming" { txn.animation = nil }
                }
        }
    }

    @ViewBuilder
    private func agentReasoningBlock(parsed: ParsedAgentDisplay, extraTopPadding: CGFloat) -> some View {
        if let reasoning = parsed.reasoningText, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AgentReasoningBlockView(
                markdown: reasoning,
                isStreaming: message.status == "streaming",
                theme: markdownTheme(muted: true)
            )
            // Slightly inset vs main answer so reasoning reads as nested under the reply.
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .padding(.top, extraTopPadding)
            .transaction { txn in
                if message.status == "streaming" { txn.animation = nil }
            }
        }
    }
    
    private func setupInitialContent() {
        let fullContent = message.content
        // If it's the user's message or a message from history (> 1.5s old), show instantly
        if isUser || !enableTyping || Date().timeIntervalSince(message.createdAt) > 1.5 {
            displayedContent = fullContent
        } else {
            // New agent message: clear and type from start
            displayedContent = ""
            startTyping(to: fullContent)
        }
    }
    
    private func startTyping(to fullContent: String) {
        typingTask?.cancel()
        // Long content: show instantly to avoid thousands of Markdown re-renders and UI freeze
        let instantThreshold = 600
        if fullContent.count > instantThreshold {
            displayedContent = fullContent
            NotificationCenter.default.post(name: MessageBubble.shouldScrollToBottom, object: nil)
            return
        }
        typingTask = Task {
            while displayedContent.count < fullContent.count {
                if Task.isCancelled { return }
                
                let diff = fullContent.count - displayedContent.count
                let step = diff > 300 ? 10 : (diff > 100 ? 4 : 1)
                
                let nextCount = min(displayedContent.count + step, fullContent.count)
                let nextIndex = fullContent.index(fullContent.startIndex, offsetBy: nextCount)
                let nextString = String(fullContent[..<nextIndex])
                
                await MainActor.run {
                    displayedContent = nextString
                    let now = Date()
                    let throttle = message.status == "streaming" ? 0.28 : scrollThrottleInterval
                    if now.timeIntervalSince(lastScrollPostTime) >= throttle {
                        lastScrollPostTime = now
                        NotificationCenter.default.post(name: MessageBubble.shouldScrollToBottom, object: nil)
                    }
                }
                
                let delay = diff > 100 ? 0.003 : 0.01
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    private func markdownTheme(muted: Bool) -> MarkdownUI.Theme {
        let primary: CGFloat = muted ? 0.74 : 1.0
        let paragraphTone: CGFloat = muted ? 0.64 : 0.9
        return MarkdownUI.Theme.gitHub
            .text {
                ForegroundColor(.white.opacity(primary))
                FontSize(16)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 8)
                    .foregroundColor(.white.opacity(primary))
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 20, bottom: 8)
                    .foregroundColor(.white.opacity(primary))
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 16, bottom: 4)
                    .foregroundColor(.white.opacity(primary))
            }
            .paragraph { configuration in
                configuration.label
                    .lineSpacing(6)
                    .markdownMargin(top: 8, bottom: 8)
                    .foregroundColor(.white.opacity(paragraphTone))
            }
            .code {
                ForegroundColor(.white.opacity(min(1, primary + 0.08)))
                BackgroundColor(SwiftUI.Color.white.opacity(0.1))
            }
            .codeBlock { configuration in
                VStack(alignment: .trailing, spacing: 0) {
                    Button(action: {
                        UIPasteboard.general.string = configuration.content
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        Analytics.track(.codeBlockCopied)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .padding(8)
                            .background(SwiftUI.Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .padding(6)
                    
                    configuration.label
                        .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
                        .frame(maxWidth: CGFloat.infinity, alignment: .leading)
                }
                .background(SwiftUI.Color.markdownCodeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SwiftUI.Color.markdownCodeBorder, lineWidth: 1)
                )
                .markdownMargin(top: 16, bottom: 16)
            }
            .strong {
                FontWeight(.bold)
                ForegroundColor(.white.opacity(primary))
            }
            .link {
                ForegroundColor(.blue.opacity(muted ? 0.88 : 1.0))
            }
    }
}

// MARK: - Agent thinking (e.g. `[thought: true] … [thought: false]`)

private struct AgentReasoningBlockView: View {
    private static let collapsedVisibleLineCount = 4

    /// Shared insets for the markdown column (expanded + collapsed).
    private static let bodyInsets = EdgeInsets(top: 2, leading: 2, bottom: 10, trailing: 4)

    private static let railGradient = LinearGradient(
        colors: [
            Color.secondary.opacity(0.55),
            Color.secondary.opacity(0.38),
            Color.secondary.opacity(0.28),
        ],
        startPoint: .top,
        endPoint: .bottom,
    )

    let markdown: String
    let isStreaming: Bool
    let theme: MarkdownUI.Theme

    @State private var expanded: Bool

    init(markdown: String, isStreaming: Bool, theme: MarkdownUI.Theme) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.theme = theme
        _expanded = State(initialValue: true)
    }

    /// Fixed clip box for collapsed thinking (4 lines + body insets); overflow must not paint past this.
    private static var collapsedMarkdownClipHeight: CGFloat {
        let lineH: CGFloat = 23
        return CGFloat(collapsedVisibleLineCount) * lineH + bodyInsets.top + bodyInsets.bottom
    }

    private var thinkingHeaderButton: some View {
        Button {
            // No `withAnimation` here: animating height trips the parent ScrollView (content jumps, then settles).
            expanded.toggle()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("Thinking")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer(minLength: 8)
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(Color.white.opacity(0.55))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: expanded)
            }
            .padding(.leading, Self.bodyInsets.leading)
            .padding(.trailing, Self.bodyInsets.trailing)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Self.railGradient)
                .frame(width: 3)
                .padding(.vertical, 2)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 0) {
                thinkingHeaderButton
                if expanded {
                    Markdown(markdown)
                        .markdownTheme(theme)
                        .markdownCodeSyntaxHighlighter(.splash(theme: .midnight(withFont: .init(size: 13))))
                        .lineSpacing(5)
                        .padding(Self.bodyInsets)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.colorScheme, .dark)
                        .transaction { txn in
                            if isStreaming { txn.animation = nil }
                        }
                } else {
                    Button {
                        expanded = true
                    } label: {
                        Markdown(markdown)
                            .markdownTheme(theme)
                            .markdownCodeSyntaxHighlighter(.splash(theme: .midnight(withFont: .init(size: 13))))
                            .lineSpacing(5)
                            .padding(Self.bodyInsets)
                            .lineLimit(Self.collapsedVisibleLineCount)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(height: Self.collapsedMarkdownClipHeight, alignment: .top)
                            .clipped()
                            .environment(\.colorScheme, .dark)
                            .transaction { txn in
                                if isStreaming { txn.animation = nil }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(nil, value: expanded)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transaction { $0.animation = nil }
    }
}
