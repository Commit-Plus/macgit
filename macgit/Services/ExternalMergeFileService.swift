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

enum ExternalMergeFileService {
    static func prepare(
        file: StatusFile,
        in repositoryURL: URL
    ) async throws -> (
        baseURL: URL,
        currentURL: URL,
        incomingURL: URL,
        outputURL: URL
    ) {
        async let baseData = conflictStageData(
            path: file.path,
            stage: 1,
            repositoryURL: repositoryURL
        )
        async let currentData = conflictStageData(
            path: file.path,
            stage: 2,
            repositoryURL: repositoryURL
        )
        async let incomingData = conflictStageData(
            path: file.path,
            stage: 3,
            repositoryURL: repositoryURL
        )

        let workspaceURL = try makeWorkspace()
        let baseURL = workspaceURL
            .appendingPathComponent("Base", isDirectory: true)
            .appendingPathComponent(file.path)
        let currentURL = workspaceURL
            .appendingPathComponent("Current", isDirectory: true)
            .appendingPathComponent(file.path)
        let incomingURL = workspaceURL
            .appendingPathComponent("Incoming", isDirectory: true)
            .appendingPathComponent(file.path)

        try write(await baseData, to: baseURL)
        try write(await currentData, to: currentURL)
        try write(await incomingData, to: incomingURL)

        let outputURL = repositoryURL.appendingPathComponent(file.path)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try Data().write(to: outputURL, options: .atomic)
        }

        return (baseURL, currentURL, incomingURL, outputURL)
    }

    private static func conflictStageData(
        path: String,
        stage: Int,
        repositoryURL: URL
    ) async -> Data {
        (try? await GitStatusService.shared.conflictStageFile(
            at: path,
            stage: stage,
            in: repositoryURL
        )) ?? Data()
    }

    private static func write(_ data: Data, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func makeWorkspace() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommitPlus-ExternalMerge", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        removeExpiredWorkspaces(in: rootURL)

        let workspaceURL = rootURL.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        return workspaceURL
    }

    private static func removeExpiredWorkspaces(in rootURL: URL) {
        guard let workspaceURLs = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date.now.addingTimeInterval(-24 * 60 * 60)
        for workspaceURL in workspaceURLs {
            let values = try? workspaceURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let modificationDate = values?.contentModificationDate,
               modificationDate < expirationDate {
                try? FileManager.default.removeItem(at: workspaceURL)
            }
        }
    }
}
