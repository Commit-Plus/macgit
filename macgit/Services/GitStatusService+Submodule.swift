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
    func submodules(in repositoryURL: URL) async throws -> [GitSubmoduleEntry] {
        let gitmodulesURL = repositoryURL.appendingPathComponent(".gitmodules", isDirectory: false)
        guard FileManager.default.fileExists(atPath: gitmodulesURL.path) else {
            return []
        }

        let config = try await runGit(
            arguments: [
                "config",
                "-z",
                "--file",
                ".gitmodules",
                "--list"
            ],
            in: repositoryURL
        )
        let index = try await runGit(arguments: ["ls-files", "--stage"], in: repositoryURL)
        let status = try await runGit(
            arguments: ["submodule", "status", "--recursive"],
            in: repositoryURL
        )
        let parsed = try GitSubmoduleParser.parse(config: config, index: index, status: status)

        var entries: [GitSubmoduleEntry] = []
        entries.reserveCapacity(parsed.count)
        for entry in parsed {
            entries.append(try await enrichSubmodule(entry, in: repositoryURL))
        }
        return entries
    }

    private func enrichSubmodule(
        _ entry: GitSubmoduleEntry,
        in repositoryURL: URL
    ) async throws -> GitSubmoduleEntry {
        let checkoutURL = repositoryURL.appendingPathComponent(entry.path, isDirectory: true)
        var isDirectory: ObjCBool = false
        let checkoutExists = FileManager.default.fileExists(
            atPath: checkoutURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        if entry.state == .uninitialized {
            let localURL = try? await runGit(
                arguments: ["config", "--get", "submodule.\(entry.name).url"],
                in: repositoryURL
            )
            let state: GitSubmoduleState = !checkoutExists && localURL != nil
                ? .missing
                : .uninitialized
            return replacing(entry, checkedOutCommit: nil, state: state)
        }

        guard checkoutExists else {
            return replacing(entry, checkedOutCommit: nil, state: .missing)
        }

        let checkedOutCommit = try await runGit(
            arguments: ["rev-parse", "HEAD"],
            in: checkoutURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let workingTreeStatus = try await runGit(
            arguments: ["status", "--porcelain"],
            in: checkoutURL
        )
        let state = entry.state == .clean && !workingTreeStatus.isEmpty
            ? GitSubmoduleState.modified
            : entry.state

        return replacing(entry, checkedOutCommit: checkedOutCommit, state: state)
    }

    private func replacing(
        _ entry: GitSubmoduleEntry,
        checkedOutCommit: String?,
        state: GitSubmoduleState
    ) -> GitSubmoduleEntry {
        GitSubmoduleEntry(
            name: entry.name,
            path: entry.path,
            url: entry.url,
            branch: entry.branch,
            recordedCommit: entry.recordedCommit,
            checkedOutCommit: checkedOutCommit,
            state: state
        )
    }
}
