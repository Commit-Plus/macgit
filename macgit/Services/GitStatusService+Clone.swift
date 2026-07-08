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
    func cloneRepository(
        remoteURL: String,
        to destinationURL: URL,
        checkoutBranch: String,
        recurseSubmodules: Bool
    ) async throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        var arguments = ["clone"]

        let trimmedBranch = checkoutBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBranch.isEmpty {
            arguments += ["--branch", trimmedBranch]
        }

        if recurseSubmodules {
            arguments.append("--recurse-submodules")
        }

        arguments += [remoteURL, destinationURL.path]
        _ = try await runGit(arguments: arguments, in: parentURL)
    }

    func remoteBranches(remoteURL: String) async throws -> [String] {
        let output = try await runGit(
            arguments: ["ls-remote", "--heads", remoteURL],
            in: FileManager.default.temporaryDirectory
        )
        return Self.parseRemoteBranches(from: output)
    }

    static func parseRemoteBranches(from output: String) -> [String] {
        let branches = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let ref = line.split(separator: "\t").last else { return nil }
                let prefix = "refs/heads/"
                guard ref.hasPrefix(prefix) else { return nil }
                return String(ref.dropFirst(prefix.count))
            }

        return Array(Set(branches)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
