//
//  GitStatusService.swift
//  macgit
//

import Foundation

enum FileStatus: String, CaseIterable {
    case modified
    case staged
    case untracked
    case deleted
    case renamed
    case added
    case conflict

    var displayColor: String {
        switch self {
        case .staged, .added:
            return "green"
        case .modified, .deleted:
            return "red"
        case .untracked:
            return "grey"
        case .renamed:
            return "green"
        case .conflict:
            return "red"
        }
    }
}

struct StatusFile: Identifiable, Equatable, Hashable {
    let id = UUID()
    let path: String
    let status: FileStatus
    let originalPath: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var directory: String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().path
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "tif", "ico", "heic", "heif", "raw", "cr2", "nef", "arw", "dng"].contains(fileExtension)
    }

    var isBinary: Bool {
        let binaryExtensions = [
            // Archives
            "zip", "tar", "gz", "bz2", "7z", "rar", "xz", "lz4", "zst",
            // Documents
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf",
            // Executables / Packages
            "exe", "dll", "dmg", "pkg", "deb", "rpm", "apk", "ipa", "app", "msi",
            "so", "dylib", "a", "o", "class", "jar", "war", "ear",
            // Disk / ISO
            "iso", "img", "vmdk", "vhd",
            // Databases
            "db", "sqlite", "sqlite3", "mdb", "accdb",
            // Ebooks
            "mobi", "epub", "azw", "azw3",
            // Adobe / Design
            "psd", "ai", "indd", "sketch", "fig", "xd",
            // Audio
            "mp3", "aac", "ogg", "flac", "wav", "m4a", "wma", "aiff",
            // Video
            "mp4", "avi", "mov", "mkv", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp",
            // Fonts
            "otf", "ttf", "woff", "woff2", "eot",
            // Other binary
            "bin", "dat", "cache", "pdb", "mo", "po", "nib", "strings"
        ]
        return binaryExtensions.contains(fileExtension)
    }
}

struct GitStatus {
    let staged: [StatusFile]
    let unstaged: [StatusFile]
    let untracked: [StatusFile]

    var isEmpty: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty
    }
}

enum GitError: LocalizedError {
    case notARepository
    case gitNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "The selected folder is not a Git repository."
        case .gitNotFound:
            return "Git command not found. Please install Git."
        case .commandFailed(let message):
            return message
        }
    }
}

