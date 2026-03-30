import Foundation
import Testing
@testable import VoiceInputCore

private struct ChatCompletionsRequest: Decodable {
    struct Message: Decodable, Equatable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double?
    let stream: Bool?
}

private let requiredPromptClauses = [
    "Correct only obvious speech recognition mistakes.",
    "Preserve content that already appears correct.",
    "Never rewrite, summarize, embellish, or delete correct text.",
    "Preserve code terms, technical names, and mixed-language content whenever they already look right.",
    "Fix obvious transliteration mistakes such as 配森 -> Python and 杰森 -> JSON when clearly warranted.",
    "Return only the final corrected text and nothing else."
]

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

struct LLMRefinerTests {
    @Test func requestUsesChatCompletionsShapeAndConservativePrompt() async throws {
        let recorder = RequestRecorder()
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )

        let refiner = LLMRefiner(httpClient: { request in
            await recorder.record(request)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{"content":"hello world"}}]}"#.utf8)
            return (body, response)
        })

        _ = try await refiner.refine(transcript: "hello 配森 world", config: config)

        let request = try #require(await recorder.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let payload = try JSONDecoder().decode(ChatCompletionsRequest.self, from: try #require(request.httpBody))
        #expect(payload.model == "gpt-4.1-mini")
        #expect(payload.temperature == 0)
        #expect(payload.stream == false)
        #expect(payload.messages.count == 2)
        #expect(payload.messages[0].role == "system")
        #expect(payload.messages[1].role == "user")
        #expect(payload.messages[1].content == "hello 配森 world")
        #expect(requiredPromptClauses.allSatisfy { payload.messages[0].content.contains($0) })
    }

    @Test func requestTrimsWhitespaceFromConfigValuesBeforeSending() async throws {
        let recorder = RequestRecorder()
        let config = LLMConfiguration(
            baseURL: "  https://example.com/v1  ",
            apiKey: "  secret  ",
            model: "  gpt-4.1-mini  "
        )

        let refiner = LLMRefiner(httpClient: { request in
            await recorder.record(request)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{"content":"trimmed"}}]}"#.utf8)
            return (body, response)
        })

        _ = try await refiner.refine(transcript: "hello", config: config)

        let request = try #require(await recorder.requests.last)
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

        let payload = try JSONDecoder().decode(ChatCompletionsRequest.self, from: try #require(request.httpBody))
        #expect(payload.model == "gpt-4.1-mini")
    }

    @Test func refineReturnsOriginalTranscriptWhenModelContentIsBlank() async throws {
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )
        let refiner = LLMRefiner(httpClient: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)
            return (body, response)
        })

        let refined = try await refiner.refine(transcript: "原始 transcript", config: config)

        #expect(refined == "原始 transcript")
    }

    @Test func refineThrowsOnMalformedSuccessBody() async throws {
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )
        let refiner = LLMRefiner(httpClient: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{}}]}"#.utf8)
            return (body, response)
        })

        do {
            _ = try await refiner.refine(transcript: "原始 transcript", config: config)
            Issue.record("expected malformed 200 body to throw")
        } catch {
        }
    }

    @Test func testConnectionReturnsFailureForMalformedSuccessBody() async throws {
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )
        let refiner = LLMRefiner(httpClient: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{}}]}"#.utf8)
            return (body, response)
        })

        let result = await refiner.testConnection(config: config)

        #expect({
            if case .failure = result {
                return true
            }
            return false
        }())
    }

    @Test func refineThrowsForNonHTTPResponse() async throws {
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )
        let refiner = LLMRefiner(httpClient: { request in
            let response = URLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                mimeType: "application/json",
                expectedContentLength: -1,
                textEncodingName: nil
            )
            let body = Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)
            return (body, response)
        })

        do {
            _ = try await refiner.refine(transcript: "原始 transcript", config: config)
            Issue.record("expected non-HTTP response to throw")
        } catch let error as LLMRefiner.RefinerError {
            #expect(error == .invalidResponse)
        } catch {
            Issue.record("expected invalidResponse, got \(error)")
        }
    }

    @Test func testConnectionUsesSameRequestPathAndReturnsSuccess() async throws {
        let recorder = RequestRecorder()
        let config = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )
        let refiner = LLMRefiner(httpClient: { request in
            await recorder.record(request)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"choices":[{"message":{"content":"connection ok"}}]}"#.utf8)
            return (body, response)
        })

        let result = await refiner.testConnection(config: config)

        #expect({
            if case .success = result {
                return true
            }
            return false
        }())
        let request = try #require(await recorder.requests.last)
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    }
}
