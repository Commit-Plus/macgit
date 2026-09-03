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

struct OpenRouterCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .openRouter,
        displayName: "OpenRouter",
        systemImage: "cloud",
        detail: "Cloud · Auto Router",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: true,
        defaultModel: "openrouter/auto",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let httpClient: any AIProviderHTTPClient
    private let endpoint: URL

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    ) {
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        self.httpClient = httpClient
        self.endpoint = endpoint
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenRouter model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": CloudCommitMessagePrompt.jsonInstructions],
                ["role": "user", "content": CloudCommitMessagePrompt.userPrompt(for: request)],
            ],
            "max_completion_tokens": 250,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "commit_message",
                    "strict": true,
                    "schema": CloudCommitMessagePrompt.responseSchema,
                ],
            ],
            "provider": ["require_parameters": true],
            "plugins": [["id": "response-healing"]],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        if let providerError = payload.error ?? payload.choices?.first?.error {
            throw CommitMessageGenerationError.providerRequestFailed(
                "OpenRouter request failed: \(providerError.message)"
            )
        }
        guard let content = payload.choices?.first?.message?.content else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try content.formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> String {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenRouter model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": RepositoryAIPrompt.instructions],
                ["role": "user", "content": RepositoryAIPrompt.userPrompt(for: request)],
            ],
            "max_completion_tokens": 1_500,
        ]
        if let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionID.isEmpty {
            requestBody["session_id"] = sessionID
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        for attempt in 0..<2 {
            let (data, response) = try await httpClient.data(for: urlRequest)
            try CloudAIProviderSupport.validate(
                response: response,
                data: data,
                providerName: descriptor.displayName
            )
            guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
                if attempt == 0 { continue }
                throw RepositoryAIError.invalidResponse(
                    "OpenRouter returned an unreadable Repository AI response after retrying."
                )
            }
            if let providerError = payload.error ?? payload.choices?.first?.error {
                throw CommitMessageGenerationError.providerRequestFailed(
                    "OpenRouter request failed: \(providerError.message)"
                )
            }
            if let text = payload.choices?.first?.message?.content?.plainText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if attempt == 0 { continue }
            throw RepositoryAIError.invalidResponse(payload.repositoryResponseFailureDescription)
        }

        throw RepositoryAIError.invalidResponse(
            "OpenRouter did not return a usable Repository AI response."
        )
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenRouter model is not configured.")
        }
        let context = try ConflictAIPrompt.context(
            for: request.snapshot,
            characterBudget: descriptor.inputCharacterBudget
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": ConflictAIPrompt.instructions],
                ["role": "user", "content": context],
            ],
            "max_completion_tokens": 4_000,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "conflict_resolution",
                    "strict": true,
                    "schema": ConflictAIPrompt.responseSchema,
                ],
            ],
            "provider": ["require_parameters": true],
            "plugins": [["id": "response-healing"]],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ConflictAIResolutionError.invalidResponse(
                "OpenRouter did not return a conflict-resolution plan."
            )
        }
        if let providerError = payload.error ?? payload.choices?.first?.error {
            throw CommitMessageGenerationError.providerRequestFailed(
                "OpenRouter request failed: \(providerError.message)"
            )
        }
        guard let content = payload.choices?.first?.message?.content else {
            throw ConflictAIResolutionError.invalidResponse(
                "OpenRouter did not return a conflict-resolution plan."
            )
        }
        return try content.conflictResolution()
    }

    private struct Response: Decodable {
        let model: String?
        let choices: [Choice]?
        let error: ProviderError?

        var repositoryResponseFailureDescription: String {
            let provider = model.map { "OpenRouter (\($0))" } ?? "OpenRouter"
            let choice = choices?.first
            let finishReason = choice?.finishReason ?? choice?.nativeFinishReason
            switch finishReason?.lowercased() {
            case "length", "max_tokens":
                return "\(provider) reached its output limit before returning a final answer."
            case "content_filter":
                return "\(provider) blocked the Repository AI response."
            case "error":
                return "\(provider) stopped before returning a final answer."
            case let reason?:
                return "\(provider) stopped with finish reason '\(reason)' without returning a final answer."
            case nil:
                return "\(provider) did not return a usable Repository AI response."
            }
        }
    }

    private struct Choice: Decodable {
        let message: Message?
        let error: ProviderError?
        let finishReason: String?
        let nativeFinishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case error
            case finishReason = "finish_reason"
            case nativeFinishReason = "native_finish_reason"
        }
    }

    private struct Message: Decodable {
        let content: MessageContent?
    }

    private struct ProviderError: Decodable {
        let message: String
    }

    private enum MessageContent: Decodable {
        case text(String)
        case structured(CloudCommitMessageResponse)
        case conflict(ConflictAIResolutionResponse)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            if let response = try? container.decode(CloudCommitMessageResponse.self) {
                self = .structured(response)
                return
            }
            if let response = try? container.decode(ConflictAIResolutionResponse.self) {
                self = .conflict(response)
                return
            }
            if let part = try? container.decode(TextPart.self),
               let text = part.text,
               !text.isEmpty {
                self = .text(text)
                return
            }
            if let parts = try? container.decode([TextPart].self) {
                let text = parts.compactMap(\.text).joined()
                guard !text.isEmpty else {
                    throw CommitMessageGenerationError.invalidResponse
                }
                self = .text(text)
                return
            }
            throw CommitMessageGenerationError.invalidResponse
        }

        func formatted() throws -> GeneratedCommitMessage {
            switch self {
            case .text(let text):
                try CloudCommitMessageResponse.decode(from: text).formatted()
            case .structured(let response):
                try response.formatted()
            case .conflict:
                throw CommitMessageGenerationError.invalidResponse
            }
        }

        var plainText: String? {
            switch self {
            case .text(let text):
                text
            case .structured:
                nil
            case .conflict:
                nil
            }
        }

        func conflictResolution() throws -> ConflictAIResolutionResponse {
            switch self {
            case .text(let text):
                try ConflictAIResolutionResponse.decode(from: text)
            case .conflict(let response):
                response
            case .structured:
                throw ConflictAIResolutionError.invalidResponse(
                    "OpenRouter returned a commit message instead of a conflict-resolution plan."
                )
            }
        }
    }

    private struct TextPart: Decodable {
        let text: String?
    }
}
