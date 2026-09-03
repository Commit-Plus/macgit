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

import CryptoKit
import Foundation

nonisolated protocol RepositoryAIFileContextServicing: Sendable {
    func listChangedFiles(in repositoryURL: URL) async throws -> [RepositoryAIFileReference]
    func listChangedFiles(commit reference: String, in repositoryURL: URL) async throws -> [RepositoryAIFileReference]
    func readFileContext(
        _ reference: RepositoryAIFileReference,
        lineRange: RepositoryAITextRange?,
        characterBudget: Int,
        in repositoryURL: URL
    ) async throws -> RepositoryAIFileContext
    func readFileDiff(
        _ reference: RepositoryAIFileReference,
        contextLines: Int,
        maximumHunks: Int,
        characterBudget: Int,
        in repositoryURL: URL
    ) async throws -> RepositoryAIFileDiff
    func currentFingerprint(for reference: RepositoryAIFileReference, in repositoryURL: URL) async throws -> String
}

extension GitStatusService: RepositoryAIFileContextServicing {
    func listChangedFiles(in repositoryURL: URL) async throws -> [RepositoryAIFileReference] {
        let currentStatus = try await status(for: repositoryURL)
        let staged = try currentStatus.staged.map { file in
            try makeFileReference(path: file.path, source: .index, objectID: nil, fingerprint: "index")
        }
        let working = try (currentStatus.unstaged + currentStatus.untracked).map { file in
            try makeFileReference(path: file.path, source: .workingTree, objectID: nil, fingerprint: "working")
        }
        var references = [RepositoryAIFileReference]()
        for reference in staged + working {
            references.append(RepositoryAIFileReference(
                path: reference.path,
                source: reference.source,
                objectID: reference.objectID,
                fingerprint: try await currentFingerprint(for: reference, in: repositoryURL)
            ))
        }
        return references
    }

    func listChangedFiles(commit reference: String, in repositoryURL: URL) async throws -> [RepositoryAIFileReference] {
        let objectID = try await validatedCommitID(reference, in: repositoryURL)
        let output = try await runGitRaw(
            arguments: ["diff-tree", "--no-commit-id", "--name-only", "-r", "--find-renames", objectID, "--"],
            in: repositoryURL
        )
        guard let text = String(data: output, encoding: .utf8) else {
            throw RepositoryAIFileContextError.unsupportedContent
        }
        return try text.split(separator: "\n").map { path in
            try makeFileReference(path: String(path), source: .commit, objectID: objectID, fingerprint: objectID)
        }
    }

    func readFileContext(
        _ reference: RepositoryAIFileReference,
        lineRange: RepositoryAITextRange? = nil,
        characterBudget: Int,
        in repositoryURL: URL
    ) async throws -> RepositoryAIFileContext {
        try validate(reference)
        guard try await isEligible(reference, in: repositoryURL) else {
            throw RepositoryAIFileContextError.unavailableFile
        }

        let data: Data
        switch reference.source {
        case .workingTree:
            data = try readSafeWorkingTreeFile(reference.path, in: repositoryURL)
        case .index:
            data = try await runGitRaw(arguments: ["show", ":\(reference.path)"], in: repositoryURL)
        case .commit:
            guard let objectID = reference.objectID else { throw RepositoryAIFileContextError.unavailableFile }
            data = try await runGitRaw(arguments: ["show", "\(objectID):\(reference.path)"], in: repositoryURL)
        }

        let text = try utf8Text(from: data)
        let selected = boundedLines(from: text, requested: lineRange, characterBudget: characterBudget)
        let fingerprint = digest(data)
        let refreshed = RepositoryAIFileReference(path: reference.path, source: reference.source, objectID: reference.objectID, fingerprint: fingerprint)
        let evidence = RepositoryAIEvidence(
            id: UUID().uuidString,
            reference: refreshed,
            textRange: selected.range,
            diffRanges: [],
            fingerprint: fingerprint
        )
        return RepositoryAIFileContext(
            reference: refreshed,
            evidence: evidence,
            content: selected.content,
            isTruncated: selected.isTruncated,
            requestedRange: lineRange
        )
    }

