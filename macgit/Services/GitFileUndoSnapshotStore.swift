//
//  GitFileUndoSnapshotStore.swift
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
        GitUndoSnapshotRegistry.shared.register(snapshotID)
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
        GitUndoSnapshotRegistry.shared.unregister(snapshotID)
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
