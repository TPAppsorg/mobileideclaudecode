import SwiftUI
import MarkdownUI
import SafariServices

struct MenuView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var supabase = SupabaseService.shared
    @State private var showingClearHistoryAlert = false
    @State private var showingSupportEmailFallback = false
    @State private var showingRateAppSheet = false
    @ObservedObject var viewModel: MainViewModel
    var onInsertPrompt: ((String) -> Void)? = nil
    
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Prompt Book") {
                    NavigationLink(destination: PromptBookDetailView(title: "Prompts", onInsertPrompt: onInsertPrompt, onCloseModal: { dismiss() })
                        .onAppear { Analytics.track(.promptBookOpened(section: "Prompts")) }
                    ) {
                        PromptBookRow(
                            title: "Prompts",
                            subtitle: "Curated prompts for devs",
                            systemImage: "text.bubble.fill",
                            color: .brandPrimary
                        )
                    }
                    NavigationLink(destination: PromptBookDetailView(title: "Tips & Tricks", onCloseModal: { dismiss() })
                        .onAppear { Analytics.track(.promptBookOpened(section: "Tips & Tricks")) }
                    ) {
                        PromptBookRow(
                            title: "Tips & Tricks",
                            subtitle: "Learn how to hack Claude Code Mobile",
                            systemImage: "lightbulb.fill",
                            color: .brandPrimary
                        )
                    }
                    NavigationLink(destination: PromptBookDetailView(title: "Plugins", onCloseModal: { dismiss() })
                        .onAppear { Analytics.track(.promptBookOpened(section: "Plugins")) }
                    ) {
                        PromptBookRow(
                            title: "Plugins",
                            subtitle: "Extend Claude Code with tools",
                            systemImage: "puzzlepiece.extension.fill",
                            color: .brandPrimary
                        )
                    }
                }
                
                Section("Support") {
                    Button(action: requestAppReview) {
                        HStack {
                            SettingsLabel(title: "Rate Us", systemImage: "star.fill", color: .brandPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.labelSecondary)
                        }
                        .foregroundColor(.labelPrimary)
                    }
                    Button(action: openSupportEmail) {
                        HStack {
                            SettingsLabel(title: "Contact Us", systemImage: "envelope.fill", color: .brandPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.labelSecondary)
                        }
                        .foregroundColor(.labelPrimary)
                    }
                }

                Section("Info") {
                    NavigationLink(destination: SafariView(url: URL(string: AppLegalLinks.termsOfUse)!)
                        .onAppear { Analytics.track(.settingsLinkTapped(link: "terms")) }
                    ) {
                        SettingsLabel(title: "Terms of Use", systemImage: "doc.text.fill", color: .brandPrimary)
                    }

                    NavigationLink(destination: SafariView(url: URL(string: AppLegalLinks.privacyPolicy)!)
                        .onAppear { Analytics.track(.settingsLinkTapped(link: "privacy")) }
                    ) {
                        SettingsLabel(title: "Privacy Policy", systemImage: "shield.fill", color: .brandPrimary)
                    }

                    HStack {
                        SettingsLabel(title: "Version", systemImage: "info.circle.fill", color: .labelSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.labelSecondary)
                    }
                }
                
                Section {
                    Button(role: .destructive, action: { showingClearHistoryAlert = true }) {
                        Text("Clear Chat History")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.labelPrimary)
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearHistoryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    viewModel.clearHistory()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to clear all chat history? This action cannot be undone.")
            }
            .alert("Contact Support", isPresented: $showingSupportEmailFallback) {
                Button("Copy Email") {
                    UIPasteboard.general.string = "support@luch.dev"
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Mail app is not available. Email us at support@luch.dev or copy the address.")
            }
            .sheet(isPresented: $showingRateAppSheet) {
                RateAppView(source: "menu_rate_us")
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
        .task {
            _ = await supabase.signInAnonymouslyIfNeeded()
        }
    }
    
    private func requestAppReview() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Analytics.track(.settingsLinkTapped(link: "rate_us"))
        showingRateAppSheet = true
    }
    
    private func openSupportEmail() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Analytics.track(.settingsLinkTapped(link: "contact_us"))
        guard let url = URL(string: "mailto:support@luch.dev") else { return }
        UIApplication.shared.open(url) { opened in
            if !opened {
                DispatchQueue.main.async { showingSupportEmailFallback = true }
            }
        }
    }
}

