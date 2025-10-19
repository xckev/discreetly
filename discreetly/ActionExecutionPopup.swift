import SwiftUI

struct ActionExecutionPopup: View {
    let actionName: String
    let actionType: ActionType
    let isExecuting: Bool
    let onDismiss: () -> Void

    @State private var progress: Double = 0.0
    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: 20) {
            // Icon and title
            VStack(spacing: 12) {
                ZStack {
                    if isExecuting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5)
                    } else if showCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: iconForActionType(actionType))
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 60, height: 60)

                Text(isExecuting ? "Executing Action" : "Action Complete")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(actionName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Status message
            VStack(spacing: 8) {
                if isExecuting {
                    Text("Processing your emergency action...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Please wait while we handle your request")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Your action has been executed successfully")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Dismiss button (only shown when not executing)
            if !isExecuting {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .frame(width: 300)
        .onAppear {
            if isExecuting {
                // Simulate progress
                withAnimation(.easeInOut(duration: 1.0)) {
                    progress = 1.0
                }

                // Show checkmark after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.spring()) {
                        showCheckmark = true
                    }

                    // Auto-dismiss after showing checkmark
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func iconForActionType(_ actionType: ActionType) -> String {
        switch actionType {
        case .distressCall:
            return "phone.fill"
        case .textMessage:
            return "message.fill"
        case .ask:
            return "brain.head.profile"
        case .covertCall:
            return "phone.circle"
        }
    }
}

// Overlay wrapper for the popup
struct ActionExecutionOverlay: View {
    let actionName: String
    let actionType: ActionType
    let isExecuting: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isExecuting {
                        onDismiss()
                    }
                }

            // Popup
            ActionExecutionPopup(
                actionName: actionName,
                actionType: actionType,
                isExecuting: isExecuting,
                onDismiss: onDismiss
            )
        }
    }
}

#Preview {
    ActionExecutionOverlay(
        actionName: "Emergency Alert",
        actionType: .textMessage,
        isExecuting: true,
        onDismiss: {}
    )
}