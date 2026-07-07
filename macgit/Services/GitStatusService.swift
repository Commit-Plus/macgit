//
//  GitStatusService.swift
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

nonisolated private final class GitProcessExecution: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let directory: URL
    private let environment: [String: String]
    private let lock = NSLock()

    private var task: Process?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var continuation: CheckedContinuation<Data, Error>?
    private var didResume = false

    init(executable: String, arguments: [String], directory: URL, environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
    }

    func run() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(continuation: CheckedContinuation<Data, Error>) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = directory
        task.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        lock.lock()
        self.task = task
        self.stdout = stdout
        self.stderr = stderr
        self.continuation = continuation
        lock.unlock()

        task.terminationHandler = { [weak self] process in
            self?.finish(process: process)
        }

        do {
            try task.run()
        } catch {
            resume(throwing: GitError.gitNotFound)
        }
    }

    private func finish(process: Process) {
        let outData = stdout?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errData = stderr?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errorOutput = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let output = String(data: outData, encoding: .utf8) ?? ""
            let message = errorOutput.isEmpty ? output : errorOutput
            resume(throwing: GitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            resume(returning: outData)
        }
    }

    private func cancel() {
        lock.lock()
        let task = task
        let shouldTerminate = task?.isRunning == true
        lock.unlock()

        if shouldTerminate {
            task?.terminate()
        }
        resume(throwing: CancellationError())
    }

    private func resume(returning data: Data) {
        complete { continuation in
            continuation.resume(returning: data)
        }
    }

    private func resume(throwing error: Error) {
        complete { continuation in
            continuation.resume(throwing: error)
        }
    }

    private func complete(_ resume: (CheckedContinuation<Data, Error>) -> Void) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        self.task = nil
        self.stdout = nil
        self.stderr = nil
        lock.unlock()

        resume(continuation)
    }
}

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

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        let data = try await runGitRaw(arguments: arguments, in: directory, environment: environment)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runGitRaw(arguments: [String], in directory: URL) async throws -> Data {
        try await runGitRaw(
            arguments: arguments,
            in: directory,
            environment: ProcessInfo.processInfo.environment
        )
    }

    func runGitRaw(arguments: [String], in directory: URL, environment: [String: String]) async throws -> Data {
        try await GitProcessExecution(
            executable: gitExecutable(),
            arguments: arguments,
            directory: directory,
            environment: environment
        ).run()
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
        var paths: [String] = []
        var includeUntracked: Bool = false
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
