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
import AppKit
import Foundation

enum SearchFileOpenError: LocalizedError {
    case fileNotFound(String)
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File no longer exists: \(path)"
        case .applicationNotFound(let name):
            return "Could not find \(name) to open this file."
        }
    }
}

enum SearchFileApplicationResolver {
    static let previewBundleIdentifier = "com.apple.Preview"

    static let editorBundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.jetbrains.CLion",
        "com.google.android.studio",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.apple.dt.Xcode",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.macromates.TextMate"
    ]

    static func preferredBundleIdentifier(
        isInstalled: (String) -> Bool
    ) -> String {
        editorBundleIdentifiers.first(where: isInstalled) ?? previewBundleIdentifier
    }
}

enum SearchFileOpener {
    @MainActor
    static func open(
        relativePath: String,
        in repositoryURL: URL,
        workspace: NSWorkspace = .shared
    ) async throws {
        let fileURL = repositoryURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SearchFileOpenError.fileNotFound(relativePath)
        }

        let bundleIdentifier = SearchFileApplicationResolver.preferredBundleIdentifier { identifier in
            workspace.urlForApplication(withBundleIdentifier: identifier) != nil
        }

        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw SearchFileOpenError.applicationNotFound("Preview")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.open(
                [fileURL],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
