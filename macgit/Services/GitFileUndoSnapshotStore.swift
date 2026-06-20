//
//  GitFileUndoSnapshotStore.swift
//  macgit
//

import Foundation

struct GitFileUndoSnapshotStore {
    private let fileManager = FileManager.default

    func capture(paths: [String], in repositoryURL: URL) throws -> GitFileUndoSnapshot {
        let snapshotID = UUID()
        let directory = snapshotDirectory(snapshotID, in: repositoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let items = try paths.map { path in
            let source = repositoryURL.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: source.path) else {
                return GitFileUndoSnapshotItem(path: path, existed: false, backupRelativePath: nil)
            }

            let backupRelativePath = "files/\(path)"
            let backupURL = directory.appendingPathComponent(backupRelativePath)
            try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: source, to: backupURL)
            return GitFileUndoSnapshotItem(path: path, existed: true, backupRelativePath: backupRelativePath)
        }

        let snapshot = GitFileUndoSnapshot(id: snapshotID, items: items)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: manifestURL(snapshotID, in: repositoryURL), options: .atomic)
        return snapshot
    }

    func restore(snapshotID: UUID, in repositoryURL: URL) throws {
        let data = try Data(contentsOf: manifestURL(snapshotID, in: repositoryURL))
        let snapshot = try JSONDecoder().decode(GitFileUndoSnapshot.self, from: data)

        for item in snapshot.items {
            let destination = repositoryURL.appendingPathComponent(item.path)
            if item.existed, let backupRelativePath = item.backupRelativePath {
                let backup = snapshotDirectory(snapshotID, in: repositoryURL).appendingPathComponent(backupRelativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: backup, to: destination)
            } else if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }
    }

    func delete(snapshotID: UUID, in repositoryURL: URL) throws {
        let directory = snapshotDirectory(snapshotID, in: repositoryURL)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func undoRoot(in repositoryURL: URL) -> URL {
        repositoryURL.appendingPathComponent(".git/macgit/undo", isDirectory: true)
    }

    private func snapshotDirectory(_ id: UUID, in repositoryURL: URL) -> URL {
        undoRoot(in: repositoryURL).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(_ id: UUID, in repositoryURL: URL) -> URL {
        snapshotDirectory(id, in: repositoryURL).appendingPathComponent("manifest.json")
    }
}