    func readFileDiff(
        _ reference: RepositoryAIFileReference,
        contextLines: Int = 3,
        maximumHunks: Int = 12,
        characterBudget: Int,
        in repositoryURL: URL
    ) async throws -> RepositoryAIFileDiff {
        try validate(reference)
        guard try await isEligible(reference, in: repositoryURL) else {
            throw RepositoryAIFileContextError.unavailableFile
        }
        let context = min(20, max(0, contextLines))
        let arguments: [String]
        switch reference.source {
        case .workingTree:
            arguments = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=\(context)", "--", reference.path]
        case .index:
            arguments = ["diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=\(context)", "--", reference.path]
        case .commit:
            guard let objectID = reference.objectID else { throw RepositoryAIFileContextError.unavailableFile }
            arguments = ["show", "--format=", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=\(context)", objectID, "--", reference.path]
        }
        let raw = try await runGitRaw(arguments: arguments, in: repositoryURL)
        let text = try utf8Text(from: raw)
        let bounded = boundedDiff(text, maximumHunks: min(24, max(1, maximumHunks)), characterBudget: characterBudget)
        let fingerprint = try await currentFingerprint(for: reference, in: repositoryURL)
        let refreshed = RepositoryAIFileReference(path: reference.path, source: reference.source, objectID: reference.objectID, fingerprint: fingerprint)
        let evidence = RepositoryAIEvidence(
            id: UUID().uuidString,
            reference: refreshed,
            textRange: nil,
            diffRanges: parseDiffRanges(in: bounded.content),
            fingerprint: fingerprint
        )
        return RepositoryAIFileDiff(reference: refreshed, evidence: evidence, content: bounded.content, isTruncated: bounded.isTruncated)
    }

    func currentFingerprint(for reference: RepositoryAIFileReference, in repositoryURL: URL) async throws -> String {
        switch reference.source {
        case .workingTree:
            return digest(try readSafeWorkingTreeFile(reference.path, in: repositoryURL))
        case .index:
            return digest(try await runGitRaw(arguments: ["show", ":\(reference.path)"], in: repositoryURL))
        case .commit:
            guard let objectID = reference.objectID else { throw RepositoryAIFileContextError.unavailableFile }
            return digest(try await runGitRaw(arguments: ["show", "\(objectID):\(reference.path)"], in: repositoryURL))
        }
    }

    private func isEligible(_ reference: RepositoryAIFileReference, in repositoryURL: URL) async throws -> Bool {
        let candidates: [RepositoryAIFileReference]
        if reference.source == .commit, let objectID = reference.objectID {
            candidates = try await listChangedFiles(commit: objectID, in: repositoryURL)
        } else {
            candidates = try await listChangedFiles(in: repositoryURL)
        }
        return candidates.contains { candidate in
            candidate.path == reference.path && candidate.source == reference.source && candidate.objectID == reference.objectID
        }
    }

    private func validatedCommitID(_ reference: String, in repositoryURL: URL) async throws -> String {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: "^[A-Za-z0-9][A-Za-z0-9._/@{}~^+-]{0,199}$", options: .regularExpression) != nil else {
            throw RepositoryAIError.invalidCommitReference
        }
        let output = try await runGit(arguments: ["rev-parse", "--verify", "\(normalized)^{commit}"], in: repositoryURL)
        let objectID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard objectID.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil else {
            throw RepositoryAIError.invalidCommitReference
        }
        return objectID
    }

    private func makeFileReference(path: String, source: RepositoryAIFileSource, objectID: String?, fingerprint: String) throws -> RepositoryAIFileReference {
        try validatePath(path)
        return RepositoryAIFileReference(path: path, source: source, objectID: objectID, fingerprint: fingerprint)
    }

