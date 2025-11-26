import Foundation

struct TextbeltResponse: Codable {
    let success: Bool
    let textId: String?
    let quotaRemaining: Int?
    let error: String?
}

enum TextbeltClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpError(Int, String)
    case decodingError
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Textbelt API key not found. Add TEXTBELT_API_KEY to Info.plist."
        case .invalidURL:
            return "Invalid Textbelt URL."
        case .httpError(let status, let body):
            return "Textbelt HTTP error \(status): \(body)"
        case .decodingError:
            return "Failed to decode Textbelt response."
        case .serviceError(let message):
            return "Textbelt service error: \(message)"
        }
    }
}

final class TextbeltClient {
    static let shared = TextbeltClient()

    private let endpoint = URL(string: "https://textbelt.com/text")

    private func loadAPIKey() -> String? {
        // Read from the app target’s Info.plist
        return Bundle.main.object(forInfoDictionaryKey: "TEXTBELT_API_KEY") as? String
    }

    /// Sends an SMS via Textbelt
    /// - Parameters:
    ///   - phone: Destination phone number (E.164 recommended, e.g. +15555555555)
    ///   - message: Message body
    /// - Returns: TextbeltResponse
    func send(phone: String, message: String) async throws -> TextbeltResponse {
        // If you want to hardcode, you can replace this with: let key = "YOUR_KEY"
        guard let key = loadAPIKey(), !key.isEmpty else {
            throw TextbeltClientError.missingAPIKey
        }
        guard let url = endpoint else {
            throw TextbeltClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // Build x-www-form-urlencoded body
        let params: [String: String] = [
            "phone": phone,
            "message": message,
            "key": key
        ]
        let body = params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TextbeltClientError.httpError(-1, "No HTTPURLResponse")
        }

        // Log response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📡 Textbelt response (\(http.statusCode)): \(responseString)")
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TextbeltClientError.httpError(http.statusCode, bodyText)
        }

        do {
            let decoded = try JSONDecoder().decode(TextbeltResponse.self, from: data)
            if decoded.success == false {
                throw TextbeltClientError.serviceError(decoded.error ?? "Unknown Textbelt error")
            }
            return decoded
        } catch {
            throw TextbeltClientError.decodingError
        }
    }
}
