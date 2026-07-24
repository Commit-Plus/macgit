//
//  GitStatusService+Commit.swift
//  macgit
//

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
    func commit(message: String, in repositoryURL: URL, amend: Bool = false, noVerify: Bool = false, signOff: Bool = false) async throws {
        var arguments = ["commit"]
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append("--allow-empty-message")
        }
        arguments.append(contentsOf: ["-m", message])
        if amend { arguments.append("--amend") }
        if noVerify { arguments.append("--no-verify") }
        if signOff { arguments.append("--signoff") }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func gitUser(in repositoryURL: URL) async -> String? {
        let name = (try? await runGit(arguments: ["config", "user.name"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (try? await runGit(arguments: ["config", "user.email"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = name, !n.isEmpty, let e = email, !e.isEmpty else { return nil }
        return "\(n) <\(e)>"
    }

    func recentCommits(limit: Int, in repositoryURL: URL) async -> [(hash: String, message: String)] {
        let output = (try? await runGit(arguments: ["log", "--oneline", "-\(limit)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            // Format: "<short-hash> <message>"
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard let hash = parts.first else { return nil }
            let message = parts.count > 1 ? String(parts[1]) : ""
            return (hash: String(hash), message: message)
        }
    }

    func recentCommits(in repositoryURL: URL, count: Int = 10) async -> [(hash: String, message: String)] {
        let output = (try? await runGit(arguments: ["log", "--oneline", "-\(count)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let hash = parts.first else { return nil }
            let message = parts.count > 1 ? String(parts[1]) : ""
            return (hash: String(hash), message: message)
        }
    }

    // MARK: - Commit History

    func commitHistory(allBranches: Bool, in repositoryURL: URL) async -> [Commit] {
        await commitHistory(allBranches: allBranches, limit: 500, skip: 0, in: repositoryURL)
    }

    func commitHistory(allBranches: Bool, limit: Int, skip: Int = 0, in repositoryURL: URL) async -> [Commit] {
        var arguments = ["log", "--topo-order"]
        if allBranches {
            arguments.append("--all")
        }
        arguments.append(contentsOf: [
            "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
            "--date=iso-strict",
            "--max-count", "\(limit)"
        ])
        if skip > 0 {
            arguments.append(contentsOf: ["--skip", "\(skip)"])
        }
        let output = (try? await runGit(arguments: arguments, in: repositoryURL)) ?? ""
        return parseCommitLog(output)
    }

    func commitHistory(branch: String, in repositoryURL: URL) async -> [Commit] {
        await commitHistory(branch: branch, limit: 500, skip: 0, in: repositoryURL)
    }

    func commitHistory(branch: String, limit: Int, skip: Int = 0, in repositoryURL: URL) async -> [Commit] {
        let arguments = [
            "log", "--topo-order", branch,
            "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
            "--date=iso-strict",
            "--max-count", "\(limit)"
        ]

        var pagedArguments = arguments
        if skip > 0 {
            pagedArguments.append(contentsOf: ["--skip", "\(skip)"])
        }

        let output = (try? await runGit(arguments: pagedArguments, in: repositoryURL)) ?? ""
        return parseCommitLog(output)
    }

    func tipHash(for ref: String, in repositoryURL: URL) async -> String? {
        let output = (try? await runGit(arguments: ["rev-parse", "\(ref)^{commit}"], in: repositoryURL))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output = output, !output.isEmpty else { return nil }
        return output
    }

    func aheadBehindCount(in repositoryURL: URL) async -> (ahead: Int, behind: Int) {
        // Pull and Push badges describe only the checked-out branch. A local
        // branch without an upstream has no meaningful remote comparison.
        guard let branch = await currentBranch(in: repositoryURL),
              await upstreamBranch(for: branch, in: repositoryURL) != nil else {
            return (ahead: 0, behind: 0)
        }

        let output = (try? await runGit(
            arguments: ["rev-list", "--count", "--left-right", "@{upstream}...HEAD"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return (ahead: 0, behind: 0)
        }
        return (ahead: ahead, behind: behind)
    }

    private func parseCommitLog(_ raw: String) -> [Commit] {
        let dateFormatter = ISO8601DateFormatter()
        var commits: [Commit] = []
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\u{0000}", omittingEmptySubsequences: false)
            guard parts.count >= 6 else { continue }
            let hash = String(parts[0])
            let parentStr = String(parts[1])
            let parents = parentStr.isEmpty ? [] : parentStr.split(separator: " ").map { String($0) }
            let message = String(parts[2])
            let author = String(parts[3])
            let email = String(parts[4])
            let dateStr = String(parts[5])
            let refsPart = parts.count > 6 ? String(parts[6]) : ""
            let refs = refsPart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let date = dateFormatter.date(from: dateStr) ?? Date()
            commits.append(Commit(hash: hash, parents: parents, message: message, author: author, email: email, date: date, refs: refs))
        }
        return commits
    }
}
