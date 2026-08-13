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

struct GeminiCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .googleGemini,
        displayName: "Gemini",
        systemImage: "cloud",
        detail: "Cloud · Gemini 3.5 Flash-Lite",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: false,
        defaultModel: "gemini-3.5-flash-lite",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let httpClient: any AIProviderHTTPClient
    private let modelsEndpoint: URL

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        modelsEndpoint: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    ) {
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        self.httpClient = httpClient
        self.modelsEndpoint = modelsEndpoint
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Gemini model is not configured.")
        }
        let endpoint = modelsEndpoint.appending(path: "\(model):generateContent")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": [
                "parts": [["text": CloudCommitMessagePrompt.instructions]],
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": CloudCommitMessagePrompt.userPrompt(for: request)]],
            ]],
            "generationConfig": [
                "maxOutputTokens": 512,
                "responseMimeType": "application/json",
                "responseJsonSchema": CloudCommitMessagePrompt.responseSchema,
                "thinkingConfig": [
                    "thinkingLevel": "MINIMAL",
                    "includeThoughts": false,
                ],
            ],
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        let candidates = payload.candidates ?? []
        let responseTexts = candidates
            .compactMap(\.content)
            .flatMap(\.parts)
            .filter { $0.thought != true }
            .compactMap(\.text)

        for text in responseTexts {
            if let generated = try? CloudCommitMessageResponse.decode(from: text).formatted() {
                return generated
            }
        }

        if let blockReason = payload.promptFeedback?.blockReason {
            throw CommitMessageGenerationError.providerRequestFailed(
                "Gemini blocked the request (\(blockReason)). Try generating from a smaller or different set of changes."
            )
        }
        if let candidate = candidates.first {
            switch candidate.finishReason {
            case "MAX_TOKENS":
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini reached its output limit before returning a commit message. Try generating from a smaller change."
                )
            case "STOP":
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini completed the request but returned no valid commit-message JSON. Generate it again."
                )
            case let reason?:
                let detail = candidate.finishMessage.map { ": \($0)" } ?? "."
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini stopped generating (\(reason))\(detail)"
                )
            case nil:
                break
            }
        }
        throw CommitMessageGenerationError.providerRequestFailed(
            "Gemini returned an empty response. Generate the commit message again."
        )
    }

    private struct Response: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
        let finishMessage: String?
    }

    private struct Content: Decodable {
        let parts: [Part]
    }

    private struct Part: Decodable {
        let text: String?
        let thought: Bool?
    }

    private struct PromptFeedback: Decodable {
        let blockReason: String?
    }
}
