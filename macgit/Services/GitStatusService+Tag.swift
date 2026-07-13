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
    func tagDetails(name: String, in repositoryURL: URL) async throws -> GitTagDetails {
        let output = try await runGit(
            arguments: [
                "show",
                "-s",
                "--format=%H%x00%an%x00%ae%x00%aI%x00%s%x00%b",
                "\(name)^{commit}"
            ],
            in: repositoryURL
        )
        let fields = output.split(separator: "\u{0000}", omittingEmptySubsequences: false)
        guard fields.count == 6 else {
            throw GitError.commandFailed("Could not read details for tag '\(name)'.")
        }

        let dateText = String(fields[3]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = ISO8601DateFormatter().date(from: dateText) else {
            throw GitError.commandFailed("Could not read the commit date for tag '\(name)'.")
        }

        return GitTagDetails(
            name: name,
            commitHash: String(fields[0]),
            authorName: String(fields[1]),
            authorEmail: String(fields[2]),
            date: date,
            subject: String(fields[4]),
            body: String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func deleteTag(name: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["tag", "-d", name], in: repositoryURL)
    }
}
