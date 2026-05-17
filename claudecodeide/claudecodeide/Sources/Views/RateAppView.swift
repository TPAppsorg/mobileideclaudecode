import SwiftUI

struct RateAppView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedbackInput = false
    @State private var selectedReaction: Reaction?
    
    let source: String
    
    enum Reaction {
        case thumbsUp
        case thumbsDown
    }
    
    var body: some View {
        ZStack {
            Color.backgroundPrimary
                .ignoresSafeArea()
            
            if showFeedbackInput {
                RateAppFeedbackView(
                    source: source,
                    onDismiss: { dismiss() },
                    onSend: { _ in dismiss() }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                reactionView
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showFeedbackInput)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedReaction)
    }
    
    private var reactionView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.labelPrimary.opacity(0.9))
                        .padding(10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            Spacer()
            
            VStack(spacing: 28) {
                Text("😊")
                    .font(.system(size: 64))
                
                Text("Are you enjoying Claude Code?")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.labelPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                HStack(spacing: 28) {
                    reactionButton(.thumbsDown)
                    reactionButton(.thumbsUp)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func reactionButton(_ reaction: Reaction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedReaction = reaction
            handleReaction(reaction)
        } label: {
            Image(systemName: reaction == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(selectedReaction == reaction ? reactionColor(reaction) : .labelPrimary.opacity(0.8))
                .frame(width: 100, height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selectedReaction == reaction ? reactionColor(reaction).opacity(0.2) : Color.labelPrimary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selectedReaction == reaction ? reactionColor(reaction) : Color.labelPrimary.opacity(0.15), lineWidth: selectedReaction == reaction ? 2 : 1)
                )
                .scaleEffect(selectedReaction == reaction ? 1.08 : 1)
        }
        .buttonStyle(.plain)
    }
    
    private func reactionColor(_ reaction: Reaction) -> Color {
        switch reaction {
        case .thumbsUp:
            return .green
        case .thumbsDown:
            return .red
        }
    }
    
    private func handleReaction(_ reaction: Reaction) {
        switch reaction {
        case .thumbsUp:
            AppRatingService.shared.openAppStoreReview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        case .thumbsDown:
            withAnimation {
                showFeedbackInput = true
            }
        }
    }
}
