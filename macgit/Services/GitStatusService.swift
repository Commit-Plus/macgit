//
//  GitStatusService.swift
//  macgit
//

import Foundation

actor GitStatusService {
    static let shared = GitStatusService()

    private init() {}

    func gitExecutable() -> String {
        // Prefer system git, fallback to /usr/bin/git
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["git"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            // fallthrough
        }
        return "/usr/bin/git"
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        let data = try await runGitRaw(arguments: arguments, in: directory)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runGitRaw(arguments: [String], in directory: URL) async throws -> Data {
        let executable = gitExecutable()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = directory
        task.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let message = errorOutput.isEmpty ? output : errorOutput
                    continuation.resume(throwing: GitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume(returning: outData)
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: GitError.gitNotFound)
            }
        }
    }

    struct PushOptions {
        var remote: String = "origin"
        var branches: [String] = []
        var branchMappings: [String: String] = [:] // local branch -> remote branch name
        var pushTags: Bool = false
    }

    struct PullOptions {
        var commitMerged: Bool = true
        var includeMessages: Bool = true
        var noFastForward: Bool = false
        var rebaseInstead: Bool = false
    }

    struct MergeOptions {
        var noFastForward: Bool = false
        var squash: Bool = false
        var message: String = ""
    }

    struct StashOptions {
        var message: String = ""
        var keepIndex: Bool = false
    }

    struct FetchOptions {
        var fetchAllRemotes: Bool = true
        var prune: Bool = false
        var fetchTags: Bool = false
    }

    enum ConflictResolution {
        case ours, theirs
    }
}
