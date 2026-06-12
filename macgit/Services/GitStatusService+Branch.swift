//
//  GitStatusService+Branch.swift
//  macgit
//

import Foundation

struct BranchSyncStatus: Equatable {
    let ahead: Int   // local commits not on remote
    let behind: Int  // remote commits not on local
}

extension GitStatusService {
    func currentBranch(in repositoryURL: URL) async -> String? {
        let branch = (try? await runGit(arguments: ["branch", "--show-current"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let b = branch, !b.isEmpty else { return nil }
        return b
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

    func setUpstream(remote: String, branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--set-upstream-to", "\(remote)/\(branch)", branch], in: repositoryURL)
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
