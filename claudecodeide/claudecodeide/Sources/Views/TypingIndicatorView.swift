import SwiftUI
import Combine

struct TypingIndicatorView: View {
    @State private var textIndex = 0
    @State private var dotCount = 1
    
    private let texts = ["Loading", "Thinking", "Generating"]
    private let dotTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let textTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            Text(texts[textIndex])
            Text(String(repeating: ".", count: dotCount))
                // Fixed width to prevent jumping when dots change
                .frame(width: 20, alignment: .leading)
        }
        .font(.system(.subheadline, design: .rounded))
        .foregroundColor(.labelSecondary.opacity(0.8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onReceive(dotTimer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                dotCount = (dotCount % 3) + 1
            }
        }
        .onReceive(textTimer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                textIndex = (textIndex + 1) % texts.count
            }
        }
    }
}

/// Small "Try again" / "Delete" buttons under a failed user message bubble; same style as TypingIndicatorView.
struct TryAgainButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("Try again")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.labelSecondary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .padding(.top, 2)
    }
}

/// Same style as TryAgainButton, red color — removes the failed message.
struct DeleteMessageButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("Delete")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.semanticError)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .padding(.top, 2)
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        TypingIndicatorView()
    }
}
