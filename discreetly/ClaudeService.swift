import Foundation

struct ClaudeService {
    static let shared = ClaudeService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    private let apiKey = "AIzaSyC0UvGrNcKxJSyYxFu77QerV2SkhGSTpQI"

    private init() {}

    struct ClaudeRequest: Codable {
        let contents: [Content]

        struct Content: Codable {
            let parts: [Part]

            struct Part: Codable {
                let text: String
            }
        }
    }

    struct ClaudeResponse: Codable {
        let candidates: [Candidate]

        struct Candidate: Codable {
            let content: Content

            struct Content: Codable {
                let parts: [Part]

                struct Part: Codable {
                    let text: String
                }
            }
        }
    }

    func askQuestion(_ question: String) async throws -> String {
        guard !apiKey.isEmpty && apiKey != "YOUR_CLAUDE_API_KEY_HERE" else {
            throw ClaudeError.missingAPIKey
        }

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw ClaudeError.invalidURL
        }

        let request = ClaudeRequest(
            contents: [
                ClaudeRequest.Content(
                    parts: [
                        ClaudeRequest.Content.Part(text: question)
                    ]
                )
            ]
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw ClaudeError.encodingError(error)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeError.invalidResponse
            }

            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ClaudeError.httpError(httpResponse.statusCode, errorMessage)
            }

            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

            guard let firstCandidate = claudeResponse.candidates.first,
                  let firstPart = firstCandidate.content.parts.first else {
                throw ClaudeError.noResponse
            }

            return firstPart.text
        } catch let error as ClaudeError {
            throw error
        } catch {
            throw ClaudeError.networkError(error)
        }
    }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case encodingError(Error)
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API key is not configured. Please contact the developer."
        case .invalidURL:
            return "Invalid Claude API URL"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .noResponse:
            return "No response from Claude AI"
        }
    }
}
