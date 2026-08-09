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

struct GitFlowConfigurationStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func configuration(in repositoryURL: URL) async -> GitFlowConfiguration? {
        if case .value(let configuration) = await loadResult(in: repositoryURL) {
            return configuration
        }
        return nil
    }

    func loadResult(in repositoryURL: URL) async -> GitFlowLocalStateLoadResult<GitFlowConfiguration> {
        guard let fileURL = try? await configurationURL(in: repositoryURL) else { return .invalid(.corrupt) }
        guard fileManager.fileExists(atPath: fileURL.path) else { return .none }
        guard let data = try? Data(contentsOf: fileURL) else { return .invalid(.corrupt) }
        if let version = Self.schemaVersion(in: data), version > GitFlowConfiguration.supportedSchemaVersion {
            return .invalid(.unsupportedVersion(version))
        }
        guard let configuration = try? JSONDecoder().decode(GitFlowConfiguration.self, from: data) else {
            return .invalid(.corrupt)
        }
        return .value(configuration)
    }

    private static func schemaVersion(in data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
    }

    func save(_ configuration: GitFlowConfiguration, in repositoryURL: URL) async throws {
        let fileURL = try await configurationURL(in: repositoryURL)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration.normalized()).write(to: fileURL, options: .atomic)
    }

    func configurationURL(in repositoryURL: URL) async throws -> URL {
        let commonDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repositoryURL)
        return commonDirectory
            .appendingPathComponent("commitplus", isDirectory: true)
            .appendingPathComponent("git-flow.json")
    }
}
