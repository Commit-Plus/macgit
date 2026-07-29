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

enum ExternalDiffFileService {
    static func prepare(
        file: StatusFile,
        in repositoryURL: URL
    ) async throws -> (beforeURL: URL, afterURL: URL) {
        let trackedPath = file.originalPath ?? file.path
        let beforeData = try await GitStatusService.shared.indexFile(
            at: trackedPath,
            in: repositoryURL
        )
        let workspaceURL = try makeWorkspace()
        let beforeURL = workspaceURL
            .appendingPathComponent("Before", isDirectory: true)
            .appendingPathComponent(trackedPath)
        try FileManager.default.createDirectory(
            at: beforeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try beforeData.write(to: beforeURL, options: .atomic)

        let workingTreeURL = repositoryURL.appendingPathComponent(file.path)
        if FileManager.default.fileExists(atPath: workingTreeURL.path) {
            return (beforeURL, workingTreeURL)
        }

        let afterURL = workspaceURL
            .appendingPathComponent("After", isDirectory: true)
            .appendingPathComponent(file.path)
        try FileManager.default.createDirectory(
            at: afterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: afterURL, options: .atomic)
        return (beforeURL, afterURL)
    }

    private static func makeWorkspace() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommitPlus-ExternalDiff", isDirectory: true)
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
