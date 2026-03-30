import Foundation

public final class LLMRefiner {
    public enum RefinerError: Swift.Error, Equatable {
        case invalidConfiguration
        case invalidResponse
        case invalidStatusCode(Int)
    }

    public typealias HTTPClient = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct ChatCompletionRequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                enum CodingKeys: String, CodingKey {
                    case content
                }

                let content: String

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    content = try container.decode(String.self, forKey: .content)
                }
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private static let systemPrompt = """
Correct only obvious speech recognition mistakes.
Preserve content that already appears correct.
Never rewrite, summarize, embellish, or delete correct text.
Preserve code terms, technical names, and mixed-language content whenever they already look right.
Fix obvious transliteration mistakes such as 配森 -> Python and 杰森 -> JSON when clearly warranted.
Return only the final corrected text and nothing else.
"""

    private let httpClient: HTTPClient

    public convenience init() {
        self.init(httpClient: Self.defaultHTTPClient)
    }

    public init(httpClient: @escaping HTTPClient) {
        self.httpClient = httpClient
    }

    public func refine(transcript: String, config: LLMConfiguration) async throws -> String {
        let request = try Self.makeRequest(transcript: transcript, config: config)
        let (data, response) = try await httpClient(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RefinerError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw RefinerError.invalidStatusCode(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let message = decoded.choices.first?.message else {
            throw RefinerError.invalidResponse
        }

        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        return content.isEmpty ? transcript : content
    }

    public func testConnection(config: LLMConfiguration) async -> Result<Void, Swift.Error> {
        do {
            _ = try await refine(transcript: "Connection test", config: config)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func makeRequest(transcript: String, config: LLMConfiguration) throws -> URLRequest {
        guard let endpoint = Self.endpointURL(for: config) else {
            throw RefinerError.invalidConfiguration
        }

        let trimmedAPIKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)

        let body = ChatCompletionRequestBody(
            model: trimmedModel,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: transcript)
            ],
            temperature: 0,
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func endpointURL(for config: LLMConfiguration) -> URL? {
        config.normalizedURL?.appending(path: "chat/completions")
    }

    private static let defaultHTTPClient: HTTPClient = { request in
        try await URLSession.shared.data(for: request)
    }
}
