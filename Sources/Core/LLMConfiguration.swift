import Foundation

public struct LLMConfiguration: Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String

    public init(baseURL: String = "", apiKey: String = "", model: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public var isComplete: Bool {
        normalizedURL != nil
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var normalizedURL: URL? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmedBaseURL),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }

        return components.url
    }

    public var normalizedBaseURLString: String? {
        normalizedURL?.absoluteString
    }
}
