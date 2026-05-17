import SwiftUI

struct RateAppFeedbackView: View {
    @FocusState private var isFeedbackFocused: Bool
    @State private var feedbackText = ""
    @State private var isSending = false
    
    let source: String
    let onDismiss: () -> Void
    let onSend: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.labelPrimary.opacity(0.9))
                        .padding(12)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    Text("Help us improve")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.labelPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("Tell us what didn't work well. Your feedback goes directly to the team.")
                        .font(.system(size: 15))
                        .foregroundColor(.labelPrimary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $feedbackText)
                            .focused($isFeedbackFocused)
                            .font(.system(size: 16))
                            .foregroundColor(.labelPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.labelPrimary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.labelPrimary.opacity(0.15), lineWidth: 1)
                            )
                        
                        if feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Write your feedback...")
                                .font(.system(size: 16))
                                .foregroundColor(.labelPrimary.opacity(0.35))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Button {
                        sendFeedback()
                    } label: {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .labelPrimary))
                            } else {
                                Text("Send Feedback")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(canSend ? Color.labelPrimary : Color.labelSecondary.opacity(0.6))
                        )
                        .foregroundColor(.labelPrimary)
                    }
                    .disabled(!canSend)
                    .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isFeedbackFocused = true
            }
        }
    }
    
    private var canSend: Bool {
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    
    private func sendFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        
        isSending = true
        RatingFeedbackService.shared.saveFeedback(trimmed, source: source) { result in
            DispatchQueue.main.async {
                isSending = false
                if case .failure(let error) = result {
                    print("Failed to save rating feedback: \(error.localizedDescription)")
                }
                onSend(trimmed)
            }
        }
    }
}
