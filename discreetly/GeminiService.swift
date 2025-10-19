import Foundation

struct GeminiService {
    static let shared = GeminiService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    private let apiKey = "AIzaSyC0UvGrNcKxJSyYxFu77QerV2SkhGSTpQI"

    private init() {}

    struct GeminiRequest: Codable {
        let contents: [Content]

        struct Content: Codable {
            let parts: [Part]

            struct Part: Codable {
                let text: String
            }
        }
    }

    struct GeminiResponse: Codable {
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
        guard !apiKey.isEmpty && apiKey != "YOUR_GEMINI_API_KEY_HERE" else {
            throw GeminiError.missingAPIKey
        }

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(
                    parts: [
                        GeminiRequest.Content.Part(text: question)
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
            throw GeminiError.encodingError(error)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }

            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiError.httpError(httpResponse.statusCode, errorMessage)
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

            guard let firstCandidate = geminiResponse.candidates.first,
                  let firstPart = firstCandidate.content.parts.first else {
                throw GeminiError.noResponse
            }

            return firstPart.text
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkError(error)
        }
    }
}

enum GeminiError: LocalizedError {
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
            return "Gemini API key is not configured. Please contact the developer."
        case .invalidURL:
            return "Invalid Gemini API URL"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .noResponse:
            return "No response from Gemini AI"
        }
    }
}
