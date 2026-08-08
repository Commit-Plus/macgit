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
    func isValidBranchName(_ branch: String, in repositoryURL: URL) async -> Bool {
        do {
            _ = try await runGit(arguments: ["check-ref-format", "--branch", branch], in: repositoryURL)
            return true
        } catch {
            return false
        }
    }

    func hasUnfinishedGitFlowStartOperation(in repositoryURL: URL) async -> Bool {
        if await isMergeInProgress(in: repositoryURL) { return true }
        if await inProgressOperation(in: repositoryURL) != nil { return true }
        return await isRebaseInProgress(in: repositoryURL)
    }

    private func isRebaseInProgress(in repositoryURL: URL) async -> Bool {
        for gitPath in ["rebase-merge", "rebase-apply"] {
            guard let output = try? await runGit(
                arguments: ["rev-parse", "--path-format=absolute", "--git-path", gitPath],
                in: repositoryURL
            ) else { continue }
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }
}
