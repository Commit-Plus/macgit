//
//  GitStatusService+Remote.swift
//  macgit
//

import Foundation

extension GitStatusService {
    func push(options: PushOptions, in repositoryURL: URL) async throws -> String {
        var outputs: [String] = []
        for branch in options.branches {
            let remoteBranch = options.branchMappings[branch] ?? branch
            let refSpec = remoteBranch == branch ? branch : "\(branch):\(remoteBranch)"
            let output = try await runGit(arguments: ["push", options.remote, refSpec], in: repositoryURL)
            outputs.append(output)
        }
        if options.pushTags {
            let tagOutput = try await runGit(arguments: ["push", options.remote, "--tags"], in: repositoryURL)
            outputs.append(tagOutput)
        }
        return outputs.joined(separator: "\n")
    }

    func pull(remote: String, branch: String, options: PullOptions, in repositoryURL: URL) async throws -> String {
        var arguments = ["pull", remote, branch]
        if !options.commitMerged { arguments.append("--no-commit") }
        if !options.includeMessages { arguments.append("--no-log") }
        if options.noFastForward { arguments.append("--no-ff") }
        if options.rebaseInstead {
            arguments.append("--rebase")
        } else {
            arguments.append("--no-rebase")
        }
        return try await runGit(arguments: arguments, in: repositoryURL)
    }

    func pullBranchFromUpstream(branch: String, in repositoryURL: URL, options: PullOptions = PullOptions()) async throws -> String {
        guard let upstreamRef = await upstreamBranch(for: branch, in: repositoryURL) else {
            throw GitError.commandFailed("Branch '\(branch)' does not have an upstream branch.")
        }
        guard let remoteBranch = remoteBranchRef(from: upstreamRef) else {
            throw GitError.commandFailed("Could not parse upstream branch '\(upstreamRef)'.")
        }
        return try await pull(remote: remoteBranch.remote, branch: remoteBranch.branch, options: options, in: repositoryURL)
    }

    func fetch(options: FetchOptions, in repositoryURL: URL) async throws {
        var arguments = ["fetch"]
        if options.fetchAllRemotes {
            arguments.append("--all")
        }
        if options.prune {
            arguments.append("--prune")
        }
        if options.fetchTags {
            arguments.append("--tags")
        }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func remotes(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["remote"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func remoteBranches(remote: String, in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["branch", "-r", "--list", "\(remote)/*"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Remove leading "* " if present
            let clean = trimmed.hasPrefix("* ") ? String(trimmed.dropFirst(2)) : trimmed
            // Return just the branch name without remote prefix
            let prefix = "\(remote)/"
            if clean.hasPrefix(prefix) {
                return String(clean.dropFirst(prefix.count))
            }
            return clean
        }.filter { !$0.isEmpty }
    }

    func remoteURL(remote: String, in repositoryURL: URL) async -> String {
        let url = (try? await runGit(arguments: ["remote", "get-url", remote], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url
    }

    func addRemote(name: String, url: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "add", name, url], in: repositoryURL)
    }

    func removeRemote(name: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "remove", name], in: repositoryURL)
    }

    func setRemoteURL(name: String, url: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "set-url", name, url], in: repositoryURL)
    }

    private func remoteBranchRef(from upstreamRef: String) -> (remote: String, branch: String)? {
        let parts = upstreamRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (remote: String(parts[0]), branch: String(parts[1]))
    }
}
