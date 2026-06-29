//
//  GitStatusService+Diff.swift
//  macgit
//

import Foundation

extension GitStatusService {
    func diff(for file: String, in commit: String, in repositoryURL: URL) async -> [DiffHunk] {
        if isStashRef(commit) {
            let output = (try? await runGit(arguments: ["diff", "--no-color", "-U3", "\(commit)^1", commit, "--", file], in: repositoryURL)) ?? ""
            return DiffParser.parse(output)
        }

        let output = (try? await runGit(arguments: ["show", "--no-color", "-p", commit, "--", file], in: repositoryURL)) ?? ""
        // Strip the commit header; diff starts at "diff --git"
        guard let diffStart = output.range(of: "diff --git") else { return [] }
        let diffText = String(output[diffStart.lowerBound...])
        return DiffParser.parse(diffText)
    }

    func diff(for file: StatusFile, in repositoryURL: URL) async throws -> [DiffHunk] {
        // Untracked file → read directly and show all lines as added (green)
        if file.status == .untracked {
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            let diffLines = lines.enumerated().map { index, line in
                DiffLine(oldLineNumber: nil, newLineNumber: index + 1, text: String(line), type: .added)
            }
            return [DiffHunk(header: "@@ -0,0 +1,\(lines.count) @@", lines: diffLines)]
        }

        // Deleted file → get old content from HEAD and show all lines as removed (red)
        if file.status == .deleted {
            let output = try await runGit(arguments: ["show", "HEAD:\(file.path)"], in: repositoryURL)
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            let diffLines = lines.enumerated().map { index, line in
                DiffLine(oldLineNumber: index + 1, newLineNumber: nil, text: String(line), type: .removed)
            }
            return [DiffHunk(header: "@@ -1,\(lines.count) +0,0 @@", lines: diffLines)]
        }

        // Normal diff for modified/renamed/staged files
        let isStaged = file.status == .staged || file.status == .added || file.status == .renamed
        var arguments = ["diff", "--no-color", "-U3"]
        if isStaged {
            arguments.append("--cached")
        }
        arguments.append("--")
        arguments.append(file.path)

        let output = try await runGit(arguments: arguments, in: repositoryURL)
        return DiffParser.parse(output)
    }

    func showFile(at path: String, ref: String, in repositoryURL: URL) async throws -> Data {
        try await runGitRaw(arguments: ["show", "\(ref):\(path)"], in: repositoryURL)
    }

