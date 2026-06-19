//
//  GitCommandRunning.swift
//  macgit
//

import Foundation

protocol GitCommandRunning {
    func runGit(arguments: [String], in directory: URL) async throws -> String
}

extension GitStatusService: GitCommandRunning {}