struct PromptBookRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .foregroundColor(.labelPrimary)
                    .font(.system(size: 20, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsHeadline)
                    .foregroundColor(.labelPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Prompts detail (content from screenshots, app-native style)

private struct PromptItem: Identifiable {
    let id = UUID()
    let sectionTitle: String
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let tags: [(label: String, color: Color)]
    let promptBody: String
}

private let promptSectionOrder = ["Architecture", "Backend", "Documentation", "Frontend", "Mobile", "Quality & Testing", "Refactoring & Code"]

private let codeReviewExpertPromptBody = """
Please review my code with a focus on:

1. Code quality and readability
2. Potential bugs or edge cases
3. Performance optimizations
4. Security vulnerabilities
5. Best practices and design patterns

For each issue found, explain why it's a problem and suggest a specific fix.
"""

private let microserviceBoundariesPromptBody = """
Analyze this codebase and define clear boundaries between services (or modules). For each boundary:

1. List what belongs inside vs outside
2. Specify the contract (APIs, events, or data shapes) at the boundary
3. Suggest concrete changes to avoid tight coupling and hidden dependencies
4. Call out any shared code that should stay minimal and stable

Output: a short boundary map plus actionable refactor steps.
"""

private let dependencyInjectionPromptBody = """
Refactor this code to use clean dependency injection:

1. Identify every external dependency (DB, APIs, config, time, etc.)
2. Introduce interfaces/abstractions and inject them via constructor or DI container
3. Remove direct instantiation and static calls; make dependencies explicit and testable
4. Keep the same public behavior; only change how dependencies are provided

Show the updated code and a brief note on how to unit test the main flow.
"""

private let architectureDecisionRecordPromptBody = """
Draft an Architecture Decision Record (ADR) for the decision visible in this code or context. Include:

1. Title and short context (what forces the decision)
2. Decision (what we decided)
3. Consequences (trade-offs, what we gain and give up)
4. Alternatives considered and why they were rejected

Use a clear, scannable format. One ADR per decision.
"""

private let stateManagementSetupPromptBody = """
Propose a minimal, scalable state management setup for this app (or the described screen):

1. What state is global vs local; what should be persisted
2. Recommended approach (e.g. single store, context, signals) with one-sentence rationale
3. Concrete file/module structure and where state lives
4. One example: reading state and one example: updating state (with code)

Keep it simple and easy to extend later.
"""

private let designPatternAdvisorPromptBody = """
For this code (or the described problem), recommend the most appropriate design pattern(s):

1. Name the pattern(s) and in one sentence why they fit
2. Sketch the structure (main types and their roles)
3. List one clear benefit and one caveat
4. Suggest a minimal refactor: what to extract, rename, or introduce first

Avoid over-engineering; prefer the smallest change that improves clarity and testability.
"""

private let databaseQueryOptimizerPromptBody = """
Review these database queries (or the code that runs them) and optimize for correctness and performance:

1. Point out N+1 queries, missing indexes, or unnecessary data fetched
2. Suggest specific index(es) and query changes (with example SQL or ORM code)
3. Note any transaction boundaries or locking concerns
4. If applicable, suggest caching or read-model strategies

Keep the same behavior; only improve efficiency and safety.
"""

private let errorHandlingStrategyPromptBody = """
Design a consistent error-handling and logging strategy for this codebase:

1. Define error types/codes and who handles what (domain vs infrastructure vs UI)
2. Where to log (which layer, which level: debug/info/warn/error) and what to include
3. Replace ad-hoc try/catch or silent failures with explicit handling and user-facing messages
4. Show one example end-to-end: error raised → logged → surfaced to user

Keep logging structured and avoid leaking sensitive data.
"""

private let apiSecurityHardeningPromptBody = """
Audit this API (or the code that exposes it) for security and harden it:

1. Authentication and authorization: who can call what; how tokens/sessions are validated
2. Input validation and sanitization for all user-controlled inputs
3. Rate limiting, CORS, and safe defaults for headers and error responses
4. Any sensitive data in logs or responses; recommend fixes

List findings by severity and provide concrete code or config changes.
"""

private let restApiEndpointPromptBody = """
Implement a complete REST endpoint for the described resource. Include:

1. Route, method(s), and idempotency where relevant
2. Request validation (body, query, path) with clear error responses
3. One success response shape (JSON) and status codes (200/201/204, 400, 404, 5xx)
4. Short doc comment or OpenAPI-style summary

Use the stack and conventions of the current project.
"""

private let readmeGeneratorPromptBody = """
Generate a professional README for this project. Include:

1. One-line description and 2–3 sentence overview
2. Prerequisites and how to run (install, env vars, commands)
3. Main features or modules (bullets)
4. How to test and how to contribute (brief)
5. License line if applicable

Use the repo structure and tech stack you see; keep it accurate and scannable.
"""

private let apiDocumentationPromptBody = """
Generate clear API documentation for the code or spec I provide. For each endpoint (or function):

1. Purpose in one sentence
2. Parameters/request body and types
3. Response shape and status codes
4. Example request and response (curl or JSON)
5. Errors and edge cases

Output in a consistent, copy-paste friendly format (e.g. Markdown or OpenAPI snippet).
"""

private let addComprehensiveCommentsPromptBody = """
Add concise, helpful comments to this code:

1. Module/file: one line on what it does and when to use it
2. Public functions: purpose, parameters, return value, and one example if non-obvious
3. Complex logic: short “why” or algorithm note, not a restatement of the code
4. No comments for trivial getters or self-explanatory names

Preserve style and formatting; only add comments that would help the next developer.
"""

private let reactComponentBuilderPromptBody = """
Create a well-structured React component that matches this description or design:

1. Clear props interface and sensible defaults
2. Use hooks (useState, useEffect, etc.) only where needed; keep side effects explicit
3. Accessible markup (semantic HTML, ARIA if needed) and one focus path
4. One or two lines on how to use it (e.g. example JSX)

Prefer function components and the project’s existing patterns (e.g. CSS modules, Tailwind).
"""

private let cssToTailwindPromptBody = """
Convert this CSS (or these styled components) to Tailwind utility classes:

1. Preserve layout, spacing, typography, and colors exactly
2. Use Tailwind’s design tokens (e.g. spacing scale, colors); avoid arbitrary values unless necessary
3. For repeated patterns, suggest a single @apply component or a short custom class only if it improves readability
4. Keep the HTML/JSX structure; only change class names and remove obsolete CSS

Output the updated markup and, if needed, a minimal custom CSS snippet.
"""

private let accessibilityAuditPromptBody = """
Audit this UI code for accessibility and fix issues:

1. Keyboard: all interactive elements focusable and in a logical order; no focus traps
2. Screen readers: semantic structure (headings, landmarks, labels); images and icons have alt/text
3. Color and contrast: no information by color alone; contrast ratios meet WCAG AA where applicable
4. Focus and motion: visible focus ring; reduce or respect prefers-reduced-motion if needed

List findings and provide the exact code changes.
"""

private let swiftuiViewBuilderPromptBody = """
Build a polished SwiftUI view that matches this description or design:

1. Use appropriate layout (VStack/HStack/Grid) and spacing; support dynamic type and rotation
2. Add one or two subtle animations (e.g. on appear, state change) using withAnimation or animation modifier
3. Extract subviews where it improves readability; keep the main view body short
4. Use system colors and fonts; support light/dark and accessibility

Provide the full view code and a one-line usage note.
"""

private let iosPerformanceDebugPromptBody = """
Analyze this iOS/Swift code for performance issues and suggest fixes:

1. Identify main-thread work that could block UI (heavy computation, sync I/O, large allocations)
2. Point out retain cycles, unnecessary copies, or expensive operations in hot paths
3. Suggest concrete changes: async/await, background queues, lazy loading, caching, or algorithm improvements
4. If relevant, mention instruments or metrics to verify the fix

Keep behavior the same; only improve responsiveness and efficiency.
"""

private let kotlinCoroutinesSetupPromptBody = """
Refactor this Kotlin code to use coroutines and Flow correctly:

1. Replace callbacks or blocking calls with suspend functions and coroutineScope where appropriate
2. Choose the right dispatcher (Main, IO, Default) and structured concurrency (viewModelScope, etc.)
3. Expose streams as Flow; handle cancellation and errors (try/catch, catch operator)
4. Keep the same behavior and APIs; only change concurrency model

Show the updated code and a brief note on how to unit test the flow.
"""

private let unitTestGeneratorPromptBody = """
Generate focused unit tests for this code:

1. Cover the main success path and 2–3 important edge cases or error cases
2. Use the project’s test framework and conventions; mock external dependencies
3. One test per behavior; clear names (e.g. `givenX_whenY_thenZ`)
4. Avoid testing implementation details; assert on observable outcomes

Provide the test code and a one-line summary of what is covered.
"""

private let integrationTestSuitePromptBody = """
Design and sketch integration tests for these API endpoints (or the described API):

1. For each critical endpoint: happy path, validation errors, auth/permission failures
2. Use the project’s HTTP/test setup; use real DB or a test container if appropriate
3. Keep tests independent (clean DB or rollback); avoid shared mutable state
4. One example full test (request → assert status and body)

List the scenarios and provide at least one complete test as a template.
"""

private let bugInvestigationPromptBody = """
Help me debug this issue systematically:

1. Summarize the observed behavior vs expected behavior and the steps to reproduce
2. Propose 2–3 likely causes (e.g. state, timing, input, environment) and how to verify each
3. Suggest minimal logs, breakpoints, or assertions to add to narrow it down
4. Recommend a fix and a simple regression check (test or manual step)

Assume I can run code and inspect state; focus on a clear, repeatable process.
"""

private let explainLikeJuniorPromptBody = """
Explain this code so a junior developer can understand and maintain it:

1. What problem it solves and where it fits in the bigger picture
2. Walk through the main flow step by step in plain language
3. Call out non-obvious decisions, gotchas, and dependencies
4. Give one or two short examples of how to use or extend it

Keep explanations concise; use analogies or diagrams (ASCII) only if they help.
"""

private let optimizeThisCodePromptBody = """
Improve this code for performance, readability, and maintainability without changing behavior:

1. Performance: unnecessary work, allocations, or complexity; suggest concrete optimizations
2. Readability: naming, structure, and comments; reduce nesting and magic values
3. Maintainability: duplication, coupling, and testability; suggest small refactors
4. For each change, state the benefit in one line

Output the refactored code and a short bullet list of what you changed and why.
"""

private let convertToModernSyntaxPromptBody = """
Update this legacy code to modern language and library features:

1. Replace deprecated APIs and old idioms with current best practices
2. Use modern syntax (e.g. pattern matching, async/await, collection APIs) where it clearly improves clarity or safety
3. Keep the same public behavior and avoid unnecessary structural changes
4. List the replacements in a short summary (e.g. “X → Y for Z”)

Provide the updated code and the summary.
"""

private let promptsList: [PromptItem] = [
    .init(sectionTitle: "Architecture", title: "Microservice Boundaries", subtitle: "Define clean boundaries between services", systemImage: "point.3.connected.trianglepath.dotted", iconColor: .brandPrimary, tags: [("Architecture", .brandPrimary), ("Backend", .brandPrimary)], promptBody: microserviceBoundariesPromptBody),
    .init(sectionTitle: "Architecture", title: "Dependency Injection Setup", subtitle: "Implement clean dependency injection", systemImage: "syringe", iconColor: .brandPrimary, tags: [("Architecture", .brandPrimary), ("Refactoring", .brandPrimary)], promptBody: dependencyInjectionPromptBody),
    .init(sectionTitle: "Architecture", title: "Architecture Decision Record", subtitle: "Document architectural decisions and rationale", systemImage: "doc.badge.gearshape", iconColor: .brandPrimary, tags: [("Documentation", .brandPrimary), ("Architecture", .brandPrimary)], promptBody: architectureDecisionRecordPromptBody),
    .init(sectionTitle: "Architecture", title: "State Management Setup", subtitle: "Implement proper state management for your app", systemImage: "square.stack.3d.up", iconColor: .brandPrimary, tags: [("Frontend", .brandPrimary), ("Architecture", .brandPrimary)], promptBody: stateManagementSetupPromptBody),
    .init(sectionTitle: "Architecture", title: "Design Pattern Advisor", subtitle: "Get recommendations for appropriate design patterns", systemImage: "cube.transparent", iconColor: .brandPrimary, tags: [("Architecture", .brandPrimary), ("Refactoring", .brandPrimary)], promptBody: designPatternAdvisorPromptBody),
    .init(sectionTitle: "Backend", title: "Database Query Optimizer", subtitle: "Optimize database queries for better performance", systemImage: "cylinder", iconColor: .brandPrimary, tags: [("Backend", .brandPrimary), ("Refactoring", .brandPrimary)], promptBody: databaseQueryOptimizerPromptBody),
    .init(sectionTitle: "Backend", title: "Error Handling Strategy", subtitle: "Implement robust error handling and logging", systemImage: "exclamationmark.triangle", iconColor: .brandPrimary, tags: [("Backend", .brandPrimary), ("Universal", .brandPrimary)], promptBody: errorHandlingStrategyPromptBody),
    .init(sectionTitle: "Backend", title: "API Security Hardening", subtitle: "Review and improve API security measures", systemImage: "lock.shield", iconColor: .brandPrimary, tags: [("Backend", .brandPrimary), ("QA", .brandPrimary)], promptBody: apiSecurityHardeningPromptBody),
    .init(sectionTitle: "Backend", title: "REST API Endpoint", subtitle: "Create a complete REST API endpoint with validation", systemImage: "doc.text", iconColor: .brandPrimary, tags: [("Backend", .brandPrimary)], promptBody: restApiEndpointPromptBody),
    .init(sectionTitle: "Documentation", title: "README Generator", subtitle: "Create a professional README for your project", systemImage: "doc.text", iconColor: .brandPrimary, tags: [("Documentation", .brandPrimary)], promptBody: readmeGeneratorPromptBody),
    .init(sectionTitle: "Documentation", title: "API Documentation", subtitle: "Generate complete API documentation", systemImage: "book", iconColor: .brandPrimary, tags: [("Documentation", .brandPrimary), ("Backend", .brandPrimary)], promptBody: apiDocumentationPromptBody),
    .init(sectionTitle: "Documentation", title: "Add Comprehensive Comments", subtitle: "Document code with clear, helpful comments", systemImage: "text.insert", iconColor: .brandPrimary, tags: [("Universal", .brandPrimary), ("Documentation", .brandPrimary)], promptBody: addComprehensiveCommentsPromptBody),
    .init(sectionTitle: "Frontend", title: "React Component Builder", subtitle: "Create a well-structured React component with hooks", systemImage: "gearshape.2", iconColor: .brandPrimary, tags: [("Frontend", .brandPrimary)], promptBody: reactComponentBuilderPromptBody),
    .init(sectionTitle: "Frontend", title: "CSS to Tailwind", subtitle: "Convert traditional CSS to Tailwind utility classes", systemImage: "paintbrush", iconColor: .brandPrimary, tags: [("Frontend", .brandPrimary)], promptBody: cssToTailwindPromptBody),
    .init(sectionTitle: "Frontend", title: "Accessibility Audit", subtitle: "Check and fix accessibility issues in UI code", systemImage: "person.crop.circle.badge.checkmark", iconColor: .brandPrimary, tags: [("Frontend", .brandPrimary), ("QA", .brandPrimary)], promptBody: accessibilityAuditPromptBody),
    .init(sectionTitle: "Mobile", title: "SwiftUI View Builder", subtitle: "Create a polished SwiftUI view with animations", systemImage: "square.grid.2x2", iconColor: .brandPrimary, tags: [("Mobile", .brandPrimary), ("Frontend", .brandPrimary)], promptBody: swiftuiViewBuilderPromptBody),
    .init(sectionTitle: "Mobile", title: "iOS Performance Debug", subtitle: "Find and fix performance issues in iOS code", systemImage: "speedometer", iconColor: .brandPrimary, tags: [("Mobile", .brandPrimary)], promptBody: iosPerformanceDebugPromptBody),
    .init(sectionTitle: "Mobile", title: "Kotlin Coroutines Setup", subtitle: "Implement proper coroutines and flow patterns", systemImage: "point.3.connected.trianglepath.dotted", iconColor: .brandPrimary, tags: [("Mobile", .brandPrimary), ("Backend", .brandPrimary)], promptBody: kotlinCoroutinesSetupPromptBody),
    .init(sectionTitle: "Quality & Testing", title: "Code Review Expert", subtitle: "Thorough code review with best practices", systemImage: "eye", iconColor: .brandPrimary, tags: [("Universal", .brandPrimary), ("QA", .brandPrimary)], promptBody: codeReviewExpertPromptBody),
    .init(sectionTitle: "Quality & Testing", title: "Unit Test Generator", subtitle: "Generate comprehensive unit tests for your code", systemImage: "checkmark.circle.badge.questionmark", iconColor: .brandPrimary, tags: [("QA", .brandPrimary)], promptBody: unitTestGeneratorPromptBody),
    .init(sectionTitle: "Quality & Testing", title: "Integration Test Suite", subtitle: "Create integration tests for API endpoints", systemImage: "server.rack", iconColor: .brandPrimary, tags: [("QA", .brandPrimary), ("Backend", .brandPrimary)], promptBody: integrationTestSuitePromptBody),
    .init(sectionTitle: "Quality & Testing", title: "Bug Investigation", subtitle: "Systematic approach to finding and fixing bugs", systemImage: "ladybug", iconColor: .brandPrimary, tags: [("Debugging", .red), ("QA", .brandPrimary)], promptBody: bugInvestigationPromptBody),
    .init(sectionTitle: "Refactoring & Code", title: "Explain Like I'm Junior", subtitle: "Clear explanations with examples for complex code", systemImage: "lightbulb.fill", iconColor: .brandPrimary, tags: [("Universal", .brandPrimary), ("Documentation", .brandPrimary)], promptBody: explainLikeJuniorPromptBody),
    .init(sectionTitle: "Refactoring & Code", title: "Optimize This Code", subtitle: "Improve performance, readability, and maintainability", systemImage: "bolt.fill", iconColor: .brandPrimary, tags: [("Universal", .brandPrimary), ("Refactoring", .brandPrimary)], promptBody: optimizeThisCodePromptBody),
    .init(sectionTitle: "Refactoring & Code", title: "Convert to Modern Syntax", subtitle: "Update legacy code to use modern language features", systemImage: "arrow.triangle.2.circlepath", iconColor: .brandPrimary, tags: [("Universal", .brandPrimary), ("Refactoring", .brandPrimary)], promptBody: convertToModernSyntaxPromptBody),
]

// MARK: - Tips & Tricks (content from screenshots, native style)

private struct TipItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let durationMinutes: Int
    let systemImage: String
    let iconColor: Color
    let bodyMarkdown: String
}

private struct TipsSection: Identifiable {
    let id = UUID()
    let sectionTitle: String
    let sectionImage: String
    let sectionColor: Color
    let items: [TipItem]
}

// MARK: - Tip articles (expanded, practical, markdown)

private let tipArticleWhatIsClaudeCodeMobile = """
Claude Code Mobile is an **AI-powered coding assistant** that bridges your phone and **Claude Code CLI** on your computer. You write prompts on the go; Claude executes them in your project directory, so you can capture ideas anywhere.

**What problem it solves**

Many ideas hit when you’re not in front of the computer: on the commute, between meetings, or right before sleep. Claude Code Mobile lets you:

- **Capture prompts from your phone** — no need to wait until you’re at the machine.
- **Keep one conversation** — the app and IDE share the same thread, so you can start on mobile and continue on desktop.
- **Use the Prompt Book** — curated prompts for code review, refactoring, docs, and more, one tap to paste and send.

**How it works end-to-end**

1. **Install Claude Code CLI** on your computer: `curl -fsSL https://claude.ai/install.sh | bash`
2. **Run the bridge**: `npx @uladluch/claudecodemobile-bridge@latest` in your project directory.
3. **Connect from this app** — tap Connect, open the link on your computer, and the bridge pairs automatically.

**When it shines**

- **Async workflow**: Queue a “review this module” or “add tests for X” from your phone; Claude executes immediately.
- **Quick iterations**: Paste a Prompt Book template (e.g. “Code Review Expert”), add a line like “focus on `src/auth/`,” and send.
- **Full project context**: Claude Code CLI runs in your project directory and can read/write files directly.

You stay in one flow: think on mobile, code on desktop.
"""

private let tipArticleSettingUpWorkspace = """
A correct setup takes a few minutes and avoids most "nothing happens" issues. Follow these steps in order.

**Step 1: Install Claude Code CLI**

- Open **Terminal** on your computer.
- Run: `curl -fsSL https://claude.ai/install.sh | bash`
- Verify it’s installed: `claude --version`
- If you haven’t logged in yet, run `claude` and follow the authentication prompts.

**Step 2: Start the Claude Code Mobile Bridge**

- Navigate to your project directory: `cd /path/to/your/project`
- Run: `npx @uladluch/claudecodemobile-bridge@latest`
- The bridge will start and display a pairing URL.

**Step 3: Connect from the app**

- On your phone, open **Claude Code Mobile** and tap **Connect** (or "Share Link").
- Open the link on your computer — the bridge will pair automatically.
- After a short handshake, the app should show a "Connected" state with your project name.

**Step 4: Confirm with a test prompt**

- In the app, send a simple message, e.g. "Hello" or "List files in this directory."
- Claude Code CLI will execute it in your project and send the result back.

**Troubleshooting**

- **"Can’t connect"**: Make sure the bridge is running and your phone is on the same network.
- **No response**: Check that Claude Code CLI is authenticated. Also check the bridge terminal output for errors.
- **Bridge not found**: Install it globally with `npm i -g claudecodemobile-bridge` or use `npx`.
"""

private let tipArticleYourFirstPrompt = """
Your first prompt is the best way to see the full loop: app → bridge → Claude Code CLI → you.

**Send a prompt from the app**

1. Open the **chat** screen in **Claude Code Mobile** (the main conversation view).
2. Type a concrete request. Good first prompts:
   - "List all files in this project."
   - "List three potential bugs in `src/index.ts`."
   - "Create a README for this project."
3. Tap **Send**. The prompt is sent to the bridge on your computer.
4. Claude Code CLI executes the prompt in your project directory and sends the result back to the app.

**Continue the conversation**

- Send follow-up messages from the app. Claude resumes the session automatically, so it remembers context.
- Use this to iterate: "Make it more concise," "Use our logging helper instead," "Add a unit test for that."

**Use the Prompt Book for a strong first run**

- In **Claude Code Mobile**, open **More → Prompt Book → Prompts**, pick a template (e.g. **Code Review Expert**), then tap **Use in Claude Code**.
- The template is pasted into the chat; add one line if needed (e.g. "Focus on `src/utils/`") and send.
- You get a structured, high-quality response because the prompt is already optimized.
"""

private let tipArticleWritingClearPrompts = """
Clear prompts get **better, more relevant answers** and fewer follow-up rounds. These rules work for both quick questions and larger tasks.

**One main ask per message**

- Prefer a single goal: “Add error handling to this function” instead of “Fix this, add tests, document it, and optimize.”
- If you have multiple steps, **number them**: “1) Validate the input. 2) Return 400 with a clear message. 3) Log the error.” The model can follow the list and you can refer to steps in follow-ups.

**Be specific about location and outcome**

- **Where**: Name the file, function, or area. For example: “In `api/users.ts`, in the `createUser` handler, add validation for the email field.”
- **What**: Describe the desired outcome. “Return 400 with body `{ \"error\": \"Invalid email\" }`” is better than “handle invalid email.”
- **How (if it matters)**: “Use our existing `validateEmail` helper” or “Follow the same pattern as in `OrderService`.”

**Give minimal but useful context**

- One sentence on stack or style often helps: “This is a REST handler in Express” or “We use React 18 and functional components with hooks.”
- Mention constraints: “Keep it under 20 lines” or “Don’t add new dependencies.”
- Avoid pasting huge files unless the AI must see them; prefer “in the open file” or “in `src/auth/login.ts`” and let the IDE provide context when possible.

**Examples of clear vs vague**

- Vague: “Make this better.”  
  Clear: “Refactor this function to use early returns and add a short comment above each logical block.”

- Vague: “Fix the bug.”  
  Clear: “In `processOrder`, when `items` is empty we currently throw; instead return a 400 with message ‘At least one item required’ and add a unit test for that case.”

The more precise the prompt, the less back-and-forth you need.
"""

private let tipArticleUsingContextEffectively = """
The AI’s answers are only as good as the **context** it has. Here’s how to give it the right information without overwhelming it.

**Point to the right place in the codebase**

- **Name files and symbols**: “In `src/auth/session.ts`” or “in the `validateToken` function” focuses the model.
- **Use the IDE’s context**: Having the relevant file or selection open often sends that context automatically. So “improve the selected function” or “explain the open file” can work with no extra pasting.
- **Reference other code**: “Same pattern as in `OrderService.create`” or “mirror the structure of `UserRepository`” helps the model stay consistent.

**Explain stack and conventions in one line**

- **Stack**: “We use SwiftUI and async/await” or “This is a Next.js 14 app with App Router.”
- **Style**: “We prefer guard for early returns” or “We use Tailwind and avoid inline styles.”
- **Conventions**: “We use MCP X for internal docs” or “Never log PII.” One sentence is enough for most answers to align with your project.

**Add context inside the prompt when needed**

- When the AI can’t see a file: “Our API returns `{ data, error }`; always check `error` before using `data`.”
- When you want a specific style: “Follow our ADR format: Context, Decision, Consequences.”
- When you’re iterating: “Last time you suggested X; we went with Y because of Z. Now add …”

**What to avoid**

- Don’t paste entire files “just in case” unless the task really needs them; prefer “in the open file” or a short snippet.
- Don’t assume the model remembers an old conversation forever; for a new session, restate key constraints in the first message if they matter.

The more precise and minimal the context, the better the model can focus and the less noise you get in the answer.
"""

private let tipArticleChoosingRightPrompt = """
Different tasks need different **prompt shapes**: short and direct vs structured and detailed. Matching the style to the task saves time and improves results.

**Quick questions (one sentence)**

- **Use when**: You need an explanation, a quick fix, or a yes/no. Examples: “What does this function do?”, “Why might this crash when `input` is null?”, “Is this the right hook for this case?”
- **Style**: One clear sentence. No need for a long preamble; the IDE often provides the code context.
- **Follow-up**: If the answer is off, add one constraint: “We’re on React 18” or “Assume the file is already open.”

**Structured tasks (checklist or template)**

- **Use when**: Code review, refactor, add tests, write docs, or any task with several expected parts.
- **Style**: Use a **Prompt Book** template (e.g. Code Review Expert, Unit Test Generator). They already define the structure (e.g. “focus on 1) quality 2) bugs 3) performance …”). You only add the target: “Focus on `src/auth/`” or “For `UserService.ts`.”
- **Why it works**: The model gets a clear checklist and outputs in a predictable format; you spend less time re-asking.

**Open-ended or exploratory (short paragraph)**

- **Use when**: You want design ideas, architecture options, or “what could we do here?”
- **Style**: One or two sentences that set the goal and scope. “Suggest a design for rate-limiting this API that works with our current auth. Prefer a simple solution first.”
- **Follow-up**: Use the first reply to narrow: “Option 2 looks good; implement it for the `/users` route only.”

**Rule of thumb**

- **One sentence** for quick help; **a template or short list** for bigger, repeatable tasks. Start small; add detail only if the first reply isn’t enough.
"""

private let tipArticleWhatAreMCPs = """
**MCP (Model Context Protocol)** is a way to give the AI **extra tools and data** beyond the current file or chat. Instead of only reasoning over what you paste, the model can call servers that read docs, run searches, query APIs, or even run tools in your environment.

**What it does**

- **MCP servers** expose capabilities (e.g. “search the codebase,” “fetch from our wiki,” “run this CLI”). They run locally or in your network.
- The **IDE or Claude Code Mobile's backend** connects to these servers. When you ask something like “What’s our deployment process?”, the model can call the “docs” MCP to fetch the real runbook instead of guessing.

**Why it matters**

- **Up-to-date answers**: The AI can use current docs, latest dependencies, or live API responses instead of outdated training data.
- **Your workflow**: MCPs can reflect your internal tools (builds, deploys, feature flags), so the AI’s suggestions stay aligned with how you actually work.
- **Less copy-paste**: You don’t have to paste huge docs or search results; the model pulls what it needs via MCP.

**In practice**

- **Enable MCPs** your team or IDE suggests (e.g. filesystem, documentation, search). Check your IDE’s or Claude Code Mobile’s settings for “MCP” or “Integrations.”
- **Then ask naturally**: “Summarize our API docs for auth,” “What did the last deploy change?,” “Where do we use this library?” The model will use the right MCP when it’s available.
- **Custom MCPs**: Teams can add their own (e.g. internal APIs, ticket systems). Ask your lead or check the docs for how to register a new server.

MCPs turn the AI from “smart about general code” into “smart about **your** code and **your** tools.”
"""

private let tipArticleEssentialMCPs = """
These MCPs are commonly useful in day-to-day development. Enable the ones that match your workflow; add more as you see the need.

**Filesystem / workspace**

- **What**: Read (and sometimes write) files in your project.
- **Why**: The model can “see” more than the current file. Prompts like “Add a test file for this module,” “Change all usages of X to Y,” or “What does this module import?” become accurate without pasting whole trees.
- **Tip**: If your IDE already sends open files or selection, this MCP complements that by allowing the model to open other files as needed.

**Documentation**

- **What**: Connects to your wiki, Notion, Confluence, or internal docs.
- **Why**: “What’s our policy for …?”, “How do we configure …?”, “What’s the runbook for …?” get answers from real docs instead of generic advice.
- **Tip**: Configure it to point at the docs your team actually uses; then reference them in prompts (“per our internal docs”) so the model knows to use the MCP.

**Search (code or web)**

- **What**: Full-text or semantic search over the repo, or web search.
- **Why**: “Find where we use this API,” “Latest best practice for X in 2024,” “Who calls this function?” become one prompt instead of manual grep or Google.
- **Tip**: For code search, the model can suggest exact files and symbols; for web, it can cite and summarize.

**Custom / team MCPs**

- **What**: Your team’s own servers (builds, deploys, feature flags, ticket system).
- **Why**: “What’s the status of the last deploy?”, “Which features are behind the beta flag?”, “Create a ticket for this bug” can be done via prompt once the MCP is wired.
- **Tip**: Ask your lead or check the IDE’s MCP list. Start with one or two; add more as you see repeated manual steps the AI could do via MCP.
"""

private let tipArticleCursorRulesFiles = """
**Claude Code CLI** supports project-level instructions via a `CLAUDE.md` file in your project root. This tells Claude Code how to behave in **this** project.

**What to put in**

- **Tech stack and versions**: "Swift 5.9, SwiftUI only." "React 18 with Next.js 14."
- **Style**: "Use guard for early returns." "Prefer explicit types."
- **Conventions**: "Never log secrets or PII." "All errors use our `ApiError` type."
- **Don’ts**: "Don’t add new dependencies without discussing."

**Where it applies**

- The `CLAUDE.md` file in your project root is automatically loaded by Claude Code CLI.
- You don’t need to repeat these instructions in every prompt.

**Tips**

- **Keep it scannable**: Use bullets and short lines.
- **Update as you learn**: When Claude keeps making the same mistake, add one line.
- **Version the file**: Commit `CLAUDE.md` so the team benefits.
"""

private let tipArticleKeyboardShortcuts = """
Shortcuts turn Claude Code Mobile into a smooth, low-friction workflow.

**In Claude Code Mobile App**

- **Send**: Tap the send button or use the keyboard’s Return.
- **Voice**: Tap the microphone icon to dictate prompts hands-free.
- **Long prompts**: Pair a hardware keyboard for faster editing.

**In Terminal (Bridge)**

- **Start bridge**: `npx @uladluch/claudecodemobile-bridge@latest` in your project directory.
- **With path**: `npx @uladluch/claudecodemobile-bridge@latest --path /your/project`
- **Auto-start**: After first pairing, the bridge offers to install as a login item.

**Claude Code CLI Tips**

- Claude runs in **full-auto** mode via the bridge — it can read/write files without asking.
- Use `CLAUDE.md` in your project root to set persistent instructions.
"""

private let tipArticleComposerBestPractices = """
When you ask the AI to **build or change several parts** of the app at once (Composer-style, multi-file flow), a bit of structure prevents wrong files, half-done work, and confusion.

**Break the work into clear steps**

- **Number the steps** in your prompt: “1) Add the API function in `api/users.ts`. 2) Add the UI component that calls it in `components/UserProfile.tsx`. 3) Add error handling and a loading state.”
- **One logical unit per step** so the model (and you) can verify each part before moving on. If step 2 depends on step 1, say so: “Step 2: using the function from step 1, add …”

**Name files and layers explicitly**

- **Files**: “Create `hooks/useUser.ts`” and “Update `pages/profile.tsx` to use it” avoid ambiguity. The model is less likely to invent a different structure.
- **Layers**: “The API layer returns X; the UI should display Y and handle Z” keeps data flow clear and consistent across files.

**Review after each big step**

- After the model generates a chunk (e.g. “step 1 done”), **skim the diff**: wrong imports, wrong types, or style issues are easier to fix before the next step builds on them.
- If something is off, correct it in a short follow-up (“Use our `apiClient` instead of fetch”) before asking for the next step.

**Use the Prompt Book for multi-step tasks**

- Templates like “Add tests for this,” “Refactor to use X,” or “Code Review Expert” give the model a **checklist**. That often leads to more complete and consistent multi-file results than a single vague prompt.
- Combine with steps: “Use the ‘Add unit tests’ template for `UserService`. Focus on the new `validateEmail` function first, then the rest.”
"""

private let tipsSectionsList: [TipsSection] = [
    TipsSection(
        sectionTitle: "Getting Started",
        sectionImage: "star.fill",
        sectionColor: Color(uiColor: .systemOrange),
        items: [
            TipItem(title: "What is Claude Code Mobile?", subtitle: "Learn about the AI-powered coding assistant", durationMinutes: 3, systemImage: "questionmark.circle.fill", iconColor: .brandPrimary, bodyMarkdown: tipArticleWhatIsClaudeCodeMobile),
            TipItem(title: "Setting Up Your Workspace", subtitle: "Install Claude Code CLI and connect the bridge", durationMinutes: 4, systemImage: "desktopcomputer", iconColor: .brandPrimary, bodyMarkdown: tipArticleSettingUpWorkspace),
            TipItem(title: "Your First Prompt", subtitle: "Send your first prompt from the app", durationMinutes: 3, systemImage: "paperplane.fill", iconColor: .brandPrimary, bodyMarkdown: tipArticleYourFirstPrompt),
        ]
    ),
    TipsSection(
        sectionTitle: "Prompting Effectively",
        sectionImage: "text.bubble.fill",
        sectionColor: Color(uiColor: .systemOrange),
        items: [
            TipItem(title: "Writing Clear Prompts", subtitle: "How to communicate effectively with AI", durationMinutes: 4, systemImage: "list.bullet", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleWritingClearPrompts),
            TipItem(title: "Using Context Effectively", subtitle: "Help AI understand your codebase", durationMinutes: 3, systemImage: "doc.text.magnifyingglass", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleUsingContextEffectively),
            TipItem(title: "Choosing the Right Prompt", subtitle: "When to use different prompt types", durationMinutes: 4, systemImage: "cpu", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleChoosingRightPrompt),
        ]
    ),
    TipsSection(
        sectionTitle: "MCPs & Extensions",
        sectionImage: "puzzlepiece.fill",
        sectionColor: Color(uiColor: .systemOrange),
        items: [
            TipItem(title: "What are MCPs?", subtitle: "Understanding Model Context Protocol", durationMinutes: 4, systemImage: "puzzlepiece.fill", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleWhatAreMCPs),
            TipItem(title: "Essential MCPs for Workflow", subtitle: "Must-have MCPs for your projects", durationMinutes: 5, systemImage: "wrench.and.screwdriver.fill", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleEssentialMCPs),
        ]
    ),
    TipsSection(
        sectionTitle: "Advanced Tips",
        sectionImage: "gearshape.2.fill",
        sectionColor: Color(uiColor: .systemOrange),
        items: [
            TipItem(title: "IDE Rules Files", subtitle: "Customize AI behavior with rules", durationMinutes: 5, systemImage: "doc.badge.gearshape", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleCursorRulesFiles),
            TipItem(title: "Keyboard Shortcuts", subtitle: "Speed up your workflow", durationMinutes: 3, systemImage: "keyboard", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleKeyboardShortcuts),
            TipItem(title: "Composer Best Practices", subtitle: "Build features with multiple components", durationMinutes: 5, systemImage: "square.stack.3d.up.fill", iconColor: Color(uiColor: .systemOrange), bodyMarkdown: tipArticleComposerBestPractices),
        ]
    ),
]

/// Нативная строка списка промпта: иконка, заголовок, подзаголовок (без категории/тегов).
private struct PromptNativeRow: View {
    let item: PromptItem
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.iconColor)
                    .frame(width: 28, height: 28)
                Image(systemName: item.systemImage)
                    .foregroundColor(.labelPrimary)
                    .font(.system(size: 14, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.labelPrimary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Нативная строка списка Tips & Tricks: иконка, заголовок, подзаголовок, длительность.
private struct TipsNativeRow: View {
    let item: TipItem
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.iconColor)
                    .frame(width: 28, height: 28)
                Image(systemName: item.systemImage)
                    .foregroundColor(.labelPrimary)
                    .font(.system(size: 14, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.labelPrimary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Детальный экран раздела Prompt Book (Prompts / Tips & Tricks / Templates).
struct PromptBookDetailView: View {
    let title: String
    var onInsertPrompt: ((String) -> Void)? = nil
    var onCloseModal: (() -> Void)? = nil
    @State private var searchText = ""
    
    private var filteredPrompts: [PromptItem] {
        guard title == "Prompts" else { return [] }
        if searchText.isEmpty { return promptsList }
        return promptsList.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.subtitle.localizedCaseInsensitiveContains(searchText)
            || $0.sectionTitle.localizedCaseInsensitiveContains(searchText)
            || $0.tags.contains { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private var groupedBySection: [(section: String, items: [PromptItem])] {
        let grouped = Dictionary(grouping: filteredPrompts, by: { $0.sectionTitle })
        return promptSectionOrder.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section: section, items: items)
        }
    }
    
    var body: some View {
        Group {
            if title == "Prompts" {
                promptsDetailContent
            } else if title == "Tips & Tricks" {
                tipsContent
            } else {
                placeholderContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { onCloseModal?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(uiColor: .label))
                }
            }
        }
    }
    
    private var promptsDetailContent: some View {
        Group {
            if filteredPrompts.isEmpty {
                promptsEmptyState
            } else {
                List {
                    ForEach(groupedBySection, id: \.section) { pair in
                        Section(pair.section) {
                            ForEach(pair.items) { item in
                                NavigationLink(destination: PromptDetailView(item: item, onUseInClaudeCodeMobile: onInsertPrompt, onCloseModal: onCloseModal)
                                    .onAppear { Analytics.track(.promptViewed(promptTitle: item.title)) }
                                ) {
                                    PromptNativeRow(item: item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: "Search prompts...")
    }
    
    private var promptsEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.labelSecondary)
            Text("No prompts found")
                .font(.dsTitle3)
                .fontWeight(.semibold)
                .foregroundColor(.labelPrimary)
            Text(searchText.isEmpty ? "Start typing to search." : "Try a different search or clear the field.")
                .font(.subheadline)
                .foregroundColor(.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var tipsContent: some View {
        List {
            ForEach(tipsSectionsList) { section in
                Section {
                    ForEach(section.items) { item in
                        NavigationLink(destination: TipDetailView(item: item, onCloseModal: onCloseModal)
                            .onAppear { Analytics.track(.tipViewed(tipTitle: item.title)) }
                        ) {
                            TipsNativeRow(item: item)
                        }
                    }
                } header: {
                    Text(section.sectionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var placeholderContent: some View {
        ZStack {
            Color.clear.edgesIgnoringSafeArea(.all)
            Text("Content coming soon")
                .font(.subheadline)
                .foregroundColor(.labelSecondary)
        }
    }
}

/// Детальный экран одного совета (Tips & Tricks): статья в Markdown, нативный стиль.
private struct TipDetailView: View {
    let item: TipItem
    var onCloseModal: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            Markdown(item.bodyMarkdown)
                .markdownTheme(tipArticleTheme)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { onCloseModal?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(uiColor: .label))
                }
            }
        }
    }
    
    private var tipArticleTheme: MarkdownUI.Theme {
        MarkdownUI.Theme.gitHub
            .text {
                ForegroundColor(Color(uiColor: .label))
                FontSize(16)
            }
            .heading1 { configuration in
                configuration.label
                    .font(.dsTitle2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(uiColor: .label))
                    .markdownMargin(top: 20, bottom: 8)
            }
            .heading2 { configuration in
                configuration.label
                    .font(.dsTitle3)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(uiColor: .label))
                    .markdownMargin(top: 16, bottom: 6)
            }
            .heading3 { configuration in
                configuration.label
                    .font(.dsHeadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(uiColor: .label))
                    .markdownMargin(top: 12, bottom: 4)
            }
            .paragraph { configuration in
                configuration.label
                    .font(.body)
                    .foregroundColor(Color(uiColor: .label))
                    .markdownMargin(top: 0, bottom: 12)
            }
            .codeBlock { configuration in
                configuration.label
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Color(uiColor: .label))
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .markdownMargin(top: 8, bottom: 8)
            }
            .strong {
                FontWeight(.semibold)
                ForegroundColor(Color(uiColor: .label))
            }
    }
}

/// Детализированный экран одного промпта: иконка, заголовок, описание, теги, текст промпта, кнопки «Use in Claude Code» и «Copy to Clipboard».
private struct PromptDetailView: View {
    let item: PromptItem
    var onUseInClaudeCodeMobile: ((String) -> Void)?
    var onCloseModal: (() -> Void)? = nil
    @State private var showCopiedToast = false
    
    private let labelColor = Color(uiColor: .secondaryLabel)
    private let labelColorSemi = Color(uiColor: .secondaryLabel).opacity(0.35)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerWithTagsSection
                    promptSection
                }
                .padding()
            }
            .frame(maxHeight: .infinity)
            buttonsSection
                .padding()
                .background(Color(uiColor: .systemGroupedBackground))
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { onCloseModal?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(uiColor: .label))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToast
            }
        }
    }
    
    private var copiedToast: some View {
        Text("Copied to clipboard")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(Color(uiColor: .label))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.backgroundSecondary))
            .padding(.bottom, 100)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private var headerWithTagsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.iconColor)
                    .frame(width: 48, height: 48)
                Image(systemName: item.systemImage)
                    .foregroundColor(.labelPrimary)
                    .font(.system(size: 22, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.subtitle)
                    .font(.body)
                    .foregroundColor(Color(uiColor: .label))
                FlowLayout(spacing: 8) {
                    ForEach(Array(item.tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(tag.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tag.color.opacity(0.35))
                            )
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
    
    private var promptSection: some View {
        Text(item.promptBody)
            .font(.body)
            .foregroundColor(Color(uiColor: .label))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.backgroundSecondary)
            )
    }
    
    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button(action: useInClaudeCodeMobile) {
                Text("Use in Claude Code")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemBlue))
                    .foregroundColor(.labelPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button(action: copyToClipboard) {
                Text("Copy to Clipboard")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.backgroundSecondary)
                    .foregroundColor(Color(uiColor: .label))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    private func useInClaudeCodeMobile() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Analytics.track(.promptUsedInAntigravity(promptTitle: item.title))
        onUseInClaudeCodeMobile?(item.promptBody)
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = item.promptBody
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Analytics.track(.promptCopied(promptTitle: item.title))
        withAnimation(.easeOut(duration: 0.2)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }
}

/// Простой flow layout для тегов в одну или несколько строк.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: 28, height: 28)
                
                Image(systemName: systemImage)
                    .foregroundColor(.labelPrimary)
                    .font(.system(size: 15, weight: .medium))
            }
            Text(title)
        }
    }
}

/// In-app Safari для открытия Terms of Use и Privacy Policy из More.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .systemBlue
        return vc
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    MenuView(viewModel: MainViewModel())
}
