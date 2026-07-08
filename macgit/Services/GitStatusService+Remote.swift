//
//  GitStatusService+Remote.swift
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
    func push(
        options: PushOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector()
    ) async throws -> String {
        let injection = try await credentialInjection(
            for: options.remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector
        )
        defer { injection?.cleanup() }

        var outputs: [String] = []
        for branch in options.branches {
            let remoteBranch = options.branchMappings[branch] ?? branch
            let refSpec = remoteBranch == branch ? branch : "\(branch):\(remoteBranch)"
            let output = try await runRemoteGit(
                arguments: ["push", options.remote, refSpec],
                in: repositoryURL,
                injection: injection
            )
            outputs.append(output)
        }
        if options.pushTags {
            let tagOutput = try await runRemoteGit(
                arguments: ["push", options.remote, "--tags"],
                in: repositoryURL,
                injection: injection
            )
            outputs.append(tagOutput)
        }
        return outputs.joined(separator: "\n")
    }

    func pull(
        remote: String,
        branch: String,
        options: PullOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector()
    ) async throws -> String {
        var arguments = ["pull", remote, branch]
        if !options.commitMerged { arguments.append("--no-commit") }
        if !options.includeMessages { arguments.append("--no-log") }
        if options.noFastForward { arguments.append("--no-ff") }
        if options.rebaseInstead {
            arguments.append("--rebase")
        } else {
            arguments.append("--no-rebase")
        }
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector
        )
        defer { injection?.cleanup() }
        return try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
    }

    func pullBranchFromUpstream(
        branch: String,
        in repositoryURL: URL,
        options: PullOptions = PullOptions(),
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws -> String {
        guard let upstreamRef = await upstreamBranch(for: branch, in: repositoryURL) else {
            throw GitError.commandFailed("Branch '\(branch)' does not have an upstream branch.")
        }
        guard let remoteBranch = remoteBranchRef(from: upstreamRef) else {
            throw GitError.commandFailed("Could not parse upstream branch '\(upstreamRef)'.")
        }
        return try await pull(
            remote: remoteBranch.remote,
            branch: remoteBranch.branch,
            options: options,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )
    }

    func fetch(
        options: FetchOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector()
    ) async throws {
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
        let injection = try await credentialInjectionForFetch(
            options: options,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
    }

    func fetchBranch(
        remote: String,
        branch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector()
    ) async throws {
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(arguments: ["fetch", remote, branch], in: repositoryURL, injection: injection)
    }

    func fetchPullRequestRef(
        remote: String,
        reference: String,
        localBranch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector()
    ) async throws {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalBranch = localBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedReference.isEmpty, !trimmedLocalBranch.isEmpty else {
            throw GitError.commandFailed("Pull request fetch reference is required.")
        }

        let injection = try await credentialInjection(
            for: trimmedRemote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector
        )
        defer { injection?.cleanup() }

        let refspec = "\(trimmedReference):refs/heads/\(trimmedLocalBranch)"
        _ = try await runRemoteGit(arguments: ["fetch", trimmedRemote, refspec], in: repositoryURL, injection: injection)
    }

    @discardableResult
    func checkoutRemoteBranch(remote: String, branch: String, in repositoryURL: URL) async throws -> String {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedBranch.isEmpty else {
            throw GitError.commandFailed("Remote branch is required.")
        }
        guard trimmedBranch != "HEAD" else {
            throw GitError.commandFailed("Cannot checkout a remote HEAD symbolic ref.")
        }

        let localBranches = await localBranches(in: repositoryURL)
        if localBranches.contains(trimmedBranch) {
            _ = try await runGit(arguments: ["checkout", trimmedBranch], in: repositoryURL)
            return trimmedBranch
        }

        _ = try await runGit(
            arguments: ["checkout", "-b", trimmedBranch, "--track", "\(trimmedRemote)/\(trimmedBranch)"],
            in: repositoryURL
        )
        return trimmedBranch
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

    private func runRemoteGit(
        arguments: [String],
        in repositoryURL: URL,
        injection: GitCredentialInjection?
    ) async throws -> String {
        if let injection {
            return try await runGit(arguments: arguments, in: repositoryURL, environment: injection.environment)
        }
        return try await runGit(arguments: arguments, in: repositoryURL)
    }

    private func credentialInjection(
        for remote: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        credentialInjector: GitCredentialInjecting
    ) async throws -> GitCredentialInjection? {
        guard let credentialResolver else { return nil }
        let remoteURLString = await remoteURL(remote: remote, in: repositoryURL)
        guard let credential = try credentialResolver.credential(for: remoteURLString) else { return nil }
        return try credentialInjector.injection(for: credential)
    }

    private func credentialInjectionForFetch(
        options: FetchOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        credentialInjector: GitCredentialInjecting
    ) async throws -> GitCredentialInjection? {
        guard let credentialResolver else { return nil }
        let remoteNames = await remotes(in: repositoryURL)
        let credentials = try await remoteNames.asyncCompactMap { remote -> GitCredential? in
            let remoteURLString = await remoteURL(remote: remote, in: repositoryURL)
            return try credentialResolver.credential(for: remoteURLString)
        }
        let uniqueCredentials = credentials.reduce(into: [GitCredential]()) { result, credential in
            if !result.contains(credential) {
                result.append(credential)
            }
        }
        guard let credential = uniqueCredentials.first else { return nil }
        guard uniqueCredentials.count == 1 else {
            throw GitProviderCredentialError.multipleMatchingAccounts(host: "configured remotes")
        }
        return try credentialInjector.injection(for: credential)
    }
}

private extension Sequence {
    func asyncCompactMap<Element>(
        _ transform: (Self.Element) async throws -> Element?
    ) async throws -> [Element] {
        var values: [Element] = []
        for element in self {
            if let value = try await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
