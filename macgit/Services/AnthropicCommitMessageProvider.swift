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

struct AnthropicCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .anthropic,
        displayName: "Claude",
        systemImage: "cloud",
        detail: "Cloud · Claude Haiku 4.5",
        dataProcessing: .cloud,
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let httpClient: any AIProviderHTTPClient
    private let endpoint: URL
    private let model: String

    init(
        credentialStore: any AIProviderCredentialStore,
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        model: String = "claude-haiku-4-5"
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.model = model
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 250,
            "system": CloudCommitMessagePrompt.instructions,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": CloudCommitMessagePrompt.responseSchema,
                ],
            ],
            "messages": [[
                "role": "user",
                "content": CloudCommitMessagePrompt.userPrompt(for: request),
            ]],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        guard let text = payload.content.first(where: { $0.type == "text" })?.text else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    private struct Response: Decodable {
        let content: [Content]
    }

    private struct Content: Decodable {
        let type: String
        let text: String?
    }
}