    private func validate(_ reference: RepositoryAIFileReference) throws {
        try validatePath(reference.path)
        if reference.source == .commit {
            guard let objectID = reference.objectID,
                  objectID.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil else {
                throw RepositoryAIFileContextError.invalidPath
            }
        } else if reference.objectID != nil {
            throw RepositoryAIFileContextError.invalidPath
        }
    }

    private func validatePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.contains("\0") else { throw RepositoryAIFileContextError.invalidPath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0 == ".git" }) else {
            throw RepositoryAIFileContextError.invalidPath
        }
    }

    private func readSafeWorkingTreeFile(_ path: String, in repositoryURL: URL) throws -> Data {
        try validatePath(path)
        let root = repositoryURL.resolvingSymlinksInPath().standardizedFileURL
        var candidate = root
        for component in path.split(separator: "/") {
            candidate.appendPathComponent(String(component))
            let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw RepositoryAIFileContextError.unsafeFile }
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else { throw RepositoryAIFileContextError.unsafeFile }
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw RepositoryAIFileContextError.unsafeFile }
        guard (values.fileSize ?? 0) <= 1_000_000 else { throw RepositoryAIFileContextError.unsupportedContent }
        return try Data(contentsOf: resolved, options: [.mappedIfSafe])
    }

    private func utf8Text(from data: Data) throws -> String {
        guard data.count <= 1_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw RepositoryAIFileContextError.unsupportedContent
        }
        return text
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func boundedLines(from text: String, requested: RepositoryAITextRange?, characterBudget: Int) -> (content: String, range: RepositoryAITextRange, isTruncated: Bool) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = requested?.startLine ?? 1
        let end = min(lines.count, requested?.endLine ?? lines.count)
        let selected = start <= end ? Array(lines[(start - 1)..<end]) : []
        var output = ""
        var includedEnd = start - 1
        let budget = max(400, characterBudget)
        for (offset, line) in selected.enumerated() {
            let numbered = "\(start + offset): \(line)\n"
            guard output.count + numbered.count <= budget else { break }
            output += numbered
            includedEnd = start + offset
        }
        let range = RepositoryAITextRange(startLine: start, endLine: max(start, includedEnd))!
        return (output, range, includedEnd < end)
    }

    private func boundedDiff(_ text: String, maximumHunks: Int, characterBudget: Int) -> (content: String, isTruncated: Bool) {
        let sections = text.components(separatedBy: "\n@@")
        let header = sections.first ?? ""
        let hunkSections = sections.dropFirst().prefix(maximumHunks).enumerated().map { index, section in
            "@@\(section)"
        }
        let joined = ([header] + hunkSections).joined(separator: "\n")
        let budget = max(400, characterBudget)
        return (String(joined.prefix(budget)), hunkSections.count < sections.dropFirst().count || joined.count > budget)
    }

    private func parseDiffRanges(in text: String) -> [RepositoryAIDiffRange] {
        text.split(separator: "\n").enumerated().compactMap { index, line in
            let values = String(line)
            guard values.hasPrefix("@@"),
                  let match = values.range(of: "@@ -([0-9]+)(?:,([0-9]+))? \\+([0-9]+)(?:,([0-9]+))? @@", options: .regularExpression) else { return nil }
            let header = String(values[match])
            let numbers = header.split { !$0.isNumber }.compactMap { Int($0) }
            guard numbers.count >= 2 else { return nil }
            let base = RepositoryAITextRange(startLine: numbers[0], endLine: numbers[0] + max(0, (numbers.count > 2 ? numbers[1] : 1) - 1))
            let headIndex = numbers.count > 2 ? 2 : 1
            let headCountIndex = numbers.count > 3 ? 3 : nil
            let head = RepositoryAITextRange(startLine: numbers[headIndex], endLine: numbers[headIndex] + max(0, (headCountIndex.map { numbers[$0] } ?? 1) - 1))
            return RepositoryAIDiffRange(hunkIndex: index, base: base, head: head)
        }
    }
}
