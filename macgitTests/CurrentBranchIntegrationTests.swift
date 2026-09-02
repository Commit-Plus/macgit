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

import XCTest
@testable import macgit

@MainActor
final class CurrentBranchIntegrationTests: XCTestCase {
    func testCurrentFeatureDetectsRemoteDefaultBranchDrift() async throws {
        let fixture = try makeFixture(conflictingBaseChange: false)

        let status = await GitStatusService.shared.currentBranchIntegrationStatus(
            branch: "feature/demo",
            preferredRemote: "origin",
            gitFlowConfiguration: GitFlowConfiguration(),
            in: fixture.localURL
        )

        XCTAssertEqual(status?.upstreamBehindCount, 0)
        XCTAssertEqual(status?.baseBranch, "main")
        XCTAssertEqual(status?.baseRef, "origin/main")
        XCTAssertEqual(status?.baseBehindCount, 1)
        XCTAssertEqual(status?.predictsBaseConflict, false)
        XCTAssertEqual(status?.predictedBaseConflictPaths, [])
        XCTAssertEqual(status?.baseIncomingChangePaths, Set(["main.txt"]))
    }

    func testCurrentFeaturePredictsTextualBaseConflict() async throws {
        let fixture = try makeFixture(conflictingBaseChange: true)

        let status = await GitStatusService.shared.currentBranchIntegrationStatus(
            branch: "feature/demo",
            preferredRemote: "origin",
            gitFlowConfiguration: GitFlowConfiguration(),
            in: fixture.localURL
        )

        XCTAssertEqual(status?.baseBehindCount, 1)
        XCTAssertEqual(status?.predictsBaseConflict, true)
        XCTAssertEqual(status?.predictedBaseConflictPaths, Set(["shared.txt"]))
        XCTAssertEqual(status?.baseIncomingChangePaths, Set(["shared.txt"]))
    }

    func testDirtyFileChangedByBaseIsMarkedAsPotentialConflict() async throws {
        let fixture = try makeFixture(
            featureChangesSharedFile: false,
            baseChangesSharedFile: true
        )
        try "local worktree edit\n".write(
            to: fixture.localURL.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )

        let status = await GitStatusService.shared.currentBranchIntegrationStatus(
            branch: "feature/demo",
            preferredRemote: "origin",
            gitFlowConfiguration: GitFlowConfiguration(),
            in: fixture.localURL
        )
        let gitStatus = try await GitStatusService.shared.status(for: fixture.localURL)
        let dirtySharedFile = try XCTUnwrap(
            gitStatus.unstaged.first(where: { $0.path == "shared.txt" })
        )

        XCTAssertEqual(status?.predictsBaseConflict, false)
        XCTAssertEqual(status?.predictedBaseConflictPaths, [])
        XCTAssertEqual(status?.baseIncomingChangePaths, Set(["shared.txt"]))
        XCTAssertTrue(status?.potentialConflictPaths.contains(dirtySharedFile.path) == true)

        let loadedStatus = try XCTUnwrap(status)
        let analysis = await GitStatusService.shared.potentialConflictFileAnalysis(
            for: dirtySharedFile,
            status: loadedStatus,
            in: fixture.localURL
        )
        XCTAssertTrue(analysis.exactAnalysisPerformed)
        XCTAssertFalse(analysis.conflictBlocks.isEmpty)
    }

    func testMergeTreeConflictPathParserSupportsNULTerminatedNames() {
        let treeOID = String(repeating: "a", count: 40)
        let output = "\(treeOID)\0Sources/App.swift\0docs/read me.md\0"

        XCTAssertEqual(
            GitStatusService.mergeTreeConflictPaths(from: output),
            Set(["Sources/App.swift", "docs/read me.md"])
        )
    }

    func testPathListParserSupportsNULTerminatedNames() {
        XCTAssertEqual(
            GitStatusService.pathList(from: "Sources/App.swift\0docs/read me.md\0"),
            Set(["Sources/App.swift", "docs/read me.md"])
        )
    }

    func testConflictBlocksKeepsOnlyConflictRegionsWithContext() {
        let output = """
        first
        second
        <<<<<<< Local changes
        local
        ||||||| Merge base
        base
        =======
        incoming
        >>>>>>> origin/main
        after
        last
        """

        let blocks = GitStatusService.conflictBlocks(from: output, contextLineCount: 1)

        XCTAssertEqual(
            blocks.map { $0.lines.map(\.text).joined(separator: "\n") },
            [
                """
                second
                <<<<<<< Local changes
                local
                ||||||| Merge base
                base
                =======
                incoming
                >>>>>>> origin/main
                after
                """
            ]
        )
    }

    func testConflictBlocksCanExcludeContextOutsideConflictRegions() {
        let output = """
        before
        <<<<<<< Local changes
        local
        =======
        incoming
        >>>>>>> origin/main
        after
        """

        let blocks = GitStatusService.conflictBlocks(from: output, contextLineCount: 0)

        XCTAssertEqual(
            blocks.first?.lines.map(\.text).joined(separator: "\n"),
            """
            <<<<<<< Local changes
            local
            =======
            incoming
            >>>>>>> origin/main
            """
        )
    }

