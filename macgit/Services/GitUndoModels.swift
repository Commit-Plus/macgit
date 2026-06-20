//
//  GitUndoModels.swift
//  macgit
//

import Foundation
import Combine
import SwiftUI

enum GitUndoResetMode: Equatable {
    case soft
    case mixed
    case hard

    var flag: String {
        switch self {
        case .soft: return "--soft"
        case .mixed: return "--mixed"
        case .hard: return "--hard"
        }
    }
}

enum GitUndoOperation: Equatable {
    case stageFiles(paths: [String])
    case unstageFiles(paths: [String])
    case applyPatch(patch: String, cached: Bool, reverse: Bool)
    case resetHead(target: String, mode: GitUndoResetMode, expectedHead: String?)
    case commit(message: String, noVerify: Bool, signOff: Bool)
}

struct GitUndoEntry: Identifiable, Equatable {
    let id: UUID
    let repositoryURL: URL
    let label: String
    let undoOperation: GitUndoOperation
    let redoOperation: GitUndoOperation

    init(
        id: UUID = UUID(),
        repositoryURL: URL,
        label: String,
        undoOperation: GitUndoOperation,
        redoOperation: GitUndoOperation
    ) {
        self.id = id
        self.repositoryURL = repositoryURL
        self.label = label
        self.undoOperation = undoOperation
        self.redoOperation = redoOperation
    }
}

enum GitUndoEntryFactory {
    static func stageFiles(repositoryURL: URL, paths: [String]) -> GitUndoEntry {
        let normalizedPaths = normalized(paths)
        return GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label(verb: "Stage", paths: normalizedPaths),
            undoOperation: .unstageFiles(paths: normalizedPaths),
            redoOperation: .stageFiles(paths: normalizedPaths)
        )
    }

    static func unstageFiles(repositoryURL: URL, paths: [String]) -> GitUndoEntry {
        let normalizedPaths = normalized(paths)
        return GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label(verb: "Unstage", paths: normalizedPaths),
            undoOperation: .stageFiles(paths: normalizedPaths),
            redoOperation: .unstageFiles(paths: normalizedPaths)
        )
    }

    static func applyPatch(
        repositoryURL: URL,
        label: String,
        patch: String,
        cached: Bool,
        reverse: Bool
    ) -> GitUndoEntry {
        GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label,
            undoOperation: .applyPatch(patch: patch, cached: cached, reverse: !reverse),
            redoOperation: .applyPatch(patch: patch, cached: cached, reverse: reverse)
        )
    }

    static func commit(
        repositoryURL: URL,
        oldHead: String,
        newHead: String,
        message: String,
        noVerify: Bool,
        signOff: Bool
    ) -> GitUndoEntry {
        GitUndoEntry(
            repositoryURL: repositoryURL,
            label: "Commit",
            undoOperation: .resetHead(target: oldHead, mode: .soft, expectedHead: newHead),
            redoOperation: .commit(message: message, noVerify: noVerify, signOff: signOff)
        )
    }

    private static func normalized(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result
    }

    private static func label(verb: String, paths: [String]) -> String {
        if paths.count == 1, let path = paths.first {
            return "\(verb) \((path as NSString).lastPathComponent)"
        }
        return "\(verb) \(paths.count) files"
    }
}

@MainActor
final class GitUndoManager: ObservableObject {
    @Published private(set) var undoStack: [GitUndoEntry] = []
    @Published private(set) var redoStack: [GitUndoEntry] = []

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var undoTitle: String {
        guard let entry = undoStack.last else { return "Undo Git Action" }
        return "Undo \(entry.label)"
    }

    var redoTitle: String {
        guard let entry = redoStack.last else { return "Redo Git Action" }
        return "Redo \(entry.label)"
    }

    func register(_ entry: GitUndoEntry) {
        undoStack.append(entry)
        redoStack.removeAll()
    }

    func popForUndo() -> GitUndoEntry? {
        undoStack.popLast()
    }

    func completeUndo(_ entry: GitUndoEntry) {
        redoStack.append(entry)
    }

    func restoreUndo(_ entry: GitUndoEntry) {
        undoStack.append(entry)
    }

    func popForRedo() -> GitUndoEntry? {
        redoStack.popLast()
    }

    func completeRedo(_ entry: GitUndoEntry) {
        undoStack.append(entry)
    }

    func restoreRedo(_ entry: GitUndoEntry) {
        redoStack.append(entry)
    }

    func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
