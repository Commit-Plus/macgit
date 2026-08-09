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

struct GitFlowRecoveryStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func checkpoint(in repositoryURL: URL) async -> GitFlowFinishCheckpoint? {
        if case .value(let checkpoint) = await loadResult(in: repositoryURL) {
            return checkpoint
        }
        return nil
    }

    func loadResult(in repositoryURL: URL) async -> GitFlowLocalStateLoadResult<GitFlowFinishCheckpoint> {
        guard let fileURL = try? await checkpointURL(in: repositoryURL) else { return .invalid(.corrupt) }
        guard fileManager.fileExists(atPath: fileURL.path) else { return .none }
        guard let data = try? Data(contentsOf: fileURL) else { return .invalid(.corrupt) }
        if let version = Self.schemaVersion(in: data), version > GitFlowFinishCheckpoint.supportedSchemaVersion {
            return .invalid(.unsupportedVersion(version))
        }
        guard let checkpoint = try? JSONDecoder().decode(GitFlowFinishCheckpoint.self, from: data) else {
            return .invalid(.corrupt)
        }
        return .value(checkpoint)
    }

    private static func schemaVersion(in data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
    }

    func save(_ checkpoint: GitFlowFinishCheckpoint, in repositoryURL: URL) async throws {
        let fileURL = try await checkpointURL(in: repositoryURL)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(checkpoint).write(to: fileURL, options: .atomic)
    }

    func clear(in repositoryURL: URL) async throws {
        let fileURL = try await checkpointURL(in: repositoryURL)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func checkpointURL(in repositoryURL: URL) async throws -> URL {
        let commonDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repositoryURL)
        return commonDirectory
            .appendingPathComponent("commitplus", isDirectory: true)
            .appendingPathComponent("git-flow-finish.json")
    }
}
