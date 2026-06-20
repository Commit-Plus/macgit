//
//  GitUndoExecutor.swift
//  macgit
//

import Foundation

enum GitUndoError: LocalizedError, Equatable {
    case emptyPathList
    case expectedHeadMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .emptyPathList:
            return "Cannot undo this Git action because it does not contain any file paths."
        case .expectedHeadMismatch(let expected, let actual):
            return "Cannot undo because HEAD moved. Expected \(expected), but found \(actual)."
        }
    }
}

struct GitUndoExecutor {
    private let runner: any GitCommandRunning
    private let patchRunner: any GitPatchApplying
    private let stashSupport: GitStashUndoSupport
    private let branchSupport: GitBranchUndoSupport

    init(
        runner: (any GitCommandRunning)? = nil,
        patchRunner: (any GitPatchApplying)? = nil,
        stashSupport: GitStashUndoSupport? = nil,
        branchSupport: GitBranchUndoSupport? = nil
    ) {
        let resolvedRunner = runner ?? GitStatusService.shared
        self.runner = resolvedRunner
        self.patchRunner = patchRunner ?? GitStatusService.shared
        self.stashSupport = stashSupport ?? GitStashUndoSupport(runner: resolvedRunner)
        self.branchSupport = branchSupport ?? GitBranchUndoSupport(runner: resolvedRunner)
    }

    func execute(_ operation: GitUndoOperation, in repositoryURL: URL) async throws {
        switch operation {
        case .stageFiles(let paths):
            try await runFileCommand(["add", "--"], paths: paths, in: repositoryURL)
        case .unstageFiles(let paths):
            try await runFileCommand(["reset", "HEAD", "--"], paths: paths, in: repositoryURL)
        case .applyPatch(let patch, let cached, let reverse):
            try await patchRunner.applyPatch(patch, in: repositoryURL, cached: cached, reverse: reverse)
        case .resetHead(let target, let mode, let expectedHead):
            if let expectedHead {
                let actual = try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard actual == expectedHead else {
                    throw GitUndoError.expectedHeadMismatch(expected: expectedHead, actual: actual)
                }
            }
            _ = try await runner.runGit(arguments: ["reset", mode.flag, target], in: repositoryURL)
        case .commit(let message, let noVerify, let signOff):
            var arguments = ["commit", "-m", message]
            if noVerify { arguments.append("--no-verify") }
            if signOff { arguments.append("--signoff") }
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .stashPush(let message, let keepIndex):
            var arguments = ["stash", "push"]
            if keepIndex { arguments.append("--keep-index") }
            if !message.isEmpty {
                arguments.append(contentsOf: ["-m", message])
            }
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .stashApply(let ref):
            _ = try await runner.runGit(arguments: ["stash", "apply", ref], in: repositoryURL)
        case .stashApplyAndDrop(let hash):
            _ = try await runner.runGit(arguments: ["stash", "apply", hash], in: repositoryURL)
            try await stashSupport.dropStash(matchingHash: hash, in: repositoryURL)
        case .stashStore(let commit, let message):
            _ = try await runner.runGit(arguments: ["stash", "store", "-m", message, commit], in: repositoryURL)
        case .stashDropMatchingHash(let hash):
            try await stashSupport.dropStash(matchingHash: hash, in: repositoryURL)
        case .checkoutRef(let ref):
            _ = try await runner.runGit(arguments: ["checkout", ref], in: repositoryURL)
        case .createLocalBranch(let name, let startPoint, let checkout):
            if checkout {
                _ = try await runner.runGit(arguments: ["checkout", "-b", name, startPoint], in: repositoryURL)
            } else {
                _ = try await runner.runGit(arguments: ["branch", name, startPoint], in: repositoryURL)
            }
        case .deleteLocalBranch(let name, let force, let expectedTip):
            if let expectedTip {
                let actualTip = try await branchSupport.tip(of: name, in: repositoryURL)
                guard actualTip == expectedTip else {
                    throw GitError.commandFailed("Cannot delete branch '\(name)' because its tip changed.")
                }
            }
            let flag = force ? "-D" : "-d"
            _ = try await runner.runGit(arguments: ["branch", flag, name], in: repositoryURL)
        case .setUpstream(let branch, let upstream):
            _ = try await runner.runGit(
                arguments: ["branch", "--set-upstream-to", upstream, branch],
                in: repositoryURL
            )
        case .sequence(let operations):
            for operation in operations {
                try await execute(operation, in: repositoryURL)
            }
        case .resetHardToHead(let expectedHead):
            if let expectedHead {
                let actual = try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard actual == expectedHead else {
                    throw GitUndoError.expectedHeadMismatch(expected: expectedHead, actual: actual)
                }
            }
            _ = try await runner.runGit(arguments: ["reset", "--hard", "HEAD"], in: repositoryURL)
        case .stashPop(let ref):
            _ = try await runner.runGit(arguments: ["stash", "pop", ref], in: repositoryURL)
        }
    }

    private func runFileCommand(_ prefix: [String], paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else {
            throw GitUndoError.emptyPathList
        }
        var arguments = prefix
        arguments.append(contentsOf: paths)
        _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
    }
}
