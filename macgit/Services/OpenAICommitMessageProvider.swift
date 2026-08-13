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

struct OpenAICommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .openAI,
        displayName: "OpenAI",
        systemImage: "cloud",
        detail: "Cloud · GPT-4o mini",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: false,
        defaultModel: "gpt-4o-mini",
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
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
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
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "instructions": CloudCommitMessagePrompt.instructions,
            "input": CloudCommitMessagePrompt.userPrompt(for: request),
            "max_output_tokens": 250,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "commit_message",
                    "strict": true,
                    "schema": CloudCommitMessagePrompt.responseSchema,
                ],
            ],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        guard let text = payload.output
            .flatMap(\.content)
            .first(where: { $0.type == "output_text" })?
            .text else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    private struct Response: Decodable {
        let output: [Output]
    }

    private struct Output: Decodable {
        let content: [Content]
    }

    private struct Content: Decodable {
        let type: String
        let text: String?
    }
}
