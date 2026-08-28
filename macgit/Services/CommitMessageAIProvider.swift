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

protocol CommitMessageAIProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }

    func availability() async -> AIProviderAvailability
    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage
    func generateRepositoryResponse(
        request: RepositoryAIRequest
    ) async throws -> String
}

extension CommitMessageAIProvider {
    func generateRepositoryResponse(
        request: RepositoryAIRequest
    ) async throws -> String {
        throw CommitMessageGenerationError.providerNotImplemented
    }
}

struct PlaceholderCommitMessageAIProvider: CommitMessageAIProvider {
    let descriptor: AIProviderDescriptor

    func availability() async -> AIProviderAvailability {
        .comingSoon
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        throw CommitMessageGenerationError.providerNotImplemented
    }
}
