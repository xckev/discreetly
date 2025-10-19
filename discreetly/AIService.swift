//
//  AIService.swift
//  discreetly
//
//  Service for AI-powered features: web search, intelligent responses, question answering
//

import Foundation

final class AIService {
    static let shared = AIService()

    private var apiKey: String?

    func setAPIKey(_ key: String) {
        self.apiKey = key
    }

    /// Search the web for information
    func searchWeb(query: String) async throws -> String {
        // Using DuckDuckGo Instant Answer API (free, no API key required)
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json") else {
            throw AIServiceError.invalidQuery
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)

        if let abstract = response.abstract, !abstract.isEmpty {
            return abstract
        } else if let answer = response.answer, !answer.isEmpty {
            return answer
        } else {
            return "No results found for: \(query)"
        }
    }

    /// Generate an intelligent response using AI
    /// This is a placeholder - you can integrate with OpenAI, Anthropic, or other AI APIs
    func generateResponse(prompt: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw AIServiceError.noAPIKey
        }

        // Placeholder for AI API integration
        // Example: OpenAI ChatGPT API
        return "AI response placeholder. Configure your API key to enable AI features."
    }

    /// Ask a question and get an answer
    func askQuestion(_ question: String) async throws -> String {
        // Try web search first
        do {
            let searchResult = try await searchWeb(query: question)
            return searchResult
        } catch {
            // Fallback to AI if web search fails
            return try await generateResponse(prompt: question)
        }
    }
}

// MARK: - Errors
enum AIServiceError: LocalizedError {
    case invalidQuery
    case noAPIKey
    case networkError
    case parsingError

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .noAPIKey:
            return "AI API key not configured"
        case .networkError:
            return "Network request failed"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}

// MARK: - DuckDuckGo API Response
struct DuckDuckGoResponse: Codable {
    let abstract: String?
    let answer: String?
    let relatedTopics: [RelatedTopic]?

    enum CodingKeys: String, CodingKey {
        case abstract = "Abstract"
        case answer = "Answer"
        case relatedTopics = "RelatedTopics"
    }
}

struct RelatedTopic: Codable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}
