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

    init(
        runner: any GitCommandRunning = GitStatusService.shared,
        patchRunner: any GitPatchApplying = GitStatusService.shared
    ) {
        self.runner = runner
        self.patchRunner = patchRunner
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
