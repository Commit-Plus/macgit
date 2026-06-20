//
//  GitCommandRunning.swift
//  macgit
//

import Foundation

protocol GitCommandRunning {
    func runGit(arguments: [String], in directory: URL) async throws -> String
}

protocol GitPatchApplying {
    func applyPatch(_ patch: String, in repositoryURL: URL, cached: Bool, reverse: Bool) async throws
}

extension GitStatusService: GitCommandRunning {}
extension GitStatusService: GitPatchApplying {}
