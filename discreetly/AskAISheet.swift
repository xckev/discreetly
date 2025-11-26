import SwiftUI

struct AskAISheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question: String = ""
    @State private var response: String = ""
    @State private var isLoading: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    let actionMapper = ActionMapper.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("AI Assistant")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Ask any question to get intelligent assistance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Question Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Question")
                        .font(.headline)
                        .foregroundColor(.primary)

                    TextField("Type your question here...", text: $question, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                        .disabled(isLoading)

                    Text("Example: Is bitcoin at 150k?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Ask Button
                Button(action: {
                    Task {
                        await askQuestion()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isLoading ? "Processing..." : "Ask AI Assistant")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(question.isEmpty || isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(question.isEmpty || isLoading)

                // Response Section
                if !response.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Assistant Response")
                            .font(.headline)
                            .foregroundColor(.primary)

                        ScrollView {
                            Text(response)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                        .frame(maxHeight: 200)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("AI Assistant")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func askQuestion() async {
        guard !question.isEmpty else { return }

        isLoading = true
        response = ""
        errorMessage = ""

        do {
            let aiResponse = try await ClaudeService.shared.askQuestion(question)

            await MainActor.run {
                self.response = aiResponse
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showingError = true
                self.isLoading = false
            }
        }
    }
}

#Preview {
    AskAISheet()
}