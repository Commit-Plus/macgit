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

    var supportsRepositoryAgent: Bool { true }

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
        guard let text = outputText(from: payload, rawData: data) else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> String {
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
            "instructions": RepositoryAIPrompt.instructions,
            "input": RepositoryAIPrompt.userPrompt(for: request),
            "max_output_tokens": 1_200,
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = outputText(from: payload, rawData: data) else {
            throw RepositoryAIError.invalidResponse(
                "OpenAI did not return a usable Repository AI response."
            )
        }
        return text
    }

    func generateRepositoryAgentTurn(
        request: RepositoryAIAgentRequest
    ) async throws -> RepositoryAIAgentTurn {
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
            "instructions": RepositoryAIPrompt.agentInstructions,
            "input": repositoryAgentInput(for: request),
            "max_output_tokens": 1_200,
            "store": false,
            "tool_choice": request.isFirstTurn ? "required" : "auto",
            "tools": [[
                "type": "function",
                "name": "execute_git",
                "description": "Run one bounded, read-only Git query in the current repository.",
                "strict": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "arguments": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Git subcommand and arguments, without the git executable.",
                        ],
                    ],
                    "required": ["arguments"],
                    "additionalProperties": false,
                ],
            ]],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse("OpenAI did not return a usable Repository AI response.")
        }
        let toolCalls = try payload.output
            .filter { $0.type == "function_call" }
            .map { output in
                guard let id = output.callID,
                      let name = output.name,
                      let rawArguments = output.arguments,
                      let data = rawArguments.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let arguments = object["arguments"] as? [String] else {
                    throw RepositoryAIError.invalidResponse("OpenAI returned an invalid Git tool call.")
                }
                return RepositoryAIAgentToolCall(id: id, name: name, arguments: arguments)
            }
        let text = payload.output.compactMap(\.content).flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?.text ?? ""
        return RepositoryAIAgentTurn(text: text, toolCalls: toolCalls)
    }

    private func repositoryAgentInput(for request: RepositoryAIAgentRequest) -> [[String: Any]] {
        var input: [[String: Any]] = [[
            "role": "user",
            "content": RepositoryAIPrompt.agentPrompt(for: request),
        ]]
        for toolResult in request.previousToolResults {
            let arguments = (try? JSONSerialization.data(withJSONObject: [
                "arguments": toolResult.toolCall.arguments,
            ]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"arguments\":[]}"
            input.append([
                "type": "function_call",
                "call_id": toolResult.toolCall.id,
                "name": toolResult.toolCall.name,
                "arguments": arguments,
            ])
            input.append([
                "type": "function_call_output",
                "call_id": toolResult.toolCall.id,
                "output": toolResult.commandResult.output,
            ])
        }
        return input
    }

    private func outputText(from payload: Response, rawData: Data) -> String? {
        if let text = payload.output
            .compactMap(\.content)
            .flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?
            .text {
            return text
        }
        return outputText(from: rawData)
    }

    private func outputText(from rawData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let output = object["output"] as? [[String: Any]] else {
            return nil
        }
        return output
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["type"] as? String == "output_text" })?["text"] as? String
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
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
            "instructions": ConflictAIPrompt.instructions,
            "input": context,
            "max_output_tokens": 4_000,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "conflict_resolution",
                    "strict": true,
                    "schema": ConflictAIPrompt.responseSchema,
                ],
            ],
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let text = outputText(from: data) else {
            throw ConflictAIResolutionError.invalidResponse(
                "OpenAI did not return a conflict-resolution plan."
            )
        }
        return try ConflictAIResolutionResponse.decode(from: text)
    }

    private struct Response: Decodable {
        let output: [Output]
    }

    private struct Output: Decodable {
        let type: String?
        let content: [Content]?
        let callID: String?
        let name: String?
        let arguments: String?

        enum CodingKeys: String, CodingKey {
            case type
            case content
            case callID = "call_id"
            case name
            case arguments
        }
    }

    private struct Content: Decodable {
        let type: String
        let text: String?
    }
}
