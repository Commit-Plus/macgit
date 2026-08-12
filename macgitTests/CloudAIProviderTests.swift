//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import XCTest
@testable import macgit

final class CloudAIProviderTests: XCTestCase {
    @MainActor
    func testControllerSavesAndRemovesCloudAPIKeyWithoutExposingIt() async throws {
        let credentialStore = InMemoryAIProviderCredentialStore()
        let defaults = makeDefaults()
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: defaults,
            credentialStore: credentialStore
        )

        try controller.saveAPIKey("  secret-openai-key  ", for: .openAI)
        await controller.refreshAvailability()

        XCTAssertTrue(controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertEqual(controller.availability(for: .openAI), .available)
        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "secret-openai-key")

        controller.selectProvider(.openAI)
        try controller.removeAPIKey(for: .openAI)

        XCTAssertFalse(controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertNil(try credentialStore.apiKey(for: .openAI))
        XCTAssertEqual(controller.selectedProviderID, .appleIntelligence)
    }

    func testOpenAIRequestUsesBearerKeyAndParsesStructuredResponse() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"output":[{"content":[{"type":"output_text","text":"{\\"type\\":\\"feat\\",\\"subject\\":\\"Configure cloud AI providers\\",\\"body\\":\\"\\"}"}]}]}
            """)
        let provider = OpenAICommitMessageProvider(credentialStore: store, httpClient: client)

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-secret")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(result.text, "feat: Configure cloud AI providers")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertNil(body["reasoning"])
        XCTAssertEqual((body["store"] as? Bool), false)
    }

    func testAnthropicRequestUsesRequiredHeadersAndParsesResponse() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"content":[{"type":"text","text":"{\\"type\\":\\"fix\\",\\"subject\\":\\"Handle provider API errors\\",\\"body\\":\\"Surface actionable failures to users.\\"}"}]}
            """)
        let provider = AnthropicCommitMessageProvider(credentialStore: store, httpClient: client)

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(result.subject, "fix: Handle provider API errors")
        XCTAssertEqual(result.body, "Surface actionable failures to users.")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        XCTAssertNotNil(body["output_config"])
    }

    func testGeminiRequestUsesHeaderKeyAndStructuredOutputSchema() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.googleGemini: "gemini-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"candidates":[{"content":{"parts":[{"thought":true,"text":"internal reasoning"},{"text":"{\\"type\\":\\"chore\\",\\"subject\\":\\"Store AI keys in Keychain\\",\\"body\\":\\"\\"}"}]},"finishReason":"STOP"}]}
            """)
        let provider = GeminiCommitMessageProvider(credentialStore: store, httpClient: client)

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-secret")
        XCTAssertEqual(result.text, "chore: Store AI keys in Keychain")
        let body = try requestJSONObject(request)
        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        let responseJSONSchema = try XCTUnwrap(generationConfig["responseJsonSchema"] as? [String: Any])
        XCTAssertEqual(responseJSONSchema["additionalProperties"] as? Bool, false)
        XCTAssertNil(generationConfig["responseSchema"])
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"
        )
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 512)
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MINIMAL")
        XCTAssertNil(thinkingConfig["thinkingBudget"])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, false)
    }

    func testGeminiReportsOutputLimitInsteadOfInvalidResponse() async {
        let store = InMemoryAIProviderCredentialStore(keys: [.googleGemini: "gemini-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"candidates":[{"content":{"parts":[]},"finishReason":"MAX_TOKENS"}]}
            """)
        let provider = GeminiCommitMessageProvider(credentialStore: store, httpClient: client)

        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected an output-limit error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(
                error,
                .providerRequestFailed(
                    "Gemini reached its output limit before returning a commit message. Try generating from a smaller change."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudProviderRejectsGenerationWithoutAPIKey() async {
        let provider = OpenAICommitMessageProvider(
            credentialStore: InMemoryAIProviderCredentialStore(),
            httpClient: StubAIProviderHTTPClient(responseBody: "{}")
        )

        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected a missing API key error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .missingAPIKey("OpenAI"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeRequest() -> CommitMessageGenerationRequest {
        CommitMessageGenerationRequest(
            repositoryName: "macgit",
            branchName: "codex/byok-ai-providers",
            changeSource: .staged,
            changes: CommitChangeSnapshot(
                fingerprint: "tree-1",
                context: "M\tmacgit/App/AIProviderController.swift\n+save API key",
                isTruncated: false
            ),
            recentCommitSubjects: ["feat: Add Apple Intelligence generation"]
        )
    }

    private func requestJSONObject(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "CloudAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        return defaults ?? .standard
    }
}

final class InMemoryAIProviderCredentialStore: AIProviderCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [AIProviderID: String]

    init(keys: [AIProviderID: String] = [:]) {
        self.keys = keys
    }

    func apiKey(for providerID: AIProviderID) throws -> String? {
        lock.withLock { keys[providerID] }
    }

    func saveAPIKey(_ apiKey: String, for providerID: AIProviderID) throws {
        lock.withLock { keys[providerID] = apiKey }
    }

    func deleteAPIKey(for providerID: AIProviderID) throws {
        lock.withLock { keys.removeValue(forKey: providerID) }
    }
}

private actor StubAIProviderHTTPClient: AIProviderHTTPClient {
    private let responseBody: String
    private let statusCode: Int
    private var request: URLRequest?

    init(responseBody: String, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
              ) else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return (Data(responseBody.utf8), response)
    }

    func receivedRequest() -> URLRequest? {
        request
    }
}

private actor StubCloudCommitChangeSnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        CommitChangeSnapshot(fingerprint: "tree-1", context: "M\tfile", isTruncated: false)
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        "tree-1"
    }
}
