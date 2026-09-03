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
import XCTest
@testable import macgit

final class RepositoryAIFileContextTests: XCTestCase {
    func testListsSeparateStagedAndWorkingTreeEvidenceForSameFile() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let file = repository.appending(path: "Example.swift")
        try "let value = 2\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Example.swift"], in: repository)
        try "let value = 3\n".write(to: file, atomically: true, encoding: .utf8)

        let files = try await GitStatusService.shared.listChangedFiles(in: repository)

        XCTAssertTrue(files.contains { $0.path == "Example.swift" && $0.source == .index })
        XCTAssertTrue(files.contains { $0.path == "Example.swift" && $0.source == .workingTree })
    }

    func testReadFileContextUsesSelectedIndexAndWorkingTreeVersions() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let file = repository.appending(path: "Example.swift")
        try "let value = 2\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Example.swift"], in: repository)
        try "let value = 3\n".write(to: file, atomically: true, encoding: .utf8)
        let files = try await GitStatusService.shared.listChangedFiles(in: repository)

        let staged = try XCTUnwrap(files.first { $0.path == "Example.swift" && $0.source == .index })
        let working = try XCTUnwrap(files.first { $0.path == "Example.swift" && $0.source == .workingTree })
        let service = GitStatusService.shared
        let stagedContext = try await service.readFileContext(staged, lineRange: nil, characterBudget: 1_000, in: repository)
        let workingContext = try await service.readFileContext(working, lineRange: nil, characterBudget: 1_000, in: repository)

        XCTAssertTrue(stagedContext.content.contains("let value = 2"))
        XCTAssertTrue(workingContext.content.contains("let value = 3"))
    }

    func testCitationValidatorRejectsInventedAndOutOfRangeCitations() throws {
        let range = try XCTUnwrap(RepositoryAITextRange(startLine: 1, endLine: 3))
        let reference = RepositoryAIFileReference(path: "Example.swift", source: .workingTree, objectID: nil, fingerprint: "fingerprint")
        let manifest = RepositoryAIEvidenceManifest(evidence: [RepositoryAIEvidence(
            id: "evidence-1", reference: reference, textRange: range, diffRanges: [], fingerprint: "fingerprint"
        )])
        let valid = RepositoryAICitation(evidenceID: "evidence-1", label: "Example.swift:2", textRange: try XCTUnwrap(RepositoryAITextRange(startLine: 2, endLine: 2)))
        let invented = RepositoryAICitation(evidenceID: "made-up", label: "Nope", textRange: range)
        let outOfRange = RepositoryAICitation(evidenceID: "evidence-1", label: "Example.swift:4", textRange: try XCTUnwrap(RepositoryAITextRange(startLine: 4, endLine: 4)))

        let result = manifest.validatedCitations(from: [valid, invented, outOfRange])
        XCTAssertEqual(result.accepted, [valid])
        XCTAssertEqual(result.rejected, [invented, outOfRange])
    }

    func testDeepSeekStyleCitationPayloadDecodesToAnswerInsteadOfRenderedJSON() throws {
        let payload = #"""
        {
          "text": "A grounded answer.",
          "citations": [{
            "evidenceID": "evidence-1",
            "label": "Example.swift staged diff",
            "textRange": {
              "start": { "offset": 295, "line": 295 },
              "end": { "offset": 379, "line": 379 }
            }
          }]
        }
        """#

        let answer = try RepositoryAIAnswerDecoder.decodeProviderText(payload)

        XCTAssertEqual(answer.text, "A grounded answer.")
        XCTAssertEqual(answer.citations.count, 1)
        XCTAssertEqual(answer.citations[0].textRange?.startLine, 295)
        XCTAssertEqual(answer.citations[0].textRange?.endLine, 379)
    }

    func testNonFileContextRecoversTextFromMalformedJSONInsteadOfRenderingTheWrapper() throws {
        let payload = #"{ "text": "The PR titled "implement Create Pull Request" is ready." }"#

        let answer = try RepositoryAIAnswerDecoder.decodeProviderText(payload)

        XCTAssertEqual(answer.text, "The PR titled \"implement Create Pull Request\" is ready.")
        XCTAssertTrue(answer.citations.isEmpty)
    }

    func testNonFileContextRecoversTextFromAnOutputLimitedJSONResponse() throws {
        let payload = #"{ "text": "The analysis was cut off before the JSON wrapper""#

        let answer = try RepositoryAIAnswerDecoder.decodeProviderText(payload)

        XCTAssertEqual(answer.text, "The analysis was cut off before the JSON wrapper")
    }

    func testFileContextStillRejectsMalformedCitationJSON() {
        let payload = #"{"summary":"Missing the required text field."}"#

        XCTAssertThrowsError(
            try RepositoryAIAnswerDecoder.decodeProviderText(payload, requiresStructuredResponse: true)
        ) { error in
            XCTAssertEqual(
                error as? RepositoryAIError,
                .invalidResponse("Repository AI returned malformed structured output.")
            )
        }
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory.appending(path: "repository-ai-file-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try runGit(["init"], in: repository)
        _ = try runGit(["config", "user.email", "test@example.com"], in: repository)
        _ = try runGit(["config", "user.name", "Repository AI Test"], in: repository)
        try "let value = 1\n".write(to: repository.appending(path: "Example.swift"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Example.swift"], in: repository)
        _ = try runGit(["commit", "-m", "Initial"], in: repository)
        return repository
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitError.commandFailed("test Git failure") }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