    func changedFiles(in commit: String, in repositoryURL: URL) async -> [CommitFileChange] {
        let output = (try? await runGit(arguments: ["show", "--name-status", "--format=", commit], in: repositoryURL)) ?? ""
        var changes: [CommitFileChange] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            let statusCode = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path: String
            if (statusCode.hasPrefix("R") || statusCode.hasPrefix("C")) && parts.count >= 3 {
                path = String(parts[2])
            } else {
                path = String(parts[1])
            }

            let status: CommitFileStatus
            switch statusCode.prefix(1) {
            case "A": status = .added
            case "M": status = .modified
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            default: status = .modified
            }
            changes.append(CommitFileChange(path: path, status: status))
        }
        return changes
    }

    func checkoutCommit(_ commit: String, force: Bool = false, in repositoryURL: URL) async throws {
        var arguments = ["checkout"]
        if force { arguments.append("-f") }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func cherryPickCommit(_ commit: String, in repositoryURL: URL) async throws {
        try await cherryPickCommits([commit], in: repositoryURL)
    }

    func cherryPickCommits(_ commits: [String], in repositoryURL: URL) async throws {
        guard !commits.isEmpty else {
            throw GitError.commandFailed("Select at least one commit to cherry-pick.")
        }
        _ = try await runGit(arguments: ["cherry-pick"] + commits, in: repositoryURL)
    }

    @discardableResult
    func cherryPickCommits(
        _ commits: [String],
        onto targetBranch: String,
        in repositoryURL: URL
    ) async throws -> GitCherryPickExecutionLocation {
        guard !commits.isEmpty else {
            throw GitError.commandFailed("Select at least one commit to cherry-pick.")
        }

        let currentBranch = await currentBranch(in: repositoryURL)
        if currentBranch == targetBranch {
            try await cherryPickCommits(commits, in: repositoryURL)
            return .currentWorkingCopy
        }

        if let existingWorktree = try await worktreePath(for: targetBranch, in: repositoryURL) {
            do {
                try await cherryPickCommits(commits, in: existingWorktree)
                return .existingWorktree(existingWorktree)
            } catch {
                throw await worktreeCherryPickError(
                    from: error,
                    path: existingWorktree,
                    kind: .existing
                )
            }
        }

        let temporaryWorktree = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("macgit-cherry-pick-\(UUID().uuidString)", isDirectory: true)
        _ = try await runGit(
            arguments: ["worktree", "add", temporaryWorktree.path, targetBranch],
            in: repositoryURL
        )

        do {
            try await cherryPickCommits(commits, in: temporaryWorktree)
        } catch {
            let cherryPickError = await worktreeCherryPickError(
                from: error,
                path: temporaryWorktree,
                kind: .temporary
            )
            if cherryPickError.isConflict {
                throw cherryPickError
            }

            let abortError = await cleanupError {
                _ = try await runGit(arguments: ["cherry-pick", "--abort"], in: temporaryWorktree)
            }
            do {
                _ = try await runGit(
                    arguments: ["worktree", "remove", temporaryWorktree.path, "--force"],
                    in: repositoryURL
                )
            } catch {
                let cleanupDetails = [abortError, error.localizedDescription]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                throw GitCherryPickWorktreeError(
                    path: temporaryWorktree,
                    kind: .temporary,
                    isConflict: false,
                    gitMessage: cherryPickError.gitMessage,
                    cleanupMessage: cleanupDetails
                )
            }

            throw error
        }

        do {
            _ = try await runGit(
                arguments: ["worktree", "remove", temporaryWorktree.path],
                in: repositoryURL
            )
        } catch {
            throw GitCherryPickWorktreeError(
                path: temporaryWorktree,
                kind: .temporary,
                isConflict: false,
                gitMessage: "Cherry-pick succeeded, but the temporary worktree could not be removed.",
                cleanupMessage: error.localizedDescription
            )
        }

        return .temporaryWorktree
    }

    private func worktreeCherryPickError(
        from error: Error,
        path: URL,
        kind: GitCherryPickWorktreeError.WorktreeKind
    ) async -> GitCherryPickWorktreeError {
        let message = error.localizedDescription
        let hasCherryPickHead = (try? await runGit(
            arguments: ["rev-parse", "--verify", "CHERRY_PICK_HEAD"],
            in: path
        )) != nil
        return GitCherryPickWorktreeError(
            path: path,
            kind: kind,
            isConflict: hasCherryPickHead || message.localizedCaseInsensitiveContains("conflict"),
            gitMessage: message,
            cleanupMessage: nil
        )
    }

    private func cleanupError(_ operation: () async throws -> Void) async -> String? {
        do {
            try await operation()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func mergeCommit(_ commit: String, noCommit: Bool = false, log: Bool = false, in repositoryURL: URL) async throws {
        var arguments = ["merge"]
        if noCommit { arguments.append("--no-commit") }
        if log { arguments.append("--log") }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func rebaseCommit(_ commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["rebase", commit], in: repositoryURL)
    }

    func resetToCommit(_ commit: String, mode: ResetMode, in repositoryURL: URL) async throws {
        let flag: String
        switch mode {
        case .soft: flag = "--soft"
        case .mixed: flag = "--mixed"
        case .hard: flag = "--hard"
        }
        _ = try await runGit(arguments: ["reset", flag, commit], in: repositoryURL)
    }

    func revertCommit(_ commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--no-edit", commit], in: repositoryURL)
    }

    func inProgressOperation(in repositoryURL: URL) async -> GitInProgressOperation? {
        if let head = try? await runGit(arguments: ["rev-parse", "--verify", "CHERRY_PICK_HEAD"], in: repositoryURL),
           !head.isEmpty {
            return .cherryPick(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let head = try? await runGit(arguments: ["rev-parse", "--verify", "REVERT_HEAD"], in: repositoryURL),
           !head.isEmpty {
            return .revert(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func continueCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--continue"], in: repositoryURL)
    }

    func abortCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--abort"], in: repositoryURL)
    }

    func continueRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--continue"], in: repositoryURL)
    }

    func abortRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--abort"], in: repositoryURL)
    }

    func skipCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--skip"], in: repositoryURL)
    }

    func skipRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--skip"], in: repositoryURL)
    }

    func createTag(name: String, commit: String, annotated: Bool, message: String?, in repositoryURL: URL) async throws {
        var arguments = ["tag"]
        if annotated {
            arguments.append("-a")
        }
        arguments.append(name)
        if annotated, let message = message, !message.isEmpty {
            arguments.append("-m")
            arguments.append(message)
        }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    private func isStashRef(_ ref: String) -> Bool {
        ref.hasPrefix("stash@{")
    }
}

enum ResetMode {
    case soft, mixed, hard
}
