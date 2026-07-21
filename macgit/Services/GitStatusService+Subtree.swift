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

extension GitStatusService {
    func subtrees(
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws -> [GitSubtreeEntry] {
        try await registry.entries(in: repositoryURL)
    }

    func linkExistingSubtree(
        _ request: SubtreeLinkRequest,
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws -> GitSubtreeEntry {
        let existing = try await registry.entries(in: repositoryURL)
        let entry = try await validatedLinkedSubtreeEntry(
            request,
            existing: existing,
            in: repositoryURL
        )
        try await registry.save(entry, in: repositoryURL)
        notifySubtreeMutationSucceeded(in: repositoryURL)
        return entry
    }

    func unlinkSubtree(
        id: String,
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws {
        try await registry.remove(id: id, in: repositoryURL)
        notifySubtreeMutationSucceeded(in: repositoryURL)
    }

    private func validatedLinkedSubtreeEntry(
        _ request: SubtreeLinkRequest,
        existing: [GitSubtreeEntry],
        in repositoryURL: URL
    ) async throws -> GitSubtreeEntry {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw GitSubtreeRegistryError.emptyName
        }

        let repository = request.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw GitSubtreeRegistryError.emptyRepository
        }

        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitSubtreeRegistryError.emptyBranch
        }

        let path = try GitSubtreeRegistry.normalizedRelativePath(request.path, in: repositoryURL)
        try GitSubtreeRegistry.rejectPathConflict(path, existing: existing)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent(path, isDirectory: true).path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SubtreeLinkValidationError.missingDirectory(path)
        }

        let trackedOutput = try? await runGit(
            arguments: ["ls-files", "--error-unmatch", "--", path],
            in: repositoryURL
        )
        guard trackedOutput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SubtreeLinkValidationError.untrackedDirectory(path)
        }

        return GitSubtreeEntry(
            id: GitSubtreeRegistry.uniqueID(for: path, existingIDs: Set(existing.map(\.id))),
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: request.squash,
            folderExists: true
        )
    }

    private func notifySubtreeMutationSucceeded(in repositoryURL: URL) {
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }
}

