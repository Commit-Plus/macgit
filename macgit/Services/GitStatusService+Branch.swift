//
//  GitStatusService+Branch.swift
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

struct BranchSyncStatus: Equatable {
    let ahead: Int   // local commits not on remote
    let behind: Int  // remote commits not on local
}

extension GitStatusService {
    func currentBranch(in repositoryURL: URL) async -> String? {
        let showCurrentOutput = try? await runGit(arguments: ["branch", "--show-current"], in: repositoryURL)
        if let branch = GitCurrentBranchResolver.resolve(
            showCurrentOutput: showCurrentOutput,
            abbreviatedHeadOutput: nil
        ) {
            return branch
        }

        let abbreviatedHeadOutput = try? await runGit(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL)
        return GitCurrentBranchResolver.resolve(
            showCurrentOutput: nil,
            abbreviatedHeadOutput: abbreviatedHeadOutput
        )
    }

    func localBranches(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["branch", "--format=%(refname:short)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func upstreamBranch(for branch: String, in repositoryURL: URL) async -> String? {
        let upstream = (try? await runGit(arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = upstream, !u.isEmpty, !u.contains("fatal:") else { return nil }
        return u
    }

    func localBranchUpstreams(in repositoryURL: URL) async -> [String: String] {
        let format = "%(refname:short) %(upstream:short)"
        let output = (try? await runGit(arguments: ["for-each-ref", "refs/heads/", "--format=\(format)"], in: repositoryURL)) ?? ""
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }

    func setUpstream(upstream: String, branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--set-upstream-to", upstream, branch], in: repositoryURL)
    }

    func unsetUpstream(branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--unset-upstream", branch], in: repositoryURL)
    }

    func createBranch(name: String, checkout: Bool, commit: String?, in repositoryURL: URL) async throws -> String {
        if checkout {
            var arguments = ["checkout", "-b", name]
            if let commit = commit, !commit.isEmpty {
                arguments.append(commit)
            }
            return try await runGit(arguments: arguments, in: repositoryURL)
        } else {
            var arguments = ["branch", name]
            if let commit = commit, !commit.isEmpty {
                arguments.append(commit)
            }
            return try await runGit(arguments: arguments, in: repositoryURL)
        }
    }

    func deleteBranch(name: String, force: Bool, in repositoryURL: URL) async throws -> String {
        let flag = force ? "-D" : "-d"
        return try await runGit(arguments: ["branch", flag, name], in: repositoryURL)
    }

    func deleteRemoteBranch(remote: String, name: String, in repositoryURL: URL) async throws -> String {
        return try await runGit(arguments: ["push", remote, "--delete", name], in: repositoryURL)
    }

    func tags(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["tag", "--list"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func branchSyncStatus(for branch: String, in repositoryURL: URL) async -> BranchSyncStatus? {
        // Check if branch has an upstream
        let upstream = await upstreamBranch(for: branch, in: repositoryURL)
        guard let upstreamRef = upstream, !upstreamRef.isEmpty else {
            print("[branchSyncStatus] No upstream for branch: \(branch)")
            return nil
        }

        // Use a single symmetric-difference command to get both counts atomically
        // Output format: "behind\tahead"
        let output = (try? await runGit(
            arguments: ["rev-list", "--count", "--left-right", "\(upstreamRef)...\(branch)"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let line = output, !line.isEmpty else {
            print("[branchSyncStatus] Empty output for branch: \(branch), upstream: \(upstreamRef)")
            return nil
        }

        let parts = line.split(separator: "\t").map { String($0) }
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            print("[branchSyncStatus] Invalid output for branch: \(branch), output: \(line)")
            return nil
        }

        // If both are zero, return nil to hide the badge
        if ahead == 0 && behind == 0 {
            return nil
        }

        print("[branchSyncStatus] Branch: \(branch), upstream: \(upstreamRef), ahead: \(ahead), behind: \(behind)")
        return BranchSyncStatus(ahead: ahead, behind: behind)
    }

}