    func testConflictBlocksRenderEveryConflictAndKeepOriginalLineNumbers() {
        let output = """
        before
        <<<<<<< Local changes
        local one
        =======
        incoming one
        >>>>>>> origin/main
        between
        <<<<<<< Local changes
        local two
        =======
        incoming two
        >>>>>>> origin/main
        after
        """

        let blocks = GitStatusService.conflictBlocks(from: output, contextLineCount: 0)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].lines.map(\.lineNumber), Array(2...6))
        XCTAssertEqual(blocks[1].lines.map(\.lineNumber), Array(8...12))
    }

    func testGitFlowFeatureUsesConfiguredDevelopBranchAsBase() async throws {
        let fixture = try makeFixture(conflictingBaseChange: false)
        try git(["checkout", "-b", "develop"], in: fixture.updaterURL)
        try "develop\n".write(
            to: fixture.updaterURL.appendingPathComponent("develop.txt"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "develop.txt"], in: fixture.updaterURL)
        try git(["commit", "-m", "Develop update"], in: fixture.updaterURL)
        try git(["push", "-u", "origin", "develop"], in: fixture.updaterURL)
        try git(["fetch", "origin", "develop"], in: fixture.localURL)
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            mainBranch: "main",
            developBranch: "develop"
        )

        let status = await GitStatusService.shared.currentBranchIntegrationStatus(
            branch: "feature/demo",
            preferredRemote: "origin",
            gitFlowConfiguration: configuration,
            in: fixture.localURL
        )

        XCTAssertEqual(status?.baseBranch, "develop")
        XCTAssertEqual(status?.baseRef, "origin/develop")
        XCTAssertEqual(status?.baseBehindCount, 2)
    }

    func testUpdateMergesBaseIntoCurrentBranchAndRegistersUndo() async throws {
        let fixture = try makeFixture(conflictingBaseChange: false)
        let loadedStatus = await GitStatusService.shared.currentBranchIntegrationStatus(
            branch: "feature/demo",
            preferredRemote: "origin",
            gitFlowConfiguration: GitFlowConfiguration(),
            in: fixture.localURL
        )
        let status = try XCTUnwrap(loadedStatus)
        let syncState = SyncState()
        let undoManager = GitUndoManager()

        await syncState.performCurrentBranchIntegrationUpdate(
            status: status,
            preferredRemote: "origin",
            gitFlowConfiguration: GitFlowConfiguration(),
            pullStrategy: .merge,
            repositoryURL: fixture.localURL,
            undoManager: undoManager
        )

        XCTAssertEqual(try gitOutput(["branch", "--show-current"], in: fixture.localURL), "feature/demo")
        XCTAssertEqual(try gitStatus(["merge-base", "--is-ancestor", "origin/main", "HEAD"], in: fixture.localURL), 0)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoStack.last?.label, "Update feature/demo")
    }

    private func makeFixture(conflictingBaseChange: Bool) throws -> IntegrationFixture {
        try makeFixture(
            featureChangesSharedFile: conflictingBaseChange,
            baseChangesSharedFile: conflictingBaseChange
        )
    }

    private func makeFixture(
        featureChangesSharedFile: Bool,
        baseChangesSharedFile: Bool
    ) throws -> IntegrationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-current-branch-integration-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let seedURL = rootURL.appendingPathComponent("seed", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)
        let updaterURL = rootURL.appendingPathComponent("updater", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try git(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try git(["init", "--initial-branch=main", seedURL.path], in: rootURL)
        try configureGit(in: seedURL)
        let sharedFile = seedURL.appendingPathComponent("shared.txt")
        try "base\n".write(to: sharedFile, atomically: true, encoding: .utf8)
        try git(["add", "shared.txt"], in: seedURL)
        try git(["commit", "-m", "Initial"], in: seedURL)
        try git(["remote", "add", "origin", originURL.path], in: seedURL)
        try git(["push", "-u", "origin", "main"], in: seedURL)

        try git(["clone", originURL.path, localURL.path], in: rootURL)
        try git(["clone", originURL.path, updaterURL.path], in: rootURL)
        try configureGit(in: localURL)
        try configureGit(in: updaterURL)

        try git(["checkout", "-b", "feature/demo"], in: localURL)
        if featureChangesSharedFile {
            try "feature\n".write(
                to: localURL.appendingPathComponent("shared.txt"),
                atomically: true,
                encoding: .utf8
            )
        } else {
            try "feature\n".write(
                to: localURL.appendingPathComponent("feature.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        try git(["add", "."], in: localURL)
        try git(["commit", "-m", "Feature"], in: localURL)
        try git(["push", "-u", "origin", "feature/demo"], in: localURL)

        if baseChangesSharedFile {
            try "main\n".write(
                to: updaterURL.appendingPathComponent("shared.txt"),
                atomically: true,
                encoding: .utf8
            )
        } else {
            try "main\n".write(
                to: updaterURL.appendingPathComponent("main.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        try git(["add", "."], in: updaterURL)
        try git(["commit", "-m", "Main update"], in: updaterURL)
        try git(["push"], in: updaterURL)
        try git(["fetch", "origin", "main"], in: localURL)

        return IntegrationFixture(localURL: localURL, updaterURL: updaterURL)
    }

    private func configureGit(in repositoryURL: URL) throws {
        try git(["config", "user.name", "Commit Plus Tests"], in: repositoryURL)
        try git(["config", "user.email", "tests@example.com"], in: repositoryURL)
    }

    @discardableResult
    private func git(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let result = try runGit(arguments, in: repositoryURL)
        guard result.status == 0 else {
            throw GitError.commandFailed(result.output)
        }
        return result.output
    }

    private func gitOutput(_ arguments: [String], in repositoryURL: URL) throws -> String {
        try git(arguments, in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitStatus(_ arguments: [String], in repositoryURL: URL) throws -> Int32 {
        try runGit(arguments, in: repositoryURL).status
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        return (process.terminationStatus, error.isEmpty ? output : error)
    }
}

private struct IntegrationFixture {
    let localURL: URL
    let updaterURL: URL
}
