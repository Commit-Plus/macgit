import XCTest
@testable import macgit

@MainActor
final class GitUndoManagerTests: XCTestCase {
    func testRegisterAddsUndoEntryAndClearsRedoStack() {
        let manager = GitUndoManager()
        let first = entry(label: "Stage README.md")
        let second = entry(label: "Stage App.swift")

        manager.register(first)
        let popped = manager.popForUndo()
        XCTAssertEqual(popped, first)
        manager.completeUndo(first)
        XCTAssertEqual(manager.redoStack, [first])

        manager.register(second)

        XCTAssertEqual(manager.undoStack, [second])
        XCTAssertTrue(manager.redoStack.isEmpty)
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.undoTitle, "Undo Stage App.swift")
        XCTAssertEqual(manager.redoTitle, "Redo Git Action")
    }

    func testUndoAndRedoStackTransitionsPreserveEntryOrder() {
        let manager = GitUndoManager()
        let first = entry(label: "Stage README.md")
        let second = entry(label: "Unstage App.swift")

        manager.register(first)
        manager.register(second)

        XCTAssertEqual(manager.popForUndo(), second)
        manager.completeUndo(second)
        XCTAssertEqual(manager.undoStack, [first])
        XCTAssertEqual(manager.redoStack, [second])
        XCTAssertEqual(manager.popForRedo(), second)
        manager.completeRedo(second)
        XCTAssertEqual(manager.undoStack, [first, second])
        XCTAssertTrue(manager.redoStack.isEmpty)
    }

    func testFailedUndoRestoresEntryToUndoStack() {
        let manager = GitUndoManager()
        let first = entry(label: "Stage README.md")
        let second = entry(label: "Stage App.swift")

        manager.register(first)
        manager.register(second)

        let popped = manager.popForUndo()
        XCTAssertEqual(popped, second)
        manager.restoreUndo(second)

        XCTAssertEqual(manager.undoStack, [first, second])
        XCTAssertTrue(manager.redoStack.isEmpty)
    }

    func testFailedRedoRestoresEntryToRedoStack() {
        let manager = GitUndoManager()
        let first = entry(label: "Stage README.md")

        manager.register(first)
        let popped = manager.popForUndo()
        XCTAssertEqual(popped, first)
        manager.completeUndo(first)

        let redo = manager.popForRedo()
        XCTAssertEqual(redo, first)
        manager.restoreRedo(first)

        XCTAssertTrue(manager.undoStack.isEmpty)
        XCTAssertEqual(manager.redoStack, [first])
    }

    func testFactoryBuildsStageAndUnstageEntriesWithStablePathOrder() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let stage = GitUndoEntryFactory.stageFiles(
            repositoryURL: repoURL,
            paths: ["Sources/App.swift", "README.md", "Sources/App.swift"]
        )
        let unstage = GitUndoEntryFactory.unstageFiles(
            repositoryURL: repoURL,
            paths: ["README.md"]
        )

        XCTAssertEqual(stage.repositoryURL, repoURL)
        XCTAssertEqual(stage.label, "Stage 2 files")
        XCTAssertEqual(stage.undoOperation, .unstageFiles(paths: ["Sources/App.swift", "README.md"]))
        XCTAssertEqual(stage.redoOperation, .stageFiles(paths: ["Sources/App.swift", "README.md"]))

        XCTAssertEqual(unstage.label, "Unstage README.md")
        XCTAssertEqual(unstage.undoOperation, .stageFiles(paths: ["README.md"]))
        XCTAssertEqual(unstage.redoOperation, .unstageFiles(paths: ["README.md"]))
    }

    func testFactoryBuildsPatchEntryWithReverseUndoOperation() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let entry = GitUndoEntryFactory.applyPatch(
            repositoryURL: repoURL,
            label: "Stage hunk in README.md",
            patch: "patch text",
            cached: true,
            reverse: false
        )

        XCTAssertEqual(entry.repositoryURL, repoURL)
        XCTAssertEqual(entry.label, "Stage hunk in README.md")
        XCTAssertEqual(entry.undoOperation, .applyPatch(patch: "patch text", cached: true, reverse: true))
        XCTAssertEqual(entry.redoOperation, .applyPatch(patch: "patch text", cached: true, reverse: false))
    }

    func testFactoryBuildsCommitEntryWithSoftResetUndoOperation() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let entry = GitUndoEntryFactory.commit(
            repositoryURL: repoURL,
            oldHead: "old-head",
            newHead: "new-head",
            message: "ship it",
            noVerify: true,
            signOff: true
        )

        XCTAssertEqual(entry.repositoryURL, repoURL)
        XCTAssertEqual(entry.label, "Commit")
        XCTAssertEqual(entry.undoOperation, .resetHead(target: "old-head", mode: .soft, expectedHead: "new-head"))
        XCTAssertEqual(entry.redoOperation, .commit(message: "ship it", noVerify: true, signOff: true))
    }

    private func entry(label: String) -> GitUndoEntry {
        GitUndoEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            repositoryURL: URL(fileURLWithPath: "/tmp/repo"),
            label: label,
            undoOperation: .unstageFiles(paths: ["README.md"]),
            redoOperation: .stageFiles(paths: ["README.md"])
        )
    }
}
