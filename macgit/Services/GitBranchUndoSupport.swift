//
//  GitBranchUndoSupport.swift
//  macgit
//

import Foundation

struct GitBranchUndoSupport {
    private let runner: any GitCommandRunning

    init(runner: (any GitCommandRunning)? = nil) {
        self.runner = runner ?? GitStatusService.shared
    }

    func currentRef(in repositoryURL: URL) async throws -> String {
        let branch = try await runner.runGit(arguments: ["branch", "--show-current"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }

        return try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tip(of ref: String, in repositoryURL: URL) async throws -> String {
        try await runner.runGit(arguments: ["rev-parse", "\(ref)^{commit}"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func upstream(of branch: String, in repositoryURL: URL) async -> String? {
        let output = try? await runner.runGit(
            arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"],
            in: repositoryURL
        )
        let upstream = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return upstream?.isEmpty == false ? upstream : nil
    }
}