actor GitStatusService {
    static let shared = GitStatusService()

    private init() {}

    private func gitExecutable() -> String {
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

    private func runGit(arguments: [String], in directory: URL) async throws -> String {
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
                let output = String(data: outData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let message = errorOutput.isEmpty ? output : errorOutput
                    continuation.resume(throwing: GitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: GitError.gitNotFound)
            }
        }
    }

    func status(for repositoryURL: URL) async throws -> GitStatus {
        let output = try await runGit(arguments: ["status", "--porcelain", "--untracked-files=all"], in: repositoryURL)
        var staged: [StatusFile] = []
        var unstaged: [StatusFile] = []
        var untracked: [StatusFile] = []

        for line in output.split(separator: "\n") {
            let line = String(line)
            guard line.count >= 3 else { continue }
            let indexStatus = line.prefix(1)
            let worktreeStatus = line.dropFirst(1).prefix(1)
            let pathPart = String(line.dropFirst(3))

            // Parse renamed paths (R  old -> new)
            var path = pathPart
            var originalPath: String? = nil
            if indexStatus == "R" || worktreeStatus == "R" {
                let components = pathPart.split(separator: " -> ", maxSplits: 1)
                if components.count == 2 {
                    originalPath = String(components[0])
                    path = String(components[1])
                }
            }

            // Skip non-previewable binary files (but keep images)
            let tempFile = StatusFile(path: path, status: .modified, originalPath: originalPath)
            if tempFile.isBinary && !tempFile.isImage {
                continue
            }

            let indexChar = Character(String(indexStatus))
            let worktreeChar = Character(String(worktreeStatus))

            // Detect merge conflicts
            let isConflict = indexStatus == "U" || worktreeStatus == "U" ||
                             (indexStatus == "A" && worktreeStatus == "A") ||
                             (indexStatus == "D" && worktreeStatus == "D")

            if isConflict {
                if indexStatus != " " && indexStatus != "." {
                    staged.append(StatusFile(path: path, status: .conflict, originalPath: originalPath))
                }
                if worktreeStatus != " " && worktreeStatus != "." && worktreeStatus != "?" {
                    unstaged.append(StatusFile(path: path, status: .conflict, originalPath: originalPath))
                }
                continue
            }

            // Index status -> staged
            switch indexChar {
            case "M", "A", "D", "R", "C":
                let status: FileStatus = (indexChar == "A") ? .added :
                                         (indexChar == "D") ? .deleted :
                                         (indexChar == "R") ? .renamed :
                                         (indexChar == "C") ? .added : .staged
                staged.append(StatusFile(path: path, status: status, originalPath: originalPath))
            default:
                break
            }

            // Worktree status -> unstaged or untracked
            switch worktreeChar {
            case "M", "D":
                let status: FileStatus = (worktreeChar == "D") ? .deleted : .modified
                unstaged.append(StatusFile(path: path, status: status, originalPath: originalPath))
            case "?":
                untracked.append(StatusFile(path: path, status: .untracked, originalPath: nil))
            default:
                break
            }
        }

        return GitStatus(staged: staged, unstaged: unstaged, untracked: untracked)
    }

    func stage(file: StatusFile, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["add", file.path], in: repositoryURL)
    }

    func unstage(file: StatusFile, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["reset", "HEAD", "--", file.path], in: repositoryURL)
    }

    func stageAll(files: [StatusFile], in repositoryURL: URL) async throws {
        guard !files.isEmpty else { return }
        var arguments = ["add", "--"]
        arguments.append(contentsOf: files.map(\.path))
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func unstageAll(files: [StatusFile], in repositoryURL: URL) async throws {
        guard !files.isEmpty else { return }
        var arguments = ["reset", "HEAD", "--"]
        arguments.append(contentsOf: files.map(\.path))
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func discard(file: StatusFile, in repositoryURL: URL) async throws {
        if file.status == .untracked {
            // Remove untracked file from filesystem
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            try FileManager.default.removeItem(at: fileURL)
        } else {
            _ = try await runGit(arguments: ["checkout", "--", file.path], in: repositoryURL)
        }
    }

    func commit(message: String, in repositoryURL: URL, amend: Bool = false, noVerify: Bool = false, signOff: Bool = false) async throws {
        var arguments = ["commit", "-m", message]
        if amend { arguments.append("--amend") }
        if noVerify { arguments.append("--no-verify") }
        if signOff { arguments.append("--signoff") }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func gitUser(in repositoryURL: URL) async -> String? {
        let name = (try? await runGit(arguments: ["config", "user.name"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (try? await runGit(arguments: ["config", "user.email"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = name, !n.isEmpty, let e = email, !e.isEmpty else { return nil }
        return "\(n) <\(e)>"
    }

    func currentBranch(in repositoryURL: URL) async -> String? {
        let branch = (try? await runGit(arguments: ["branch", "--show-current"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let b = branch, !b.isEmpty else { return nil }
        return b
    }

    struct PushOptions {
        var remote: String = "origin"
        var branches: [String] = []
        var branchMappings: [String: String] = [:] // local branch -> remote branch name
        var pushTags: Bool = false
    }

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

    func localBranches(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["branch", "--format=%(refname:short)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func upstreamBranch(for branch: String, in repositoryURL: URL) async -> String? {
        let upstream = (try? await runGit(arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = upstream, !u.isEmpty, !u.contains("fatal:") else { return nil }
        return u
    }

    func setUpstream(remote: String, branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--set-upstream-to", "\(remote)/\(branch)", branch], in: repositoryURL)
    }

    struct PullOptions {
        var commitMerged: Bool = true
        var includeMessages: Bool = true
        var noFastForward: Bool = false
        var rebaseInstead: Bool = false
    }

    func pull(remote: String, branch: String, options: PullOptions, in repositoryURL: URL) async throws -> String {
        var arguments = ["pull", remote, branch]
        if !options.commitMerged { arguments.append("--no-commit") }
        if !options.includeMessages { arguments.append("--no-log") }
        if options.noFastForward { arguments.append("--no-ff") }
        if options.rebaseInstead { arguments.append("--rebase") }
        return try await runGit(arguments: arguments, in: repositoryURL)
    }

    func fetch(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["fetch"], in: repositoryURL)
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

    func aheadBehindCount(in repositoryURL: URL) async -> (ahead: Int, behind: Int) {
        let aheadOutput = (try? await runGit(arguments: ["rev-list", "--count", "@{upstream}..HEAD"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let behindOutput = (try? await runGit(arguments: ["rev-list", "--count", "HEAD..@{upstream}"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ahead = Int(aheadOutput ?? "0") ?? 0
        let behind = Int(behindOutput ?? "0") ?? 0
        return (ahead: ahead, behind: behind)
    }

    func hasConflicts(in repositoryURL: URL) async -> Bool {
        guard let status = try? await self.status(for: repositoryURL) else { return false }
        return status.staged.contains(where: { $0.status == .conflict })
            || status.unstaged.contains(where: { $0.status == .conflict })
            || status.untracked.contains(where: { $0.status == .conflict })
    }

    func remove(file: StatusFile, in repositoryURL: URL) async throws {
        if file.status == .untracked {
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            try FileManager.default.removeItem(at: fileURL)
        } else {
            _ = try await runGit(arguments: ["rm", "-f", file.path], in: repositoryURL)
        }
    }

    func ignore(file: StatusFile, in repositoryURL: URL) async throws {
        try await ignore(file: file, pattern: file.path, in: repositoryURL)
    }

    func ignore(file: StatusFile, pattern: String, in repositoryURL: URL) async throws {
        let gitignoreURL = repositoryURL.appendingPathComponent(".gitignore")
        let entry = "\(pattern)\n"

        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            let handle = try FileHandle(forWritingTo: gitignoreURL)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try entry.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }

        if file.status != .untracked {
            _ = try? await runGit(arguments: ["rm", "--cached", file.path], in: repositoryURL)
        }
    }

    enum ConflictResolution {
        case ours, theirs
    }

    func resolveConflict(file: StatusFile, in repositoryURL: URL, using: ConflictResolution) async throws {
        let flag = using == .ours ? "--ours" : "--theirs"
        _ = try await runGit(arguments: ["checkout", flag, "--", file.path], in: repositoryURL)
        _ = try await runGit(arguments: ["add", file.path], in: repositoryURL)
    }

    func resetToCommit(file: StatusFile, commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["checkout", commit, "--", file.path], in: repositoryURL)
    }

    func recentCommits(in repositoryURL: URL, count: Int = 10) async -> [(hash: String, message: String)] {
        let output = (try? await runGit(arguments: ["log", "--oneline", "-\(count)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let hash = parts.first else { return nil }
            let message = parts.count > 1 ? String(parts[1]) : ""
            return (hash: String(hash), message: message)
        }
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

    // MARK: - Hunk / Line Operations

    func stage(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot stage hunk for untracked file")
        }
        let patch = patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true)
    }

    func discard(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot discard hunk for untracked file")
        }
        let patch = patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, reverse: true)
    }

    func stage(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot stage lines for untracked file")
        }
        let patch = patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true)
    }

    func discard(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot discard lines for untracked file")
        }
        let patch = patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, reverse: true)
    }

    func unstage(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        let patch = patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true, reverse: true)
    }

    func unstage(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        let patch = patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true, reverse: true)
    }

    // MARK: - Patch Helpers

    private func applyPatch(_ patch: String, in repositoryURL: URL, cached: Bool = false, reverse: Bool = false) async throws {
        var arguments = ["apply"]
        if cached { arguments.append("--cached") }
        if reverse { arguments.append("--reverse") }
        arguments.append("-")

        let executable = gitExecutable()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        task.environment = ProcessInfo.processInfo.environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errData, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: GitError.commandFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume(returning: ())
                }
            }
            do {
                try task.run()
                if let data = patch.data(using: .utf8) {
                    stdin.fileHandleForWriting.write(data)
                }
                stdin.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: GitError.gitNotFound)
            }
        }
    }

    private func patchString(for hunk: DiffHunk, filePath: String) -> String {
        let linesStr = hunk.lines.map { line in
            switch line.type {
            case .added: return "+\(line.text)"
            case .removed: return "-\(line.text)"
            case .context: return " \(line.text)"
            case .header: return line.text
            case .conflictMarker: return " \(line.text)"
            }
        }.joined(separator: "\n")
        return "--- a/\(filePath)\n+++ b/\(filePath)\n\(hunk.header)\n\(linesStr)\n"
    }

    private func patchString(for hunk: DiffHunk, selectedLines: [DiffLine], filePath: String) -> String {
        let selectedIDs = Set(selectedLines.map(\.id))

        var oldCount = 0
        var newCount = 0
        var filteredLines: [String] = []

        for line in hunk.lines {
            switch line.type {
            case .context:
                filteredLines.append(" \(line.text)")
                oldCount += 1
                newCount += 1
            case .added:
                if selectedIDs.contains(line.id) {
                    filteredLines.append("+\(line.text)")
                    newCount += 1
                }
            case .removed:
                if selectedIDs.contains(line.id) {
                    filteredLines.append("-\(line.text)")
                    oldCount += 1
                }
            case .header:
                filteredLines.append(line.text)
            case .conflictMarker:
                filteredLines.append(" \(line.text)")
                oldCount += 1
                newCount += 1
            }
        }

        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)) else {
            return patchString(for: hunk, filePath: filePath)
        }

        let oldStart = Int(hunk.header[Range(match.range(at: 1), in: hunk.header)!])!
        let newStart = Int(hunk.header[Range(match.range(at: 3), in: hunk.header)!])!

        let newHeader = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        let linesStr = filteredLines.joined(separator: "\n")
        return "--- a/\(filePath)\n+++ b/\(filePath)\n\(newHeader)\n\(linesStr)\n"
    }
}

// MARK: - Diff Parser

enum DiffLineType {
    case context
    case added
    case removed
    case header
    case conflictMarker
}

struct DiffLine: Identifiable {
    let id = UUID()
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
    let type: DiffLineType
}

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

enum DiffParser {
    static func parse(_ raw: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var currentHeader = ""
        var oldLine = 0
        var newLine = 0

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var inHunk = false

        for line in lines {
            let text = String(line)

            if text.hasPrefix("@@") {
                // Start of hunk
                if inHunk {
                    hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
                }
                inHunk = true
                currentHeader = text
                currentLines = []

                // Parse line numbers: @@ -start,count +start,count @@
                if let range = text.range(of: "@@ -"),
                   let atRange = text[range.upperBound...].range(of: " @@") {
                    let numbersPart = String(text[range.upperBound..<atRange.lowerBound])
                    let parts = numbersPart.split(separator: " ")
                    if parts.count == 2 {
                        let oldPart = parts[0].split(separator: ",")
                        let newPart = parts[1].split(separator: ",")
                        oldLine = Int(oldPart[0]) ?? 0
                        if oldPart.count > 1, let count = Int(oldPart[1]), count == 0 {
                            // Deleted file or new file
                        }
                        newLine = Int(String(newPart[0]).dropFirst()) ?? 0
                    }
                }
                continue
            }

            if !inHunk {
                continue
            }

            guard !text.isEmpty else {
                currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: nil, text: "", type: .context))
                continue
            }

            let prefix = text.prefix(1)
            let content = String(text.dropFirst())
            let isConflictMarker = content.hasPrefix("<<<<<<<") || content.hasPrefix("=======") || content.hasPrefix(">>>>>>>")

            switch prefix {
            case "+":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: newLine, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: newLine, text: content, type: .added))
                }
                newLine += 1
            case "-":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: nil, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: nil, text: content, type: .removed))
                }
                oldLine += 1
            case " ":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: newLine, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: newLine, text: content, type: .context))
                }
                oldLine += 1
                newLine += 1
            case "\\":
                // "\ No newline at end of file"
                currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: nil, text: text, type: .header))
            default:
                break
            }
        }

        if inHunk && !currentLines.isEmpty {
            hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
        }

        return hunks
    }
}
